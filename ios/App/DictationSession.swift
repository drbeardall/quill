import AVFoundation
import SwiftUI
import UIKit

/// Owns the microphone, Whisper and the keyboard session.
@MainActor
final class DictationSession: ObservableObject {
    static let shared = DictationSession()

    enum ModelState: Equatable { case notLoaded, loading, ready, failed(String) }

    @Published var modelState: ModelState = .notLoaded
    @Published var sessionActive = false
    @Published var sessionEnds: Date?
    @Published var recording = false
    @Published var processing = false
    @Published var lastText = ""
    @Published var lastError = ""
    @Published var cameFromKeyboard = false

    private let transcriber = Transcriber()
    private let engine = AVAudioEngine()
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let sampleLock = NSLock()
    private nonisolated(unsafe) var samples: [Float] = []
    private nonisolated(unsafe) var capturing = false
    private var engineRunning = false
    private var heartbeat: Timer?
    private var localJob = false  // dictation started inside the app (not from the keyboard)

    private init() {
        Bridge.observe(Bridge.startNote) { [weak self] in self?.keyboardStart() }
        Bridge.observe(Bridge.stopNote) { [weak self] in self?.stop() }
        Bridge.observe(Bridge.cancelNote) { [weak self] in self?.cancel() }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                if type == .ended, self?.sessionActive == true { try? self?.startEngine() }
            }
        }
    }

    // MARK: Model

    func loadModel() {
        guard modelState != .loading else { return }
        modelState = .loading
        let model = QuillSettings.load().whisperModel
        Task {
            do {
                try await transcriber.load(model: model)
                modelState = .ready
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Keyboard session

    /// Opened from the keyboard (quill://dictate): keep listening in the background for a while.
    func handleURL(_ url: URL) {
        guard url.scheme == "quill" else { return }
        cameFromKeyboard = true
        Task {
            await startSession()
            if Bridge.job?.state == .requested { keyboardStart() }
        }
    }

    func startSession() async {
        guard await requestMic() else {
            lastError = "Quill needs microphone access. Turn it on in Settings › Quill."
            return
        }
        do {
            try startEngine()
        } catch {
            lastError = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }
        sessionActive = true
        extendSession()
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func endSession() {
        heartbeat?.invalidate()
        heartbeat = nil
        if recording { cancel() }
        stopEngine()
        sessionActive = false
        sessionEnds = nil
        cameFromKeyboard = false
        Bridge.endSession()
    }

    private func extendSession() {
        let minutes = max(1, QuillSettings.load().sessionMinutes)
        sessionEnds = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func tick() {
        guard sessionActive, let ends = sessionEnds else { return }
        if Date() > ends, !recording, !processing {
            endSession()
            return
        }
        Bridge.beat(sessionEnds: ends)
    }

    private func keyboardStart() {
        guard var job = Bridge.job, job.state == .requested else { return }
        if !engineRunning {
            Task { await startSession(); keyboardStart() }
            return
        }
        localJob = false
        beginCapture()
        job.state = .listening
        Bridge.job = job
        Bridge.post(Bridge.changedNote)
        extendSession()
    }

    // MARK: In-app dictation

    func toggleInApp() {
        if recording { stop(); return }
        Task {
            if !engineRunning {
                guard await requestMic() else {
                    lastError = "Quill needs microphone access. Turn it on in Settings › Quill."
                    return
                }
                do { try startEngine() } catch { lastError = error.localizedDescription; return }
            }
            localJob = true
            beginCapture()
        }
    }

    // MARK: Recording

    private func beginCapture() {
        sampleLock.lock(); samples.removeAll(keepingCapacity: true); capturing = true; sampleLock.unlock()
        recording = true
        lastError = ""
        haptic(.medium)
    }

    func stop() {
        guard recording else { return }
        sampleLock.lock(); capturing = false; let audio = samples; samples.removeAll(); sampleLock.unlock()
        recording = false
        processing = true
        haptic(.light)
        let isLocal = localJob
        let job = isLocal ? nil : Bridge.job
        if !isLocal { Bridge.update { $0.state = .processing } }
        if isLocal && !sessionActive { stopEngine() }

        Task {
            let settings = QuillSettings.load()
            do {
                let text = try await process(audio, job: job, settings: settings)
                if isLocal {
                    lastText = text
                } else {
                    Bridge.update { $0.state = .done; $0.text = text }
                }
            } catch {
                lastError = error.localizedDescription
                if !isLocal { Bridge.update { $0.state = .failed; $0.error = error.localizedDescription } }
            }
            processing = false
            extendSession()
        }
    }

    func cancel() {
        sampleLock.lock(); capturing = false; samples.removeAll(); sampleLock.unlock()
        recording = false
        if !localJob { Bridge.update { $0.state = .cancelled } }
        if localJob && !sessionActive { stopEngine() }
    }

    private func process(_ audio: [Float], job: Job?, settings: QuillSettings) async throws -> String {
        guard Self.isSpeech(audio) else { return "" }
        if modelState != .ready {
            if modelState != .loading { loadModel() }
            while modelState == .loading { try await Task.sleep(nanoseconds: 200_000_000) }
            if case .failed(let msg) = modelState { throw ClaudeClient.APIError(message: "Speech model failed to load: \(msg)") }
        }
        let raw = try await transcriber.transcribe(audio, prompt: TextTools.whisperPrompt(settings))
        let style = job?.style ?? settings.style
        if job?.mode == .command {
            return try await Cleanup.command(raw, selection: job?.selection ?? "", style: style, settings: settings)
        }
        return await Cleanup.dictate(raw, style: style, settings: settings)
    }

    nonisolated static func isSpeech(_ a: [Float]) -> Bool {
        guard a.count >= 16_000 * 3 / 10 else { return false }
        let rms = sqrt(a.reduce(0) { $0 + $1 * $1 } / Float(a.count))
        return rms >= 0.004
    }

    // MARK: Audio engine

    private func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    private func startEngine() throws {
        guard !engineRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: format, to: targetFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: makeTapBlock())
        engine.prepare()
        try engine.start()
        engineRunning = true
    }

    private func stopEngine() {
        guard engineRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        engineRunning = false
    }

    /// Built outside the main actor: the tap runs on the audio thread.
    private nonisolated func makeTapBlock() -> AVAudioNodeTapBlock {
        { [weak self] buffer, _ in self?.append(buffer) }
    }

    private nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        sampleLock.lock()
        let on = capturing
        sampleLock.unlock()
        guard on else { return }
        let converted = convert(buffer) ?? []  // runs on the audio thread
        sampleLock.lock(); if capturing { samples.append(contentsOf: converted) }; sampleLock.unlock()
    }

    private nonisolated func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, let ch = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        if QuillSettings.load().haptics { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }
}
