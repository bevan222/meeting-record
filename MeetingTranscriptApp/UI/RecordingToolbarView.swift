import SwiftUI

struct RecordingToolbarView: View {
    @ObservedObject var recorder: MacAudioRecorder
    let canStartRecording: Bool
    let onRecord: () -> Void
    let onStop: () -> Void

    private var canRecord: Bool {
        guard canStartRecording else { return false }

        switch recorder.state {
        case .idle, .permissionDenied, .saved, .failed:
            return true
        case .checkingPermission, .recording, .stopping:
            return false
        }
    }

    private var canStop: Bool {
        if case .recording = recorder.state {
            return true
        }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onRecord()
            } label: {
                Label("Record", systemImage: "record.circle")
            }
            .disabled(!canRecord)

            Button {
                onStop()
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .disabled(!canStop)

            Text(formatElapsed(recorder.elapsedSeconds))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 76, alignment: .leading)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()
        }
        .padding()
    }

    private var statusText: String? {
        switch recorder.state {
        case .idle, .recording:
            return nil
        case .checkingPermission:
            return "Checking microphone access"
        case .permissionDenied:
            return "Microphone access denied"
        case .stopping:
            return "Stopping"
        case .saved:
            return "Recording saved"
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch recorder.state {
        case .permissionDenied, .failed:
            return .red
        default:
            return .secondary
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(
            format: "%02d:%02d:%02d",
            totalSeconds / 3600,
            (totalSeconds % 3600) / 60,
            totalSeconds % 60
        )
    }
}
