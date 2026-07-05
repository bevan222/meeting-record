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
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardError = standardError

        try process.run()
        try standardInput.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
        try standardInput.fileHandleForWriting.close()
        process.waitUntilExit()

        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errorData, as: UTF8.self)
        return CodexCommandResult(terminationStatus: process.terminationStatus, standardError: errorText)
    }
}
