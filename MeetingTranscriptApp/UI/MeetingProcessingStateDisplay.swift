import MeetingTranscriptCore

extension MeetingProcessingState {
    var displayText: String {
        switch self {
        case .created:
            "已建立"
        case .recording:
            "錄音中"
        case .recorded:
            "音檔已保存"
        case .transcribing:
            "轉文字中..."
        case .transcribed:
            "逐字稿完成"
        case .diarizing:
            "講者標註中..."
        case .speakerAttributed:
            "完成"
        case .exported:
            "已匯出"
        case .failed:
            "失敗"
        }
    }

    var isProcessing: Bool {
        switch self {
        case .recording, .transcribing, .diarizing:
            true
        case .created, .recorded, .transcribed, .speakerAttributed, .exported, .failed:
            false
        }
    }

    var isFailure: Bool {
        self == .failed
    }
}
