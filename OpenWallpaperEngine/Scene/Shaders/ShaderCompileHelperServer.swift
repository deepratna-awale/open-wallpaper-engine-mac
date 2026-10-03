import Foundation
import Darwin

/// The shader compile helper: a copy of the app's executable run with `--shader-compile-helper`
/// (`ShaderPrewarmCommand`), which translates shaders for the app that started it
/// (`HelperShaderCompiler`), so a crash or hang in glslang or SPIRV-Cross takes down the helper
/// instead of the app.
///
/// Requests come in on stdin and responses go out on the original stdout, both as
/// `ShaderCompileHelperFrame`s. The libraries' own prints are sent to stderr (the null device), so
/// they can't corrupt the stream. The helper exits when stdin closes (the app quit or died) and
/// after answering a request its compile thread hung on (`ShaderCompileThread.isStuck`).
enum ShaderCompileHelperServer {
    static let argument = "--shader-compile-helper"
    /// Exit status after a hung compile.
    static let stuckStatus: Int32 = 3

    /// Serves requests until stdin closes; returns the exit status.
    static func run() -> Int32 {
        let responses = dup(STDOUT_FILENO)
        guard responses >= 0, dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
            OWELog.error(.shader, "Shader compile helper: can't set up its output (errno \(errno))")
            return 1
        }
        // Compiles assert they run off the main thread (`ThreadGuards`), and glslang needs a big stack.
        var status: Int32 = 0
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            status = serve(input: FileHandle.standardInput,
                           output: FileHandle(fileDescriptor: responses, closeOnDealloc: true),
                           compiler: ShaderCompilerFactory.makeDefault())
            done.signal()
        }
        thread.name = "OWE shader compile helper"
        thread.stackSize = ShaderCompileThread.stackSize
        thread.qualityOfService = .userInitiated
        thread.start()
        done.wait()
        return status
    }

    static func serve(input: FileHandle, output: FileHandle, compiler: ShaderCompiler) -> Int32 {
        OWELog.info(.shader, "Shader compile helper started (pid \(ProcessInfo.processInfo.processIdentifier))")
        var buffer = Data()
        while true {
            do {
                guard let payload = try nextFrame(input, buffer: &buffer) else { return 0 }
                let request = try JSONDecoder().decode(ShaderCompileHelperMessage.Request.self, from: payload)
                var response = handle(request, compiler: compiler)
                let stuck = (compiler as? InProcessShaderCompiler)?.isStuck ?? false
                response.exiting = stuck
                try output.write(contentsOf: ShaderCompileHelperFrame.encode(response))
                if stuck {
                    OWELog.error(.shader, "Shader compile helper: a compile hung; exiting so the app starts a new helper")
                    return stuckStatus
                }
            } catch {
                OWELog.error(.shader, "Shader compile helper: broken request stream: \(error)")
                return 1
            }
        }
    }

    /// Runs one request on `compiler`.
    static func handle(_ request: ShaderCompileHelperMessage.Request,
                       compiler: ShaderCompiler) -> ShaderCompileHelperMessage.Response {
        let started = DispatchTime.now().uptimeNanoseconds
        var response = ShaderCompileHelperMessage.Response(id: request.id, text: nil, reflection: nil, failure: nil,
                                                           computeNanoseconds: 0, exiting: false)
        do {
            switch request.operation {
            case .preprocess:
                response.text = try compiler.preprocess(request.source, stage: request.stage)
            case .compileToMSL:
                let output = try compiler.compileToMSL(request.source, stage: request.stage)
                response.text = output.msl
                response.reflection = output.reflection
            }
        } catch ShaderCompilerError.failed(let step, let output) {
            response.failure = .init(step: step, output: output, quarantined: false)
        } catch ShaderCompilerError.quarantined(let step) {
            response.failure = .init(step: step, output: "", quarantined: true)
        } catch {
            response.failure = .init(step: request.operation.rawValue, output: "\(error)", quarantined: false)
        }
        response.computeNanoseconds = DispatchTime.now().uptimeNanoseconds - started
        return response
    }

    /// The next request's payload, or nil once stdin closed.
    private static func nextFrame(_ input: FileHandle, buffer: inout Data) throws -> Data? {
        while true {
            if let payload = try ShaderCompileHelperFrame.take(from: &buffer) { return payload }
            guard let chunk = try input.read(upToCount: 1 << 16), !chunk.isEmpty else { return nil }
            buffer.append(chunk)
        }
    }
}
