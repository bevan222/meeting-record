import AVFoundation
import Foundation

@MainActor
final class MacAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case checkingPermission
        case permissionDenied
        case recording(startedAt: Date)
        case stopping
        case saved(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?

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

    func stopRecording() {
        guard let recorder, isRecording else { return }

        updateElapsed()
        state = .stopping
        recorder.stop()
        stopTimer()
        elapsedSeconds = max(elapsedSeconds, recorder.currentTime)
        state = .saved(recorder.url)
        self.recorder = nil
        startedAt = nil
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            stopTimer()
            self.recorder = nil
            startedAt = nil
            state = .failed(error?.localizedDescription ?? "Recording failed.")
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
}
