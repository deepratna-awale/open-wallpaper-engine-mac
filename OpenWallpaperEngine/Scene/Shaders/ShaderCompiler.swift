import Foundation

enum ShaderCompilerError: Error, CustomStringConvertible {
    case failed(step: String, output: String)
    /// This shader's compile killed or hung an earlier run (`InProcessCompileCrashGuard`); it is
    /// skipped so the rest of the scene still compiles.
    case quarantined(step: String)

    var description: String {
        switch self {
        case .failed(let step, let output): return "\(step) failed: \(output)"
        case .quarantined(let step):
            return "\(step) skipped: this shader killed or hung the app in an earlier run "
                + "(quarantined until the shader libraries change)"
        }
    }
}

/// The GLSL → SPIR-V → MSL toolchain. The app uses `InProcessShaderCompiler` (glslang and
/// SPIRV-Cross linked in); tests substitute their own.
protocol ShaderCompiler {
    /// Identifies everything that decides the output: backend, library versions and options.
    /// Part of the variant cache key; never machine-specific (no paths or dates).
    var cacheFingerprint: String { get }
    /// Runs the GLSL preprocessor only, resolving every `#if` against the defined macros.
    func preprocess(_ source: String, stage: ShaderStage) throws -> String
    /// Compiles preprocessed, fully decorated GLSL to MSL and returns it with SPIRV-Cross's
    /// reflection JSON.
    func compileToMSL(_ source: String, stage: ShaderStage) throws -> (msl: String, reflection: Data)
}

/// Makes the app's shader compiler: the linked libraries, guarded against shaders that crashed
/// or hung them in an earlier run.
enum ShaderCompilerFactory {
    static func makeDefault(stateDirectory: URL? = ShaderVariantTranslator.defaultCacheDirectory?
        .deletingLastPathComponent().appending(path: "shader-compiler", directoryHint: .isDirectory)) -> ShaderCompiler {
        guard let stateDirectory else { return InProcessShaderCompiler() }
        let crashGuard = InProcessCompileCrashGuard(directory: stateDirectory,
                                                    fingerprint: InProcessShaderCompiler.libraryFingerprint)
        crashGuard.collectDeaths()
        return InProcessShaderCompiler(crashGuard: crashGuard)
    }
}
