import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { status == 0 }
}

public struct ShellError: Error, CustomStringConvertible {
    public let command: String
    public let status: Int32
    public let stderr: String
    public var description: String {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(command) exited with status \(status)" + (detail.isEmpty ? "" : ": \(detail)")
    }
}

/// Runs programs with an argument array. Nothing here ever goes through a shell,
/// so no value can be interpreted as shell syntax.
public enum Shell {
    /// `Process` is safe to stop from another thread; this lets a cancellation handler hold on to one.
    private struct Running: @unchecked Sendable {
        let process: Process
    }

    /// Runs a program and captures its output.
    /// - Parameter inherit: when true the child writes straight to this process's terminal
    ///   (used for progress bars) and nothing is captured.
    /// - Parameter cancellation: when cancelled, the program is told to stop and `Cancelled` is thrown.
    @discardableResult
    public static func run(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        cwd: URL? = nil,
        inherit: Bool = false,
        cancellation: Cancellation? = nil
    ) throws -> ShellResult {
        try cancellation?.check()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let cwd { process.currentDirectoryURL = cwd }

        let running = Running(process: process)
        func stopOnCancel() {
            cancellation?.onCancel { if running.process.isRunning { running.process.terminate() } }
        }

        if inherit {
            try process.run()
            stopOnCancel()
            process.waitUntilExit()
            try cancellation?.check()
            return ShellResult(status: process.terminationStatus, stdout: "", stderr: "")
        }

        // stdout through a pipe read to the end; stderr to a temp file, so neither can block the other.
        let outPipe = Pipe()
        let errURL = FileManager.default.temporaryDirectory.appending(path: "tannin-stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let errHandle = try FileHandle(forWritingTo: errURL)
        defer {
            try? errHandle.close()
            try? FileManager.default.removeItem(at: errURL)
        }
        process.standardOutput = outPipe
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice

        try process.run()
        stopOnCancel()
        let outData = try outPipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        try cancellation?.check()
        let errData = (try? Data(contentsOf: errURL)) ?? Data()

        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Like `run`, but a non-zero exit status is an error.
    @discardableResult
    public static func check(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        cwd: URL? = nil,
        inherit: Bool = false,
        cancellation: Cancellation? = nil
    ) throws -> ShellResult {
        let result = try run(executable, arguments, environment: environment, cwd: cwd, inherit: inherit, cancellation: cancellation)
        guard result.ok else {
            throw ShellError(
                command: ([executable] + arguments).joined(separator: " "),
                status: result.status,
                stderr: result.stderr
            )
        }
        return result
    }
}
