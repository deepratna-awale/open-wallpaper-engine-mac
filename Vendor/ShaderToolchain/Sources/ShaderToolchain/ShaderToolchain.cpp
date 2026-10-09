#include "ShaderToolchain.h"

#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

#include "glslang/Public/ShaderLang.h"
#include "glslang/Public/ResourceLimits.h"
#include "SPIRV/GlslangToSpv.h"

#include "spirv_msl.hpp"
#include "spirv_parser.hpp"
#include "spirv_reflect.hpp"

// The SPIRV-Cross release the sources in ../../SPIRV-Cross were taken from (it has no runtime
// version query). Keep in sync with README.md.
#define OWE_SPIRV_CROSS_VERSION "vulkan-sdk-1.4.357.0"
// The fixed options below; change this string whenever they change.
#define OWE_SHADER_OPTIONS "E:none;G:opengl450-spv1.0-msgspv;pair:vulkan100-relaxed-linked-WEUniforms0-spv1.0;rename:metal-clashes-we_;msl20300+decoration-binding;vert:fixup-clipspace+flip-vert-y"

namespace {

std::mutex &compileLock() {
    static std::mutex lock;
    return lock;
}

void initializeOnce() {
    // Never finalized: the library stays usable for the life of the process.
    static std::once_flag once;
    std::call_once(once, [] { glslang::InitializeProcess(); });
}

char *copy(const std::string &text) {
    char *result = static_cast<char *>(std::malloc(text.size() + 1));
    if (result) std::memcpy(result, text.c_str(), text.size() + 1);
    return result;
}

EShLanguage language(owe_shader_stage stage) {
    return stage == OWE_SHADER_STAGE_VERTEX ? EShLangVertex : EShLangFragment;
}

// glslangValidator's DirStackFileIncluder with no directories: WE sources have their includes
// inlined before they get here, so every #include fails, as it does for the command line tool.
class NoIncluder : public glslang::TShader::Includer {
public:
    IncludeResult *includeSystem(const char *, const char *, size_t) override { return nullptr; }
    IncludeResult *includeLocal(const char *, const char *, size_t) override { return nullptr; }
    void releaseInclude(IncludeResult *) override {}
};

// glslangValidator names its input by file path; the scratch file was always "shader.<stage>".
const char *fileName(owe_shader_stage stage) {
    return stage == OWE_SHADER_STAGE_VERTEX ? "shader.vert" : "shader.frag";
}

std::string infoLog(glslang::TShader &shader) {
    return std::string(shader.getInfoLog()) + shader.getInfoDebugLog();
}

// StandAlone.cpp: `-E` sets no client, messages = EShMsgOnlyPreprocessor, default version 100.
bool preprocess(const char *source, owe_shader_stage stage, std::string &output, std::string &log) {
    glslang::TShader shader(language(stage));
    const char *strings[] = {source};
    const char *names[] = {fileName(stage)};
    shader.setStringsWithLengthsAndNames(strings, nullptr, names, 1);
    shader.setPreamble("");
    NoIncluder includer;
    std::string text;
    bool ok = shader.preprocess(GetDefaultResources(), 100, ENoProfile, false, false,
                                EShMsgOnlyPreprocessor, &text, includer);
    log = infoLog(shader);
    // glslangValidator prints the result with puts(), which appends a newline.
    if (ok && !text.empty()) output = text + "\n";
    return ok;
}

// StandAlone.cpp: `-G` = OpenGL client 4.50, SPIR-V 1.0, messages = EShMsgSpvRules, a linked
// program, mapIO(), then GlslangToSpv with default options.
bool compileSpirv(const char *source, owe_shader_stage stage, std::vector<unsigned int> &spirv, std::string &log) {
    EShLanguage lang = language(stage);
    glslang::TShader shader(lang);
    const char *strings[] = {source};
    const char *names[] = {fileName(stage)};
    shader.setStringsWithLengthsAndNames(strings, nullptr, names, 1);
    shader.setPreamble("");
    shader.setEnvInput(glslang::EShSourceGlsl, lang, glslang::EShClientOpenGL, 100);
    shader.setEnvClient(glslang::EShClientOpenGL, glslang::EShTargetOpenGL_450);
    shader.setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_0);
    NoIncluder includer;
    const EShMessages messages = EShMsgSpvRules;
    if (!shader.parse(GetDefaultResources(), 100, false, messages, includer)) {
        log = infoLog(shader);
        return false;
    }
    glslang::TProgram program;
    program.addShader(&shader);
    if (!program.link(messages) || !program.mapIO()) {
        log = infoLog(shader) + program.getInfoLog() + program.getInfoDebugLog();
        return false;
    }
    glslang::SpvOptions options;
    options.compilerSignature = "glslang";
    spv::SpvBuildLogger logger;
    glslang::GlslangToSpv(*program.getIntermediate(lang), spirv, &logger, &options);
    return true;
}

// The pair as one program under glslang's relaxed Vulkan rules (GL_KHR_vulkan_glsl's relaxations,
// `--relaxed-rules-vulkan`): WE declares its constants as loose uniforms, which strict GLSL for
// SPIR-V rejects; relaxed, glslang gathers them into one default block, here named
// `WEUniforms` at binding 0, and linking both stages merges the block, so each stage reads the
// same std140 layout (vertex stage's members first). Uniform initialisers are ignored, as
// WE's cbuffers have none.
void configure(glslang::TShader &shader, EShLanguage lang, const char *const *strings, const char *const *names) {
    shader.setStringsWithLengthsAndNames(strings, nullptr, names, 1);
    shader.setPreamble("");
    shader.setEnvInput(glslang::EShSourceGlsl, lang, glslang::EShClientVulkan, 100);
    shader.setEnvInputVulkanRulesRelaxed();
    shader.setEnvClient(glslang::EShClientVulkan, glslang::EShTargetVulkan_1_0);
    shader.setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_0);
    shader.setGlobalUniformBlockName("WEUniforms");
    shader.setGlobalUniformSet(0);
    shader.setGlobalUniformBinding(0);
}

bool compilePairSpirv(const char *vertexSource, const char *fragmentSource, std::vector<unsigned int> &vertexSpirv,
                      std::vector<unsigned int> &fragmentSpirv, std::string &log, int &failedStage) {
    const char *vertexStrings[] = {vertexSource};
    const char *fragmentStrings[] = {fragmentSource};
    const char *vertexNames[] = {fileName(OWE_SHADER_STAGE_VERTEX)};
    const char *fragmentNames[] = {fileName(OWE_SHADER_STAGE_FRAGMENT)};
    glslang::TShader vertex(EShLangVertex);
    glslang::TShader fragment(EShLangFragment);
    configure(vertex, EShLangVertex, vertexStrings, vertexNames);
    configure(fragment, EShLangFragment, fragmentStrings, fragmentNames);
    NoIncluder includer;
    const EShMessages messages = static_cast<EShMessages>(EShMsgSpvRules | EShMsgVulkanRules);
    if (!vertex.parse(GetDefaultResources(), 100, false, messages, includer)) {
        log = infoLog(vertex);
        failedStage = OWE_SHADER_STAGE_VERTEX;
        return false;
    }
    if (!fragment.parse(GetDefaultResources(), 100, false, messages, includer)) {
        log = infoLog(fragment);
        failedStage = OWE_SHADER_STAGE_FRAGMENT;
        return false;
    }
    glslang::TProgram program;
    program.addShader(&vertex);
    program.addShader(&fragment);
    if (!program.link(messages) || !program.mapIO()) {
        log = infoLog(vertex) + infoLog(fragment) + program.getInfoLog() + program.getInfoDebugLog();
        failedStage = -1;
        return false;
    }
    glslang::SpvOptions options;
    options.compilerSignature = "glslang";
    spv::SpvBuildLogger logger;
    glslang::GlslangToSpv(*program.getIntermediate(EShLangVertex), vertexSpirv, &logger, &options);
    glslang::GlslangToSpv(*program.getIntermediate(EShLangFragment), fragmentSpirv, &logger, &options);
    return true;
}

// Names GLSL lets a shader use that MSL (C++) reserves or Metal's standard library declares, so
// a WE shader's own `or`, `this` or `log10` would not compile as MSL. They are renamed `we_<name>`
// in the SPIR-V's debug names (OpName, OpMemberName) the MSL is written from; the reflection
// reads the original SPIR-V, so constants still bind by WE's names. A function's name is
// glslang's mangled `name(args`.
const std::unordered_set<std::string> &metalClashes() {
    static const std::unordered_set<std::string> names = {
        "and", "or", "xor", "bitand", "bitor", "compl", "and_eq", "or_eq", "xor_eq", "not_eq",
        "template", "namespace", "this", "new", "delete", "operator", "class", "typename", "private",
        "public", "protected", "friend", "virtual", "register", "auto", "explicit", "mutable", "using",
        "typedef", "union", "enum", "extern", "static", "goto", "try", "catch", "throw", "sizeof",
        "alignas", "alignof", "decltype", "constexpr", "nullptr", "static_assert", "thread_local",
        "noexcept", "char", "short", "long", "signed", "unsigned", "wchar_t", "typeid", "export",
        "concept", "requires", "device", "constant", "thread", "threadgroup", "kernel", "vertex", "fragment",
        // Metal standard library functions GLSL lacks: a shader's own definition is ambiguous.
        "log10", "fmod", "rsqrt", "saturate", "fract2", "powr", "select", "median3",
    };
    return names;
}

std::vector<uint32_t> renameMetalClashes(const std::vector<uint32_t> &words) {
    const uint32_t opName = 5, opMemberName = 6;
    if (words.size() < 5) return words;
    std::vector<uint32_t> result(words.begin(), words.begin() + 5);
    result.reserve(words.size());
    size_t index = 5;
    while (index < words.size()) {
        uint32_t count = words[index] >> 16, opcode = words[index] & 0xffff;
        if (count == 0 || index + count > words.size()) {
            result.insert(result.end(), words.begin() + index, words.end());
            break;
        }
        size_t operands = opcode == opName ? 1 : opcode == opMemberName ? 2 : 0;
        if (operands > 0 && count > operands + 1) {
            const char *text = reinterpret_cast<const char *>(&words[index + 1 + operands]);
            size_t limit = (count - 1 - operands) * 4;
            std::string name(text, strnlen(text, limit));
            if (metalClashes().count(name.substr(0, name.find('(')))) {
                std::string renamed = "we_" + name;
                std::vector<uint32_t> string(renamed.size() / 4 + 1, 0);
                std::memcpy(string.data(), renamed.data(), renamed.size());
                uint32_t total = static_cast<uint32_t>(1 + operands + string.size());
                result.push_back(total << 16 | opcode);
                result.insert(result.end(), words.begin() + index + 1, words.begin() + index + 1 + operands);
                result.insert(result.end(), string.begin(), string.end());
                index += count;
                continue;
            }
        }
        result.insert(result.end(), words.begin() + index, words.begin() + index + count);
        index += count;
    }
    return result;
}

// spirv-cross main.cpp `compile_iteration` with the CLI defaults and our three flags.
std::string compileMSL(std::vector<uint32_t> spirv, owe_shader_stage stage) {
    using namespace SPIRV_CROSS_NAMESPACE;
    Parser parser(renameMetalClashes(spirv));
    parser.parse();
    CompilerMSL compiler(std::move(parser.get_parsed_ir()));

    auto msl = compiler.get_msl_options();
    msl.msl_version = 20300;
    msl.capture_output_to_buffer = false;
    msl.swizzle_texture_samples = false;
    msl.invariant_float_math = false;
    msl.pad_fragment_output_components = false;
    msl.tess_domain_origin_lower_left = false;
    msl.argument_buffers = false;
    msl.argument_buffers_tier = CompilerMSL::Options::ArgumentBuffersTier::Tier1;
    msl.texture_buffer_native = false;
    msl.multiview = false;
    msl.multiview_layered_rendering = true;
    msl.view_index_from_device_index = false;
    msl.dispatch_base = false;
    msl.enable_decoration_binding = true;
    msl.force_active_argument_buffer_resources = false;
    msl.force_native_arrays = false;
    msl.enable_frag_depth_builtin = true;
    msl.enable_frag_stencil_ref_builtin = true;
    msl.enable_frag_output_mask = 0xffffffff;
    msl.enable_clip_distance_user_varying = true;
    msl.raw_buffer_tese_input = false;
    msl.multi_patch_workgroup = false;
    msl.vertex_for_tessellation = false;
    msl.additional_fixed_sample_mask = 0xffffffff;
    msl.arrayed_subpass_input = false;
    msl.r32ui_linear_texture_alignment = 4;
    msl.r32ui_alignment_constant_id = 65535;
    msl.texture_1D_as_2D = false;
    msl.ios_use_simdgroup_functions = false;
    msl.emulate_subgroups = false;
    msl.fixed_subgroup_size = 0;
    msl.force_sample_rate_shading = false;
    msl.manual_helper_invocation_updates = true;
    msl.check_discarded_frag_stores = false;
    msl.force_fragment_with_side_effects_execution = false;
    msl.emulate_reversed_depth_viewport = false;
    msl.sample_dref_lod_array_as_grad = false;
    msl.ios_support_base_vertex_instance = true;
    msl.runtime_array_rich_descriptor = false;
    msl.replace_recursive_inputs = false;
    msl.input_attachment_is_ds_attachment = false;
    msl.readwrite_texture_fences = true;
    msl.agx_manual_cube_grad_fixup = false;
    msl.disable_rasterization = false;
    msl.auto_disable_rasterization = false;
    msl.enable_point_size_default = false;
    msl.default_point_size = 1.0f;
    compiler.set_msl_options(msl);

    auto common = compiler.get_common_options();
    common.force_temporary = false;
    common.separate_shader_objects = false;
    common.flatten_multidimensional_arrays = false;
    common.enable_420pack_extension = true;
    common.vulkan_semantics = false;
    common.vertex.fixup_clipspace = stage == OWE_SHADER_STAGE_VERTEX;
    common.vertex.flip_vert_y = stage == OWE_SHADER_STAGE_VERTEX;
    common.vertex.support_nonzero_base_instance = true;
    common.emit_push_constant_as_uniform_buffer = false;
    common.emit_uniform_buffer_as_plain_uniforms = false;
    common.force_flattened_io_blocks = false;
    common.ovr_multiview_view_count = 0;
    common.emit_line_directives = false;
    common.enable_storage_image_qualifier_deduction = true;
    common.force_zero_initialized_variables = false;
    common.relax_nan_checks = false;
    common.force_recompile_max_debug_iterations = 3;
    compiler.set_common_options(common);

    // Mirrors the CLI, which queries resources and remaps (no) pixel-local storage before compiling.
    (void)compiler.get_shader_resources();
    compiler.remap_pixel_local_storage({}, {});
    return compiler.compile();
}

std::string reflect(std::vector<uint32_t> spirv) {
    using namespace SPIRV_CROSS_NAMESPACE;
    Parser parser(std::move(spirv));
    parser.parse();
    CompilerReflection compiler(std::move(parser.get_parsed_ir()));
    compiler.set_format("json");
    return compiler.compile();
}

} // namespace

extern "C" int owe_shader_preprocess(const char *source, owe_shader_stage stage, char **output, char **log) {
    std::lock_guard<std::mutex> guard(compileLock());
    initializeOnce();
    std::string text, messages;
    if (!preprocess(source, stage, text, messages)) {
        *log = copy(messages);
        return 0;
    }
    *output = copy(text);
    return 1;
}

extern "C" int owe_shader_compile_msl(const char *source, owe_shader_stage stage, char **msl, char **reflection,
                                      char **log, const char **failed_step) {
    std::lock_guard<std::mutex> guard(compileLock());
    initializeOnce();
    std::vector<unsigned int> spirv;
    std::string messages;
    if (!compileSpirv(source, stage, spirv, messages)) {
        *failed_step = "glslang";
        *log = copy(messages);
        return 0;
    }
    std::vector<uint32_t> words(spirv.begin(), spirv.end());
    std::string mslText;
    try {
        mslText = compileMSL(words, stage);
    } catch (const std::exception &error) {
        *failed_step = "spirv-cross";
        *log = copy(error.what());
        return 0;
    }
    std::string json;
    try {
        json = reflect(words);
    } catch (const std::exception &error) {
        *failed_step = "reflect";
        *log = copy(error.what());
        return 0;
    }
    *msl = copy(mslText);
    *reflection = copy(json);
    return 1;
}

extern "C" int owe_shader_compile_pair_msl(const char *vertex, const char *fragment, char **vertex_msl,
                                           char **vertex_reflection, char **fragment_msl, char **fragment_reflection,
                                           char **log, const char **failed_step, int *failed_stage) {
    std::lock_guard<std::mutex> guard(compileLock());
    initializeOnce();
    std::vector<unsigned int> vertexSpirv, fragmentSpirv;
    std::string messages;
    int stage = -1;
    if (!compilePairSpirv(vertex, fragment, vertexSpirv, fragmentSpirv, messages, stage)) {
        *failed_step = "glslang";
        *failed_stage = stage;
        *log = copy(messages);
        return 0;
    }
    const std::vector<uint32_t> *spirvs[] = {nullptr, nullptr};
    std::vector<uint32_t> vertexWords(vertexSpirv.begin(), vertexSpirv.end());
    std::vector<uint32_t> fragmentWords(fragmentSpirv.begin(), fragmentSpirv.end());
    spirvs[0] = &vertexWords;
    spirvs[1] = &fragmentWords;
    std::string msl[2], json[2];
    for (int index = 0; index < 2; index++) {
        owe_shader_stage current = index == 0 ? OWE_SHADER_STAGE_VERTEX : OWE_SHADER_STAGE_FRAGMENT;
        *failed_stage = current;
        try {
            msl[index] = compileMSL(*spirvs[index], current);
        } catch (const std::exception &error) {
            *failed_step = "spirv-cross";
            *log = copy(error.what());
            return 0;
        }
        try {
            json[index] = reflect(*spirvs[index]);
        } catch (const std::exception &error) {
            *failed_step = "reflect";
            *log = copy(error.what());
            return 0;
        }
    }
    *vertex_msl = copy(msl[0]);
    *vertex_reflection = copy(json[0]);
    *fragment_msl = copy(msl[1]);
    *fragment_reflection = copy(json[1]);
    return 1;
}

extern "C" void owe_shader_free(char *string) { std::free(string); }

extern "C" const char *owe_shader_toolchain_fingerprint(void) {
    static const std::string fingerprint = [] {
        auto version = glslang::GetVersion();
        return "glslang " + std::to_string(version.major) + "." + std::to_string(version.minor) + "." +
               std::to_string(version.patch) + version.flavor + "|spirv-cross " OWE_SPIRV_CROSS_VERSION
               "|" OWE_SHADER_OPTIONS;
    }();
    return fingerprint.c_str();
}
