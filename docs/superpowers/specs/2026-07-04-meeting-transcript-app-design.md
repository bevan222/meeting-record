# 本機會議逐字稿 App 第一階段設計

## 目標

建立一個 macOS 本機會議逐字稿 App 的第一階段 MVP。第一階段要驗證端到端產品流程，而不是先挑戰真實模型整合。

第一階段採用「端到端骨架優先」：

- 可啟動 SwiftUI macOS App。
- 可開始與停止麥克風錄音。
- 真正保存每場會議的 `audio.m4a`。
- 建立會議資料夾與本機檔案儲存。
- 保存 canonical `transcript.json`。
- 匯出 deterministic `transcript.md`。
- 顯示會議清單與逐字稿工作區。
- 支援編輯 segment text。
- 支援 speaker 改名，例如 `Speaker 1` 顯示為 `Gavin`。
- 提供 mock transcription 與 mock diarization，讓資料流和 UI 先完整打通。

第一階段不接真實 WhisperKit / SpeakerKit 模型。第二階段再用 Argmax OSS Swift SDK 實作相同 protocol 的 adapter。

## 明確不做

- 不使用 OpenAI 或其他雲端模型 API。
- 不做 Windows 或 iOS。
- 不做系統音訊錄製，只錄預設麥克風。
- 不做真實 WhisperKit 即時轉錄。
- 不做真實 SpeakerKit diarization。
- 不自動辨識真實姓名。
- 不產生 `summary.md`。摘要是 Codex 或後續版本的輸出，不是第一階段逐字稿 App 的核心資料。
- 不使用 Core Data。第一階段採檔案與 JSON，方便檢查、匯出、測試與後續遷移。

## 技術假設

- App 使用 SwiftUI macOS。
- 第一階段最低開發環境以可建立現代 macOS SwiftUI App 為準。
- 第二階段 Argmax SDK 接入時，官方 package URL 為 `https://github.com/argmaxinc/argmax-oss-swift.git`。
- Argmax OSS Swift SDK README 目前列出 products 包含 `WhisperKit` 與 `SpeakerKit`，且 package prereq 包含 macOS 14+ / Xcode 16+；這會在第二階段接 SDK 時再正式固定 target 與 dependency。
- App 的 canonical model 使用自有 domain types，不把 WhisperKit / SpeakerKit raw types 存入 JSON、UI 或核心 use case。

## 第一階段驗收標準

- App 可啟動並顯示空狀態。
- 使用者可按 Record，App 會檢查麥克風權限。
- 使用者允許權限後，App 建立 meeting folder 並開始錄音。
- 使用者按 Stop 後，folder 內有可播放的 `audio.m4a`。
- Stop 後 mock transcription 會產生 segments 並保存 `transcript.json`。
- 使用者可執行 mock speaker 標註，segments 會得到 `speakerId`。
- 使用者可把 `Speaker 1` 改名為 `Gavin`，segment 的 `speakerId` 不改。
- 使用者可匯出或重建 `transcript.md`。
- 關閉重開 App 後，會議清單與已保存 transcript 可讀回。

## 專案分層

```text
MeetingTranscriptApp/
  App/
    MeetingTranscriptApp.swift
  UI/
    MeetingListView.swift
    MeetingDetailView.swift
    RecordingToolbarView.swift
    TranscriptSegmentRow.swift
    SpeakerEditorView.swift
  ViewModels/
    MeetingListViewModel.swift
    MeetingDetailViewModel.swift
    RecorderViewModel.swift
  Services/
    MacAudioRecorder.swift
    AppContainer.swift
  Storage/
    FileMeetingStore.swift
    AppDirectories.swift

Sources/MeetingTranscriptCore/
  Models/
    Meeting.swift
    TranscriptDocument.swift
    Speaker.swift
    TranscriptSegment.swift
    SpeakerTurn.swift
  Ports/
    RecordingService.swift
    MeetingRepository.swift
    TranscriptionEngine.swift
    DiarizationEngine.swift
  UseCases/
    CreateMeetingUseCase.swift
    FinishRecordingUseCase.swift
    RunTranscriptionUseCase.swift
    RunDiarizationUseCase.swift
    RenameSpeakerUseCase.swift
    ExportTranscriptUseCase.swift
  Adapters/
    MockTranscriptionEngine.swift
    MockDiarizationEngine.swift
    TranscriptAssembler.swift
    JSONTranscriptExporter.swift
    MarkdownTranscriptExporter.swift

Tests/MeetingTranscriptCoreTests/
```

`MeetingTranscriptCore` 不 import SwiftUI、AVFoundation、WhisperKit 或 SpeakerKit。它只包含可單元測試的資料模型、狀態轉換、speaker 對齊、JSON 與 Markdown 匯出。

`MeetingTranscriptApp` 負責 macOS App wiring、SwiftUI、麥克風權限、AVFoundation 錄音、Application Support path。

## 主要資料模型

```text
Meeting
- id: String
- title: String
- recordedAt: Date
- durationSeconds: TimeInterval
- language: String
- sourceAudio: String
- status: MeetingProcessingState

Speaker
- id: String
- label: String
- name: String?

TranscriptSegment
- id: String
- start: TimeInterval
- end: TimeInterval
- speakerId: String?
- text: String
- confidence: Double?

SpeakerTurn
- speakerId: String
- start: TimeInterval
- end: TimeInterval
- confidence: Double?

TranscriptDocument
- meeting: Meeting
- speakers: [Speaker]
- segments: [TranscriptSegment]
```

Speaker 顯示名稱規則：

```text
displayName = speaker.name ?? speaker.label
```

speaker 改名只更新 `speakers[].name`，不改 `speakers[].id`，也不改 segment 的 `speakerId`。

## JSON 格式

`transcript.json` 採用以下 canonical 結構：

```json
{
  "meeting": {
    "id": "2026-07-04-1400-tgb-sit",
    "title": "TGB SIT 進度會議",
    "recordedAt": "2026-07-04T14:00:00+08:00",
    "durationSeconds": 3600,
    "language": "zh-TW",
    "sourceAudio": "audio.m4a",
    "status": "speakerAttributed"
  },
  "speakers": [
    { "id": "speaker_1", "label": "Speaker 1", "name": null },
    { "id": "speaker_2", "label": "Speaker 2", "name": null }
  ],
  "segments": [
    {
      "id": "seg_0001",
      "start": 3.2,
      "end": 8.1,
      "speakerId": "speaker_1",
      "text": "今天先確認 SIT 測試範圍。",
      "confidence": null
    }
  ]
}
```

`metadata.json` 是會議清單用的索引資料，保存 title、日期、長度、狀態、檔案相對路徑與是否已有 speaker attribution。`transcript.json` 仍是逐字稿主資料。

## 檔案結構

App data 存在 Application Support：

```text
~/Library/Application Support/MeetingTranscriptApp/Meetings/
└─ 2026-07-04-1400-tgb-sit/
   ├─ metadata.json
   ├─ audio.m4a
   ├─ transcript.json
   └─ transcript.md
```

每場會議先建立 folder，再直接錄到最終的 `audio.m4a`。第一階段避免使用暫存音檔轉移，降低檔案生命週期複雜度。

`transcript.md` 可由 `transcript.json` deterministic rebuild。若 JSON 和 Markdown 不一致，以 JSON 為準。

## 錄音設計

第一階段使用 `AVAudioRecorder`，原因是 MVP 只需要預設麥克風錄製並保存 `audio.m4a`。`AVAudioEngine` 留到第二階段，需要即時 audio chunk、waveform、device routing 或真實 streaming transcription 時再引入。

macOS 需要：

- `NSMicrophoneUsageDescription`
- sandbox audio input entitlement：`com.apple.security.device.audio-input`
- 錄音前檢查或要求 microphone permission

建議音檔設定：

- container：MPEG-4
- codec：AAC-LC
- channel：mono
- sample rate：44.1 kHz 或 48 kHz
- bitrate：64-96 kbps

`audio.m4a` 是 durable source。第二階段如果 WhisperKit 或 SpeakerKit adapter 需要 PCM/WAV/16 kHz，adapter 內部再產生暫存 derivative，不改 canonical source。

## 狀態流

錄音狀態獨立於會議處理狀態。

```text
RecordingState:
idle
-> checkingPermission
-> recording(startedAt, elapsed, level)
-> stopping
-> saved(meetingId, audioURL)

checkingPermission -> permissionDenied
recording/stopping -> failed(error)
```

```text
MeetingProcessingState:
created
-> recording
-> recorded
-> transcribing
-> transcribed
-> diarizing
-> speakerAttributed
-> exported
```

失敗不應破壞已完成的 durable output。例如 mock diarization 失敗時，meeting 可停在 `transcribed`，`audio.m4a` 和 transcription segments 仍可保留。

## Transcription 與 Diarization Adapter 邊界

第一階段定義 app-owned protocols：

```text
TranscriptionEngine:
  transcribe(audioURL, options) async -> [TranscriptSegment]

DiarizationEngine:
  diarize(audioURL, options) async -> [SpeakerTurn]

TranscriptAssembler:
  assign speaker turns to transcript segments by time overlap
```

第一階段實作：

- `MockTranscriptionEngine`
- `MockDiarizationEngine`

第二階段實作：

- `WhisperKitTranscriptionEngine`
- `SpeakerKitDiarizationEngine`

protocol options 只包含 app-level fields，例如 language hint、speaker count hint、local-only requirement 與 progress callback。不要把 SDK-specific option structs 暴露到 Core 或 ViewModel。

模型下載是產品行為，不是細節。第二階段需要新增 `ModelManager` 或等效邊界，明確處理模型是否已安裝、是否允許下載、下載進度、模型版本與刪除。若使用者要求全程本機，App 不應在 processing 時靜默下載模型。

## Speaker 對齊策略

`TranscriptAssembler` 用 speaker turn 與 transcript segment 的時間重疊比例決定 `speakerId`。

第一階段規則：

- 對每個 transcript segment 計算與每個 speaker turn 的 overlap duration。
- 選 overlap 最大的 speaker。
- 若沒有 overlap，保留 `speakerId = nil`，不建立 `speaker_unknown`。
- 生成 speakers 時使用 `speaker_1`, `speaker_2`, `speaker_3`。
- 顯示時使用 `name > label`。

第二階段可再比較 SpeakerKit 內建合併策略與自有 assembler，但 canonical output 仍寫入 app-owned `TranscriptSegment`。

## UI 設計

第一階段採「Library + Transcript Workspace」：

- 左側 sidebar：會議清單、搜尋 title、狀態 badge。
- 右側上方 toolbar：meeting title、Record、Stop、elapsed time、錄音狀態。
- 右側中間：transcript segment list，顯示時間、speaker display name、文字。
- 右側下方或 toolbar：Diarize、Export JSON、Export Markdown、Open Folder。
- Speaker editor：列出 speakers，允許修改 `name`。

空狀態顯示：

- 沒有會議時，右側顯示開始錄音的主要動作。
- 有會議但沒有 transcript 時，顯示音檔與處理狀態。

第一階段的 live transcript 可以用 mock live segments 表示資料流已打通。真實 WhisperKit live streaming 不屬於第一階段驗收。

## 錯誤處理

只處理 MVP 必要錯誤：

- 麥克風權限 denied：顯示 recoverable state，不建立空會議。
- 錄音開始失敗：保留錯誤，不寫半套 transcript。
- 停止錄音失敗：meeting 停在 failed，可重試或刪除。
- JSON 寫入失敗：顯示保存失敗，不宣稱 export 成功。
- mock transcription 失敗：meeting 停在 recorded，audio 保留。
- mock diarization 失敗：meeting 停在 transcribed，transcript 保留。

## 測試策略

單元測試：

- `TranscriptDocument` JSON encode/decode 不遺失 speaker 與 segment。
- Markdown export 時間格式為 `[HH:MM:SS]`。
- speaker rename 後，segment `speakerId` 不變。
- speaker turn 對齊 transcript segment 的 overlap 邏輯正確。
- JSON 為 canonical source，Markdown 可 deterministic rebuild。

Workflow 測試：

- 使用 fake recorder 與 temporary directory 建立 meeting。
- 模擬錄音完成，保存 metadata。
- mock transcription 寫入 transcript JSON。
- mock diarization 合併 speakerId。
- export Markdown。

手動驗收：

- Fresh install 第一次錄音時會要求 microphone permission。
- 拒絕權限時 UI 顯示明確狀態。
- 錄 10 秒後，folder 內有可播放 `audio.m4a`。
- 重新啟動 App 後，會議列表與 transcript 可讀回。
- 改 `Speaker 1` 為 `Gavin` 後，UI 與 Markdown 都顯示 `Gavin`。

## 後續第二階段

第二階段接入 Argmax OSS Swift SDK：

- 加入 Swift package dependency：`https://github.com/argmaxinc/argmax-oss-swift.git`
- 加入 products：`WhisperKit`、`SpeakerKit`
- 實作 `WhisperKitTranscriptionEngine`
- 實作 `SpeakerKitDiarizationEngine`
- 決定模型管理策略：預先安裝、本機下載、或使用者手動指定 model folder
- 將 mock transcription 替換為真實 transcription
- 將 mock diarization 替換為真實 diarization

第二階段不應要求修改 `transcript.json` canonical schema，除非第一階段測試暴露出 schema 無法容納真實 SDK output。
