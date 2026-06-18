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
    private static let inputExhaustedMessage =
    """
    Program requested more input than provided.
    Add one value per line in the Input panel and run again.
    """
    private static let inputExhaustedPartialMessage =
    """
    Program needed more input lines than provided.
    Add additional lines in the Input panel and run again.
    """
    private static let iOSJavaScriptNodeInputUnsupportedMessage =
    """
    Node-style interactive stdin/readline is not supported on iOS JavaScriptCore.
    Use prompt()/readLine() with Input values instead.
    """
    private static let jsCoreFallbackNodeAPIMessage =
    """
    This code uses Node.js APIs that aren't available in the built-in JavaScript engine.
    Install Node.js to run this code:
      \u{2022} brew install node
      \u{2022} Or download from https://nodejs.org
    """
    private static let maxInlineOutputCharacters = 12_000

    static func execute(
        code: String,
        language: ExecutableLanguage,
        stdin: String = "",
        timeout: TimeInterval = 10
    ) async -> CodeExecutionResult {
        #if os(macOS)
        return await executeMacOS(code: code, language: language, stdin: stdin, timeout: timeout)
        #else
        return await executeiOS(code: code, language: language, stdin: stdin)
        #endif
    }

    // MARK: - macOS — Process

    #if os(macOS)
    private struct ExecutionWorkspace {
        let rootURL: URL
        let scriptURL: URL
        let environment: [String: String]
    }

    /// Resolved Node.js path, computed once per app launch.
    private static let _nodePath: String? = {
        let knownPaths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ]
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Interactive login-shell lookup for non-standard installs (nvm, fnm, volta, etc.)
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lic", "command -v node 2>/dev/null"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}
        return nil
    }()

    private static func executeMacOS(
        code: String,
        language: ExecutableLanguage,
        stdin: String,
        timeout: TimeInterval
    ) async -> CodeExecutionResult {
        // prompt()/readLine() snippets are authored for browser-style execution.
        // Route those to JavaScriptCore even on macOS to avoid Node "prompt is not defined".
        if language == .javascript,
           usesPromptStyleJavaScript(code),
           !usesNodeStyleInteractiveJavaScript(code) {
            return await executeJavaScriptCore(code: code, stdin: stdin)
        }

        // JavaScript: fall back to JavaScriptCore when Node.js is not installed
        if language == .javascript && _nodePath == nil {
            if usesNodeStyleInteractiveJavaScript(code) {
                return CodeExecutionResult(
                    stdout: "", stderr: jsCoreFallbackNodeAPIMessage,
                    exitCode: -1, timedOut: false
                )
            }
            let result = await executeJavaScriptCore(code: code, stdin: stdin)
            if result.exitCode != 0 && !result.stderr.isEmpty {
                return CodeExecutionResult(
                    stdout: result.stdout,
                    stderr: result.stderr
                        + "\n\nNote: Ran with built-in JavaScriptCore (Node.js not found)."
                        + "\nFor Node.js APIs, install via: brew install node",
                    exitCode: result.exitCode,
                    timedOut: false
                )
            }
            return result
        }

        let workspace: ExecutionWorkspace
        do {
            workspace = try makeWorkspace(for: language, code: code)
        } catch {
            return CodeExecutionResult(
                stdout: "",
                stderr: "Failed to prepare execution workspace: \(error.localizedDescription)",
                exitCode: -1,
                timedOut: false
            )
        }

        let (executablePath, arguments) = processInfo(for: language, scriptPath: workspace.scriptURL.path)

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.currentDirectoryURL = workspace.rootURL
            process.environment = workspace.environment

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let data = normalizedInputText(stdin).data(using: .utf8) {
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
                teardownWorkspace(workspace)
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

            let stdout = truncateInlineOutput(String(data: stdoutData, encoding: .utf8) ?? "")
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let normalizedStderr = truncateInlineOutput(
                normalizeInputError(stderr: stderr, language: language, stdin: stdin)
            )
            teardownWorkspace(workspace)

            continuation.resume(returning: CodeExecutionResult(
                stdout: stdout,
                stderr: normalizedStderr,
                exitCode: process.terminationStatus,
                timedOut: timedOut
            ))
        }
    }

    private static func processInfo(for language: ExecutableLanguage, scriptPath: String) -> (String, [String]) {
        switch language {
        case .python:
            return ("/usr/bin/python3", ["-u", scriptPath])
        case .javascript:
            return (_nodePath ?? "/usr/local/bin/node", [scriptPath])
        case .shell:
            return ("/bin/bash", [scriptPath])
        }
    }

    private static func makeWorkspace(for language: ExecutableLanguage, code: String) throws -> ExecutionWorkspace {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("seer-inline-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let tmp = root.appendingPathComponent("tmp", isDirectory: true)
        let pipCache = root.appendingPathComponent("pip-cache", isDirectory: true)
        let npmCache = root.appendingPathComponent("npm-cache", isDirectory: true)
        let script = root.appendingPathComponent("snippet.\(scriptExtension(for: language))")

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        try fm.createDirectory(at: pipCache, withIntermediateDirectories: true)
        try fm.createDirectory(at: npmCache, withIntermediateDirectories: true)
        try code.write(to: script, atomically: true, encoding: .utf8)

        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        env["TMPDIR"] = tmp.path
        env["PIP_CACHE_DIR"] = pipCache.path
        env["npm_config_cache"] = npmCache.path

        return ExecutionWorkspace(rootURL: root, scriptURL: script, environment: env)
    }

    private static func teardownWorkspace(_ workspace: ExecutionWorkspace) {
        try? FileManager.default.removeItem(at: workspace.rootURL)
    }
    #endif

    private static func normalizeInputError(stderr: String, language: ExecutableLanguage, stdin: String) -> String {
        let lower = stderr.lowercased()
        let isInputExhausted: Bool = {
            switch language {
            case .python:
                return lower.contains("eoferror: eof when reading a line")
            case .javascript:
                return lower.contains("end-of-file") && lower.contains("stdin")
            case .shell:
                return lower.contains("read error")
                    || (lower.contains("read") && lower.contains("end of file"))
            }
        }()

        guard isInputExhausted else { return stderr }

        let hasInput = !stdin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasInput ? inputExhaustedPartialMessage : inputExhaustedMessage
    }

    // MARK: - JavaScriptCore (shared across platforms)

    #if canImport(JavaScriptCore)
    private static func executeJavaScriptCore(code: String, stdin: String) async -> CodeExecutionResult {
        return await withCheckedContinuation { continuation in
            // JSCore can't be pre-empted, but we can stop waiting on a runaway
            // script (e.g. `while(true){}`) so the Run spinner doesn't hang
            // forever. The orphaned evaluation finishes on its own thread.
            let resumeLock = NSLock()
            var resumed = false
            func finish(_ result: CodeExecutionResult) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                finish(CodeExecutionResult(
                    stdout: "",
                    stderr: "Execution timed out after 10s (possible infinite loop).",
                    exitCode: -1,
                    timedOut: true
                ))
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let ctx = JSContext()!
                var consoleOutput: [String] = []
                let inputJSON = javascriptInputJSON(from: stdin)

                // Capture console.log
                let logFn: @convention(block) () -> Void = {
                    let args = JSContext.currentArguments()?.compactMap { ($0 as? JSValue)?.toString() } ?? []
                    consoleOutput.append(args.joined(separator: " "))
                }
                ctx.setObject(logFn, forKeyedSubscript: "$$log" as NSString)

                // Console (with object formatting + console.table), networking stubs,
                // and the common web globals JavaScriptCore lacks. Without this,
                // console.log(obj) printed "[object Object]", console.table threw, and
                // fetch/btoa/crypto were "Can't find variable" errors.
                ctx.evaluateScript(#"""
                (function (g) {
                  function __seerFmt(v, depth) {
                    depth = depth || 0;
                    if (v === null) return "null";
                    var t = typeof v;
                    if (t === "undefined") return "undefined";
                    if (t === "string") return depth === 0 ? v : JSON.stringify(v);
                    if (t === "number" || t === "boolean" || t === "bigint") return String(v);
                    if (t === "symbol") return v.toString();
                    if (t === "function") return "[Function" + (v.name ? ": " + v.name : "") + "]";
                    if (v instanceof Error) return (v.stack ? String(v.stack) : (v.name + ": " + v.message));
                    try {
                      var out = JSON.stringify(v, function (k, val) {
                        if (typeof val === "bigint") return String(val);
                        if (typeof val === "function") return "[Function]";
                        if (typeof val === "undefined") return "[undefined]";
                        return val;
                      }, 2);
                      return out === undefined ? String(v) : out;
                    } catch (e) { return String(v); }
                  }
                  g.__seerFmt = __seerFmt;
                  function emit() {
                    var parts = [];
                    for (var i = 0; i < arguments.length; i++) parts.push(__seerFmt(arguments[i], 0));
                    g.$$log(parts.join(" "));
                  }
                  function table(data) {
                    try {
                      if (!data || typeof data !== "object") { emit(data); return; }
                      var isArr = Array.isArray(data);
                      var indices = isArr ? data.map(function (_, i) { return String(i); }) : Object.keys(data);
                      var rows = indices.map(function (k) { return data[k]; });
                      var cols = [];
                      rows.forEach(function (r) {
                        if (r && typeof r === "object") Object.keys(r).forEach(function (k) { if (cols.indexOf(k) === -1) cols.push(k); });
                      });
                      if (cols.length === 0) { emit(data); return; }
                      var header = ["(index)"].concat(cols);
                      var lines = [header];
                      rows.forEach(function (r, i) {
                        var line = [indices[i]];
                        cols.forEach(function (c) { line.push(r && typeof r === "object" && c in r ? String(r[c]) : ""); });
                        lines.push(line);
                      });
                      var widths = header.map(function (_, c) {
                        return Math.max.apply(null, lines.map(function (l) { return String(l[c]).length; }));
                      });
                      var sep = "+" + widths.map(function (w) { return "-".repeat(w + 2); }).join("+") + "+";
                      var out = [sep];
                      lines.forEach(function (l, li) {
                        out.push("| " + l.map(function (cell, c) { var s = String(cell); return s + " ".repeat(widths[c] - s.length); }).join(" | ") + " |");
                        if (li === 0) out.push(sep);
                      });
                      out.push(sep);
                      g.$$log(out.join("\n"));
                    } catch (e) { emit(data); }
                  }
                  g.console = {
                    log: emit, info: emit, warn: emit, error: emit, debug: emit,
                    trace: emit, dir: emit, group: emit, groupCollapsed: emit,
                    groupEnd: function () {}, table: table,
                    assert: function (cond) {
                      if (!cond) {
                        var rest = Array.prototype.slice.call(arguments, 1);
                        g.$$log("Assertion failed" + (rest.length ? ": " + rest.map(function (x) { return __seerFmt(x, 0); }).join(" ") : ""));
                      }
                    },
                    count: function () {}, time: function () {}, timeEnd: function () {}, clear: function () {}
                  };
                  var NET_MSG = "Network requests aren't available in SEER's offline code sandbox. Use inline data instead of fetch()/XMLHttpRequest.";
                  if (!g.fetch) g.fetch = function () { return Promise.reject(new Error(NET_MSG)); };
                  if (!g.XMLHttpRequest) g.XMLHttpRequest = function () {
                    return { open: function () {}, setRequestHeader: function () {}, send: function () { throw new Error(NET_MSG); }, addEventListener: function () {} };
                  };
                  if (!g.btoa) g.btoa = function (input) {
                    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
                    var str = String(input), out = "";
                    for (var i = 0; i < str.length;) {
                      var c1 = str.charCodeAt(i++), c2 = str.charCodeAt(i++), c3 = str.charCodeAt(i++);
                      var e1 = c1 >> 2, e2 = ((c1 & 3) << 4) | (c2 >> 4);
                      var e3 = isNaN(c2) ? 64 : (((c2 & 15) << 2) | (c3 >> 6)), e4 = isNaN(c3) ? 64 : (c3 & 63);
                      out += chars.charAt(e1) + chars.charAt(e2) + chars.charAt(e3) + chars.charAt(e4);
                    }
                    return out;
                  };
                  if (!g.atob) g.atob = function (input) {
                    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
                    var str = String(input).replace(/=+$/, ""), out = "";
                    for (var bc = 0, bs = 0, buffer, i = 0; (buffer = str.charAt(i++));) {
                      var idx = chars.indexOf(buffer);
                      if (idx === -1) continue;
                      bs = bc % 4 ? bs * 64 + idx : idx;
                      if (bc++ % 4) out += String.fromCharCode(255 & (bs >> ((-2 * bc) & 6)));
                    }
                    return out;
                  };
                  if (!g.crypto) g.crypto = {};
                  if (!g.crypto.randomUUID) g.crypto.randomUUID = function () {
                    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
                      var r = Math.random() * 16 | 0, v = c === "x" ? r : (r & 0x3 | 0x8);
                      return v.toString(16);
                    });
                  };
                  if (!g.crypto.getRandomValues) g.crypto.getRandomValues = function (arr) {
                    for (var i = 0; i < arr.length; i++) arr[i] = Math.floor(Math.random() * 256);
                    return arr;
                  };
                  if (!g.structuredClone) g.structuredClone = function (v) { return JSON.parse(JSON.stringify(v)); };
                  if (!g.performance) g.performance = { now: function () { return Date.now(); } };
                })(typeof globalThis !== "undefined" ? globalThis : this);
                """#)

                // Timer shim: JavaScriptCore has no event loop, so setTimeout/
                // setInterval don't exist — timer-based "stream over time / tick-
                // by-tick" code would silently produce nothing. Back them with a
                // virtual clock that we drain synchronously after the script runs,
                // so such code actually executes and prints. Bounded by virtual
                // time + callback count so a bare setInterval can't spin forever.
                ctx.evaluateScript(#"""
                (function (g) {
                  var T = [], now = 0, seq = 1, MAX_CB = 5000, MAX_MS = 30000;
                  g.setTimeout = function (cb, delay) {
                    var a = Array.prototype.slice.call(arguments, 2);
                    var id = seq++; T.push({ id: id, cb: cb, t: now + (delay | 0), iv: null, a: a }); return id;
                  };
                  g.setInterval = function (cb, delay) {
                    var a = Array.prototype.slice.call(arguments, 2);
                    var id = seq++, d = Math.max(1, delay | 0); T.push({ id: id, cb: cb, t: now + d, iv: d, a: a }); return id;
                  };
                  g.clearTimeout = g.clearInterval = function (id) {
                    for (var i = 0; i < T.length; i++) if (T[i].id === id) { T.splice(i, 1); return; }
                  };
                  g.queueMicrotask = function (cb) { g.setTimeout(cb, 0); };
                  g.__seerDrainTimers = function () {
                    var n = 0, t0 = Date.now(), BUDGET = 6000;   // stop well before the 10s watchdog
                    while (T.length) {
                      if (Date.now() - t0 > BUDGET) { if (g.console) console.warn('[timers stopped after ' + BUDGET + 'ms of work — reduce ticks or per-tick work]'); break; }
                      var k = 0;
                      for (var i = 1; i < T.length; i++) if (T[i].t < T[k].t) k = i;
                      var x = T[k];
                      if (x.t > MAX_MS) break;
                      now = x.t;
                      if (x.iv != null) x.t = now + x.iv; else T.splice(k, 1);
                      try { x.cb.apply(g, x.a || []); } catch (e) { if (g.console) console.error(String(e)); }
                      if (++n >= MAX_CB) { if (g.console) console.warn('[timers stopped after ' + MAX_CB + ' callbacks]'); break; }
                    }
                  };
                })(typeof globalThis !== "undefined" ? globalThis : this);
                """#)
                let inputPrelude = """
                var __seerInputQueue = \(inputJSON);
                var __seerGlobal = (typeof globalThis !== "undefined") ? globalThis : this;
                function __seerTakeInput() {
                  if (!Array.isArray(__seerInputQueue) || __seerInputQueue.length === 0) {
                    throw new Error("Program requested more input than provided. Add one value per line in the Input panel and run again.");
                  }
                  return String(__seerInputQueue.shift());
                }
                __seerGlobal.prompt = __seerGlobal.prompt || function(_message) { return __seerTakeInput(); };
                __seerGlobal.readLine = __seerGlobal.readLine || function() { return __seerTakeInput(); };
                __seerGlobal.process = __seerGlobal.process || {};
                process.stdin = process.stdin || {};
                process.stdin.read = function() { return __seerTakeInput(); };
                process.stdin.setEncoding = function() {};
                process.stdin.resume = function() {};
                process.stdin.pause = function() {};
                process.stdin.on = function(event, handler) {
                  if (typeof handler !== "function") { return process.stdin; }
                  if (event === "data") {
                    while (Array.isArray(__seerInputQueue) && __seerInputQueue.length > 0) {
                      var next = __seerTakeInput();
                      if (next === null) { break; }
                      handler(next);
                    }
                  }
                  if (event === "end") { handler(); }
                  return process.stdin;
                };
                """
                _ = ctx.evaluateScript(inputPrelude)

                // Capture exceptions
                var errorOutput = ""
                ctx.exceptionHandler = { _, value in
                    errorOutput = value?.toString() ?? "Unknown error"
                }

                let result = ctx.evaluateScript(code)

                // A top-level `async` IIFE (or any expression) evaluates to a Promise.
                // Don't print "[object Promise]"; instead settle it best-effort and log
                // its resolution/rejection. JavaScriptCore drains promise microtasks at
                // script boundaries, so by the next evaluateScript the handler has run.
                var resultIsThenable = false
                if let val = result, val.isObject,
                   let thenFn = val.objectForKeyedSubscript("then"), thenFn.isObject {
                    resultIsThenable = true
                    ctx.setObject(val, forKeyedSubscript: "__seerResultPromise" as NSString)
                    _ = ctx.evaluateScript(#"""
                    (function () {
                      var p = __seerResultPromise;
                      if (p && typeof p.then === "function") {
                        p.then(function (v) { if (v !== undefined && v !== null) console.log(v); },
                               function (e) { console.error(e && e.stack ? String(e.stack) : String(e)); });
                      }
                    })();
                    """#)
                }

                // Drain any pending setTimeout/setInterval callbacks (virtual clock) and
                // give queued promise reactions a chance to run before we collect output.
                _ = ctx.evaluateScript("typeof __seerDrainTimers === 'function' && __seerDrainTimers();")

                // If the last expression produced a (non-Promise) value, append it.
                if errorOutput.isEmpty, !resultIsThenable, let val = result, !val.isUndefined, !val.isNull {
                    let str = val.toString() ?? ""
                    if !str.isEmpty && !consoleOutput.contains(str) {
                        consoleOutput.append(str)
                    }
                }

                let stdout = truncateInlineOutput(consoleOutput.joined(separator: "\n"))
                let stderr = truncateInlineOutput(errorOutput)

                finish(CodeExecutionResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: stderr.isEmpty ? 0 : 1,
                    timedOut: false
                ))
            }
        }
    }
    #endif

    // MARK: - iOS — JavaScriptCore

    #if os(iOS)
    private static func executeiOS(code: String, language: ExecutableLanguage, stdin: String) async -> CodeExecutionResult {
        guard language == .javascript else {
            return CodeExecutionResult(
                stdout: "",
                stderr: "\(language.displayName) is not available on iOS.",
                exitCode: -1,
                timedOut: false
            )
        }

        if usesNodeStyleInteractiveJavaScript(code) {
            return CodeExecutionResult(
                stdout: "",
                stderr: iOSJavaScriptNodeInputUnsupportedMessage,
                exitCode: 2,
                timedOut: false
            )
        }

        return await executeJavaScriptCore(code: code, stdin: stdin)
    }
    #endif

    private static func scriptExtension(for language: ExecutableLanguage) -> String {
        switch language {
        case .python:
            return "py"
        case .javascript:
            return "mjs"
        case .shell:
            return "sh"
        }
    }

    private static func normalizedInputText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let clean = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return clean.hasSuffix("\n") ? clean : "\(clean)\n"
    }

    static func usesNodeStyleInteractiveJavaScript(_ code: String) -> Bool {
        let lower = code.lowercased()
        return lower.contains("readline.createinterface(")
            || lower.contains("require('readline'")
            || lower.contains("require(\"readline\"")
            || lower.contains("node:readline")
    }

    static func usesPromptStyleJavaScript(_ code: String) -> Bool {
        let lower = code.lowercased()
        return lower.contains("prompt(") || lower.contains("readline(")
    }

    private static func javascriptInputJSON(from text: String) -> String {
        let lines = inputLines(from: text)
        guard let data = try? JSONSerialization.data(withJSONObject: lines),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func inputLines(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func truncateInlineOutput(_ text: String) -> String {
        guard text.count > maxInlineOutputCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxInlineOutputCharacters)
        return "\(text[..<end])\n\n[output truncated at \(maxInlineOutputCharacters) characters]"
    }
}
