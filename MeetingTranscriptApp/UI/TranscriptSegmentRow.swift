import MeetingTranscriptCore
import SwiftUI

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let speakerName: String
    let onTextChanged: (String) -> Void

    @State private var text: String

    init(segment: TranscriptSegment, speakerName: String, onTextChanged: @escaping (String) -> Void) {
        self.segment = segment
        self.speakerName = speakerName
        self.onTextChanged = onTextChanged
        self._text = State(initialValue: segment.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timestamp(segment.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(speakerName)
                    .font(.caption)
                    .fontWeight(.semibold)

                TextField("Transcript text", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...6)
                    .onChange(of: text) { _, newValue in
                        onTextChanged(newValue)
                    }
            }
        }
        .padding(.vertical, 6)
        .onChange(of: segment.text) { _, newValue in
            if text != newValue {
                text = newValue
            }
        }
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
