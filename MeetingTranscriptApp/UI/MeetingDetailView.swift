import MeetingTranscriptCore
import SwiftUI

struct MeetingDetailView: View {
    @ObservedObject var viewModel: MeetingDetailViewModel
    let selectedMeetingId: String?

    var body: some View {
        Group {
            if let document = viewModel.document {
                VStack(alignment: .leading, spacing: 0) {
                    header(document)
                    Divider()
                    List(document.segments) { segment in
                        TranscriptSegmentRow(
                            segment: segment,
                            speakerName: speakerName(for: segment, in: document),
                            onTextChanged: { text in
                                viewModel.updateSegmentText(segmentId: segment.id, text: text)
                            }
                        )
                    }
                    Divider()
                    speakerEditor(document)
                    Divider()
                    footer
                }
            } else {
                ContentUnavailableView(
                    "No Meeting Selected",
                    systemImage: "waveform",
                    description: Text("Start a recording or select a saved meeting.")
                )
            }
        }
        .onAppear {
            viewModel.load(meetingId: selectedMeetingId)
        }
    }

    private func header(_ document: TranscriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(document.meeting.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text("\(document.meeting.language) | \(formatDuration(document.meeting.durationSeconds)) | \(document.meeting.status.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func speakerEditor(_ document: TranscriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speakers")
                .font(.headline)

            ForEach(document.speakers) { speaker in
                HStack {
                    Text(speaker.label)
                        .frame(width: 90, alignment: .leading)

                    TextField("Name", text: Binding(
                        get: { speaker.name ?? "" },
                        set: { viewModel.renameSpeaker(speakerId: speaker.id, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button("Export Markdown") {
                viewModel.exportMarkdown()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding()
    }

    private func speakerName(for segment: TranscriptSegment, in document: TranscriptDocument) -> String {
        guard let speakerId = segment.speakerId,
              let speaker = document.speakers.first(where: { $0.id == speakerId })
        else {
            return "Unknown Speaker"
        }

        return speaker.displayName
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
