import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

// MARK: - Executable Language

enum ExecutableLanguage {
    case python, javascript, shell

    static func from(markdownLanguage: String?) -> ExecutableLanguage? {
        guard let lang = markdownLanguage?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        switch lang {
        case "python", "py", "python3":
            return .python
        case "javascript", "js", "node":
            return .javascript
        case "bash", "sh", "shell", "zsh":
            return .shell
        default:
            return nil
        }
    }

    var isAvailableOnCurrentPlatform: Bool {
        #if os(macOS)
        return true
        #else
        return self == .javascript
        #endif
    }

    var displayName: String {
        switch self {
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .shell: return "Shell"
        }
    }
}

// MARK: - Execution Result

struct CodeExecutionResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool
}

// MARK: - Code Execution Service

enum CodeExecutionService {
    private static let interactiveInputUnsupportedMessage =
    """
    Interactive input is not supported in inline Run.
    Use fixed sample values instead of reading from stdin/prompt.
    """

    static func execute(code: String, language: ExecutableLanguage, timeout: TimeInterval = 10) async -> CodeExecutionResult {
        #if os(macOS)
        return await executeMacOS(code: code, language: language, timeout: timeout)
        #else
        return await executeiOS(code: code, language: language)
        #endif
    }

    // MARK: - macOS — Process

    #if os(macOS)
    private static func executeMacOS(code: String, language: ExecutableLanguage, timeout: TimeInterval) async -> CodeExecutionResult {
        if requiresInteractiveInput(code: code, language: language) {
            return CodeExecutionResult(
                stdout: "",
                stderr: interactiveInputUnsupportedMessage,
                exitCode: 2,
                timedOut: false
            )
        }

        let (executablePath, arguments) = processInfo(for: language)

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Write code to stdin
            if let data = code.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()

            // Timeout killer
            var timedOut = false
            let killer = DispatchWorkItem {
                timedOut = true
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

            var stdoutData = Data()
            var stderrData = Data()
            let stdoutGroup = DispatchGroup()
            let stderrGroup = DispatchGroup()

            do {
                try process.run()

                // Close the parent's write handles; only the child should write to stdout/stderr.
                stdoutPipe.fileHandleForWriting.closeFile()
                stderrPipe.fileHandleForWriting.closeFile()

                stdoutGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    stdoutGroup.leave()
                }

                stderrGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    stderrGroup.leave()
                }

                process.waitUntilExit()
            } catch {
                killer.cancel()
                continuation.resume(returning: CodeExecutionResult(
                    stdout: "",
                    stderr: error.localizedDescription,
                    exitCode: -1,
                    timedOut: false
                ))
                return
            }

            killer.cancel()

            stdoutGroup.wait()
            stderrGroup.wait()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let normalizedStderr = normalizeInteractiveInputError(stderr: stderr, language: language)

            continuation.resume(returning: CodeExecutionResult(
                stdout: stdout,
                stderr: normalizedStderr,
                exitCode: process.terminationStatus,
                timedOut: timedOut
            ))
        }
    }

    private static func processInfo(for language: ExecutableLanguage) -> (String, [String]) {
        switch language {
        case .python:
            return ("/usr/bin/python3", ["-u", "-"])
        case .javascript:
            return ("/usr/bin/env", ["node", "--input-type=module", "-"])
        case .shell:
            return ("/bin/bash", ["-s"])
        }
    }
    #endif

    static func requiresInteractiveInput(code: String, language: ExecutableLanguage) -> Bool {
        let lower = code.lowercased()
        switch language {
        case .python:
            return lower.contains("input(")
                || lower.contains("raw_input(")
                || lower.contains("sys.stdin.readline(")
        case .javascript:
            return lower.contains("prompt(")
                || lower.contains("process.stdin")
                || lower.contains("readline.createinterface(")
        case .shell:
            return lower.contains("\nread ")
                || lower.hasPrefix("read ")
                || lower.contains("\nread\t")
                || lower.hasPrefix("read\t")
                || lower.contains("read -p")
        }
    }

    private static func normalizeInteractiveInputError(stderr: String, language: ExecutableLanguage) -> String {
        let lower = stderr.lowercased()
        switch language {
        case .python:
            if lower.contains("eoferror: eof when reading a line") {
                return interactiveInputUnsupportedMessage
            }
        case .javascript:
            if lower.contains("stdin") && lower.contains("end-of-file") {
                return interactiveInputUnsupportedMessage
            }
        case .shell:
            if lower.contains("read error") && lower.contains("0: bad file descriptor") {
                return interactiveInputUnsupportedMessage
            }
        }
        return stderr
    }

    // MARK: - iOS — JavaScriptCore

    #if os(iOS)
    private static func executeiOS(code: String, language: ExecutableLanguage) async -> CodeExecutionResult {
        guard language == .javascript else {
            return CodeExecutionResult(
                stdout: "",
                stderr: "\(language.displayName) is not available on iOS.",
                exitCode: -1,
                timedOut: false
            )
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ctx = JSContext()!
                var consoleOutput: [String] = []

                // Capture console.log
                let logFn: @convention(block) () -> Void = {
                    let args = JSContext.currentArguments()?.compactMap { ($0 as? JSValue)?.toString() } ?? []
                    consoleOutput.append(args.joined(separator: " "))
                }
                ctx.setObject(logFn, forKeyedSubscript: "$$log" as NSString)
                ctx.evaluateScript("var console = { log: $$log, warn: $$log, error: $$log, info: $$log };")

                // Capture exceptions
                var errorOutput = ""
                ctx.exceptionHandler = { _, value in
                    errorOutput = value?.toString() ?? "Unknown error"
                }

                let result = ctx.evaluateScript(code)

                // If the last expression produced a value, append it
                if errorOutput.isEmpty, let val = result, !val.isUndefined, !val.isNull {
                    let str = val.toString() ?? ""
                    if !str.isEmpty && !consoleOutput.contains(str) {
                        consoleOutput.append(str)
                    }
                }

                continuation.resume(returning: CodeExecutionResult(
                    stdout: consoleOutput.joined(separator: "\n"),
                    stderr: errorOutput,
                    exitCode: errorOutput.isEmpty ? 0 : 1,
                    timedOut: false
                ))
            }
        }
    }
    #endif
}
