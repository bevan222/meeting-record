import AppKit
import MeetingTranscriptCore
import SwiftUI

struct MeetingDetailView: View {
    @ObservedObject var viewModel: MeetingDetailViewModel
    @ObservedObject var recorder: MacAudioRecorder
    let canStartRecording: Bool
    let onRecord: () -> Void
    let onStop: () -> Void
    let onMeetingMetadataChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordingToolbarView(
                recorder: recorder,
                canStartRecording: canStartRecording,
                onRecord: onRecord,
                onStop: onStop
            )
            Divider()

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func header(_ document: TranscriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MeetingTitleField(title: document.meeting.title) { title in
                let updatedTitle = viewModel.updateMeetingTitle(title)
                if updatedTitle != nil {
                    onMeetingMetadataChanged()
                }
                return updatedTitle
            }
            HStack(spacing: 6) {
                Text("\(document.meeting.language) | \(formatDuration(document.meeting.durationSeconds)) | \(document.meeting.status.displayText)")
                if document.meeting.status.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption)
            .foregroundStyle(document.meeting.status.isFailure ? .red : .secondary)
        }
        .padding()
    }

    private func speakerEditor(_ document: TranscriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speakers")
                .font(.headline)

            ForEach(document.speakers) { speaker in
                SpeakerNameRow(speaker: speaker) { name in
                    viewModel.renameSpeaker(speakerId: speaker.id, name: name)
                }
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button("Export JSON") {
                viewModel.exportJSON()
            }

            Button("Export Markdown") {
                viewModel.exportMarkdown()
            }

            Button("Open Folder") {
                if let url = viewModel.meetingFolderURL() {
                    NSWorkspace.shared.open(url)
                }
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

private struct MeetingTitleField: View {
    let title: String
    let onTitleChanged: (String) -> String?

    @State private var text: String
    @State private var lastCommittedText: String
    @FocusState private var isTextFocused: Bool

    init(title: String, onTitleChanged: @escaping (String) -> String?) {
        self.title = title
        self.onTitleChanged = onTitleChanged
        self._text = State(initialValue: title)
        self._lastCommittedText = State(initialValue: title)
    }

    var body: some View {
        TextField("Meeting title", text: $text)
            .textFieldStyle(.plain)
            .font(.title2)
            .fontWeight(.semibold)
            .focused($isTextFocused)
            .onSubmit {
                commit()
            }
            .onChange(of: isTextFocused) { oldValue, newValue in
                if oldValue && !newValue {
                    commit()
                }
            }
            .onChange(of: title) { _, newValue in
                guard !isTextFocused else { return }

                lastCommittedText = newValue
                text = newValue
            }
    }

    private func commit() {
        guard text != lastCommittedText else { return }

        guard let updatedTitle = onTitleChanged(text) else { return }

        lastCommittedText = updatedTitle
        text = updatedTitle
    }
}

private struct SpeakerNameRow: View {
    let speaker: Speaker
    let onNameChanged: (String) -> Void

    @State private var text: String
    @State private var lastCommittedText: String
    @FocusState private var isTextFocused: Bool

    init(speaker: Speaker, onNameChanged: @escaping (String) -> Void) {
        let name = speaker.name ?? ""

        self.speaker = speaker
        self.onNameChanged = onNameChanged
        self._text = State(initialValue: name)
        self._lastCommittedText = State(initialValue: name)
    }

    var body: some View {
        HStack {
            Text(speaker.label)
                .frame(width: 90, alignment: .leading)

            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFocused)
                .onSubmit {
                    commit()
                }
        }
        .onChange(of: isTextFocused) { oldValue, newValue in
            if oldValue && !newValue {
                commit()
            }
        }
        .onChange(of: speaker.name) { _, newValue in
            let newText = newValue ?? ""

            if !isTextFocused {
                lastCommittedText = newText
                text = newText
            }
        }
    }

    private func commit() {
        guard text != lastCommittedText else { return }

        lastCommittedText = text
        onNameChanged(text)
    }
}
