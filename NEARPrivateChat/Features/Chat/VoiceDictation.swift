import AVFoundation
import Combine
import Foundation
import Speech

/// On-device dictation for the composer. Streams partial speech-to-text into a
/// callback while recording. Every failure path degrades to a status message
/// rather than a crash, and audio is never persisted.
@MainActor
final class VoiceDictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var statusMessage: String?

    /// Receives the latest transcript (partial or final) on the main actor.
    var onTranscript: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isSupported: Bool { recognizer != nil }

    func toggle() {
        if isRecording {
            stop()
        } else {
            requestAuthorizationAndStart()
        }
    }

    private func requestAuthorizationAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechAuth in
            Task { @MainActor in
                guard let self else { return }
                guard speechAuth == .authorized else {
                    self.statusMessage = "Enable Speech Recognition in Settings to dictate."
                    return
                }
                AVAudioApplication.requestRecordPermission { [weak self] micGranted in
                    Task { @MainActor in
                        guard let self else { return }
                        guard micGranted else {
                            self.statusMessage = "Enable Microphone access in Settings to dictate."
                            return
                        }
                        self.beginRecording()
                    }
                }
            }
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Dictation isn't available right now."
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            statusMessage = "Couldn't start the microphone."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // The tap runs on a real-time audio thread — only append to the
        // request here (thread-safe); never touch @Published state.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            statusMessage = "Couldn't start the microphone."
            teardownAudio()
            return
        }

        isRecording = true
        statusMessage = nil
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.onTranscript?(result.bestTranscription.formattedString)
                    if result.isFinal { self.stop() }
                } else if error != nil {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        teardownAudio()
        isRecording = false
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
