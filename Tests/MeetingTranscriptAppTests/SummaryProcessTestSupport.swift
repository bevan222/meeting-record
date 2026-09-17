import Darwin
import Foundation
import XCTest
@testable import MeetingTranscriptApp
@testable import MeetingTranscriptCore

// No shell is involved. The alarm also bounds the fixture's lifetime if a test fails.
final class IgnoringTerminationSummaryGenerator: SummaryGenerating, @unchecked Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let retainsStdinInDescendant: Bool
    var readyURL: URL { directory.appendingPathComponent("ready") }
    var executableURL: URL { URL(fileURLWithPath: "/usr/bin/perl") }
    var arguments: [String] {
        ["-e", """
        $SIG{TERM} = 'IGNORE';
        alarm 8;
        if ($ARGV[1]) {
            my $pid = fork();
            die $! unless defined $pid;
            if ($pid == 0) {
                alarm 8;
                sleep 1 while 1;
            }
            open(my $child, '>', $ARGV[0] . '.child') or die $!;
            print $child $pid;
            close($child);
        }
        open(my $ready, '>', $ARGV[0]) or die $!;
        print $ready $$;
        close($ready);
        sleep 1 while 1;
        """, readyURL.path, retainsStdinInDescendant ? "1" : "0"]
    }

    init(retainsStdinInDescendant: Bool = false) throws {
        self.retainsStdinInDescendant = retainsStdinInDescendant
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func waitUntilRunning() async throws -> pid_t {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if let text = try? String(contentsOf: readyURL, encoding: .utf8),
               let pid = pid_t(text), pid > 0 {
                return pid
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SummaryTestTimeout.expired
    }

    func cleanUp() {
        for url in [readyURL, readyURL.appendingPathExtension("child")] {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let pid = pid_t(text), pid > 0 {
                _ = kill(pid, SIGKILL)
            }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func generateSummary(for document: TranscriptDocument, meetingDirectory: URL) async throws -> String {
        let result = try await ProcessSummaryCommandRunner().runSummaryCommand(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: directory,
            prompt: "prompt"
        )
        return result.standardOutput
    }
}

enum SummaryTestTimeout: Error {
    case expired
}

// An unstructured observer avoids task-group scope waiting forever on cancellation.
@discardableResult
func waitForSummaryTask<T: Sendable, Failure: Error>(
    _ task: Task<T, Failure>,
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> Result<T, Failure>? {
    let completed = XCTestExpectation(description: "summary task completed")
    Task {
        _ = await task.result
        completed.fulfill()
    }
    let result = await XCTWaiter.fulfillment(of: [completed], timeout: timeout)
    XCTAssertEqual(result, .completed, "Summary task exceeded bounded timeout", file: file, line: line)
    guard result == .completed else { return nil }
    return await task.result
}
