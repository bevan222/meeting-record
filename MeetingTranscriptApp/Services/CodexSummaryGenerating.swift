import Foundation
import MeetingTranscriptCore

protocol CodexSummaryGenerating: Sendable {
    func generateSummary(for document: TranscriptDocument, meetingDirectory: URL) async throws -> String
}

struct CodexCommandResult: Sendable {
    let terminationStatus: Int32
    let standardError: String
}

protocol CodexCommandRunning: Sendable {
    func runCodex(executableURL: URL, arguments: [String], workingDirectory: URL, outputFileURL: URL, prompt: String) async throws -> CodexCommandResult
}

enum CodexSummaryError: LocalizedError, Equatable {
    case executableMissing(String)
    case commandFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            return "Codex CLI was not found at \(path)."
        case .commandFailed(let standardError):
            let trimmedError = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedError.isEmpty {
                return "Codex CLI failed."
            }
            return "Codex CLI failed: \(trimmedError)"
        case .emptyOutput:
            return "Codex CLI returned an empty summary."
        }
    }
}

struct CodexCLISummaryGenerator: CodexSummaryGenerating {
    private let executableURL: URL
    private let commandRunner: any CodexCommandRunning

    init(
        executableURL: URL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
        commandRunner: any CodexCommandRunning = ProcessCodexCommandRunner()
    ) {
        self.executableURL = executableURL
        self.commandRunner = commandRunner
    }

    func generateSummary(for document: TranscriptDocument, meetingDirectory: URL) async throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw CodexSummaryError.executableMissing(executableURL.path)
        }

        let outputFileURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        defer {
            try? fileManager.removeItem(at: outputFileURL)
        }

        let arguments = ["exec", "--skip-git-repo-check", "--output-last-message", outputFileURL.path, "-"]
        let result = try await commandRunner.runCodex(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: meetingDirectory,
            outputFileURL: outputFileURL,
            prompt: try Self.makePrompt(for: document)
        )

        guard result.terminationStatus == 0 else {
            throw CodexSummaryError.commandFailed(result.standardError)
        }

        let summary = try String(contentsOf: outputFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw CodexSummaryError.emptyOutput
        }
        return summary
    }

    static func makePrompt(for document: TranscriptDocument) throws -> String {
        let data = try JSONEncoder.transcriptEncoder.encode(document)
        let json = String(decoding: data, as: UTF8.self)
        return """
        請根據以下會議逐字稿整理：
        1. 重點摘要
        2. 決議事項
        3. 待辦事項
        4. 負責人
        5. 期限
        6. 未解問題

        請使用繁體中文，輸出 Markdown。

        ```json
        \(json)
        ```
        """
    }
}

struct ProcessCodexCommandRunner: CodexCommandRunning {
    func runCodex(executableURL: URL, arguments: [String], workingDirectory: URL, outputFileURL: URL, prompt: String) async throws -> CodexCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let standardInput = Pipe()
        let standardErrorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("stderr")
        FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
        let standardError = try FileHandle(forWritingTo: standardErrorURL)
        defer {
            try? standardError.close()
            try? FileManager.default.removeItem(at: standardErrorURL)
        }

        process.standardInput = standardInput
        process.standardError = standardError

        let processState = ProcessTerminationState()
        process.terminationHandler = { process in
            processState.finish(terminationStatus: process.terminationStatus)
        }

        let terminationStatus = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.run()
            processState.setProcess(process)
            do {
                try standardInput.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
                try standardInput.fileHandleForWriting.close()
            } catch {
                processState.terminate()
                _ = await processState.waitForTermination()
                throw error
            }

            let terminationStatus = await processState.waitForTermination()
            if processState.wasCancelled {
                throw CancellationError()
            }
            return terminationStatus
        } onCancel: {
            processState.cancel()
        }

        try standardError.close()
        let errorData = try Data(contentsOf: standardErrorURL)
        let errorText = String(decoding: errorData, as: UTF8.self)
        return CodexCommandResult(terminationStatus: terminationStatus, standardError: errorText)
    }
}

private final class ProcessTerminationState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ProcessTerminationState")
    private var process: Process?
    private var continuation: CheckedContinuation<Int32, Never>?
    private var terminationStatus: Int32?
    private var isCancelled = false

    var wasCancelled: Bool {
        queue.sync { isCancelled }
    }

    func setProcess(_ process: Process) {
        let shouldTerminate = queue.sync {
            self.process = process
            return isCancelled
        }
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func waitForTermination() async -> Int32 {
        await withCheckedContinuation { continuation in
            let status: Int32? = queue.sync {
                if let terminationStatus {
                    return terminationStatus
                }
                self.continuation = continuation
                return nil
            }
            if let status {
                continuation.resume(returning: status)
            }
        }
    }

    func finish(terminationStatus: Int32) {
        let continuation = queue.sync {
            guard self.terminationStatus == nil else {
                return nil as CheckedContinuation<Int32, Never>?
            }
            self.terminationStatus = terminationStatus
            let continuation = self.continuation
            self.continuation = nil
            self.process = nil
            return continuation
        }
        continuation?.resume(returning: terminationStatus)
    }

    func cancel() {
        let process = queue.sync {
            isCancelled = true
            return self.process
        }
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func terminate() {
        let process = queue.sync { self.process }
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
