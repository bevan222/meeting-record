import AVFoundation
import Foundation

@MainActor
class MacAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case checkingPermission
        case permissionDenied
        case recording(startedAt: Date)
        case stopping
        case saved(URL)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var elapsedSeconds: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?
    private var stopContinuation: CheckedContinuation<URL?, Never>?

    var isRecording: Bool {
        if case .recording = state {
            return true
        }
        return false
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            state = .permissionDenied
            return false
        case .notDetermined:
            state = .checkingPermission
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                state = .permissionDenied
            }
            return granted
        @unknown default:
            state = .permissionDenied
            return false
        }
    }

    func startRecording(to url: URL, requestPermissionIfNeeded: Bool = true) async {
        guard !isRecording else { return }

        if requestPermissionIfNeeded {
            guard await requestPermission() else { return }
        }

        do {
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true

            guard recorder.record() else {
                state = .failed("Recording could not be started.")
                return
            }

            self.recorder = recorder
            startedAt = Date()
            elapsedSeconds = 0
            state = .recording(startedAt: startedAt!)
            startTimer()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording() async -> URL? {
        guard let recorder, isRecording else { return nil }

        updateElapsed()
        state = .stopping
        stopTimer()

        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
            recorder.stop()
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            let url = recorder.url

            if flag, isNonEmptyFile(at: url) {
                completeStop(url: url, errorMessage: nil, recorder: recorder)
            } else {
                completeStop(
                    url: nil,
                    errorMessage: "Recording could not be saved.",
                    recorder: recorder
                )
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            completeStop(
                url: nil,
                errorMessage: error?.localizedDescription ?? "Recording failed.",
                recorder: recorder
            )
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateElapsed() {
        guard let startedAt else { return }
        elapsedSeconds = Date().timeIntervalSince(startedAt)
    }

    private func completeStop(url: URL?, errorMessage: String?, recorder: AVAudioRecorder) {
        guard self.recorder === recorder else { return }

        stopTimer()
        elapsedSeconds = max(elapsedSeconds, recorder.currentTime)
        self.recorder = nil
        startedAt = nil

        if let url {
            state = .saved(url)
        } else {
            state = .failed(errorMessage ?? "Recording failed.")
        }

        stopContinuation?.resume(returning: url)
        stopContinuation = nil
    }

    private func isNonEmptyFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return false
        }

        return fileSize.int64Value > 0
    }
}
