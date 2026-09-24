//
//  Created by ktiays on 2026/9/24.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AVFoundation
import Foundation
import Observation

struct TranscriptionConfiguration: Sendable {
    static let credentialID: ProviderIdentifier = .bailian
    static let defaultEndpoint = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    static let defaultModel = "qwen-audio-3.1-asr-flash"

    let endpoint: URL
    let model: String
    let apiKey: String?

    init(endpoint: String, model: String, apiKey: String?) throws {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else {
            throw ProviderError.invalidConfiguration("The transcription endpoint is invalid.")
        }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw ProviderError.invalidConfiguration("Set a transcription model in Settings → Voice Input.")
        }
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.invalidConfiguration("Set your Bailian API key in Settings → Providers → Bailian.")
        }
        self.endpoint = url
        self.model = model
        self.apiKey = apiKey
    }
}

struct TranscriptionClient {
    var session: URLSession = .shared

    func transcribe(file: URL, configuration: TranscriptionConfiguration) async throws -> String {
        let audio = try Data(contentsOf: file)
        guard audio.count <= 7_000_000 else {
            throw ProviderError.invalidConfiguration("The recording is too large. Please record a shorter message.")
        }
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("disable", forHTTPHeaderField: "X-DashScope-SSE")
        if let key = configuration.apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "input": ["messages": [[
                "role": "user",
                "content": [[
                    "type": "input_audio",
                    "input_audio": ["data": "data:audio/mp4;base64," + audio.base64EncodedString()],
                ]],
            ]]],
            "parameters": ["format": "m4a", "sample_rate": "44100"],
        ])
        let (data, response) = try await session.upload(for: request, from: body)
        guard let response = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            struct APIError: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            throw ProviderError.httpStatus(response.statusCode, message ?? "Transcription failed (HTTP \(response.statusCode)).")
        }
        struct Result: Decodable {
            struct Output: Decodable { let text: String }
            let output: Output
        }
        let text = try JSONDecoder().decode(Result.self, from: data).output.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ProviderError.invalidConfiguration("No speech was recognized. Try recording again.")
        }
        return text
    }
}

@MainActor
@Observable
final class VoiceInput: NSObject, AVAudioRecorderDelegate {
    enum Phase {
        case idle, requestingPermission, recording, transcribing
    }

    static let meteringInterval: TimeInterval = 0.05

    private(set) var phase: Phase = .idle
    private(set) var levels: [Float] = []
    private(set) var lastLevelDate = Date.distantPast
    private var meteringTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    private var configuration: TranscriptionConfiguration?
    private var recordingLimitReached: (() -> Void)?
    private var reportError: ((String) -> Void)?

    var isActive: Bool { phase != .idle }

    func start(configuration: TranscriptionConfiguration, onRecordingLimit: @escaping () -> Void, onError: @escaping (String) -> Void) {
        guard !isActive else { return }
        self.configuration = configuration
        reportError = onError
        recordingLimitReached = onRecordingLimit
        phase = .requestingPermission
        let id = UUID()
        operationID = id
        task = Task { [weak self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard let self, self.operationID == id, !Task.isCancelled else { return }
            do {
                guard allowed else {
                    throw ProviderError.invalidConfiguration("Allow microphone access in System Settings → Privacy & Security → Microphone.")
                }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
                self.file = url
                let recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64000,
                ])
                self.recorder = recorder
                recorder.delegate = self
                recorder.isMeteringEnabled = true
                guard recorder.record(forDuration: 299) else {
                    throw ProviderError.invalidConfiguration("Could not start microphone recording.")
                }
                self.phase = .recording
                self.startMetering()
                self.task = nil
            } catch {
                self.cancel()
                onError(error.localizedDescription)
            }
        }
    }

    func finish(onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        guard phase == .recording, let file, let configuration else { return }
        phase = .transcribing
        meteringTask?.cancel()
        meteringTask = nil
        recorder?.stop()
        recorder = nil
        let id = operationID
        task = Task { [weak self] in
            do {
                let text = try await TranscriptionClient().transcribe(file: file, configuration: configuration)
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                self.cancel()
                onText(text)
            } catch {
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                self.cancel()
                onError(error.localizedDescription)
            }
        }
    }

    func cancel() {
        operationID = UUID()
        meteringTask?.cancel()
        meteringTask = nil
        levels = []
        task?.cancel()
        task = nil
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        configuration = nil
        reportError = nil
        recordingLimitReached = nil
        phase = .idle
    }

    private func startMetering() {
        levels = []
        meteringTask = Task { [weak self] in
            var deadline = ContinuousClock.now
            while !Task.isCancelled {
                guard let self, self.phase == .recording, let recorder = self.recorder else { return }
                recorder.updateMeters()
                // Decibels are already logarithmic, so a linear map over the speech range
                // (-45 dB noise floor to -15 dB loud speech) tracks perceived loudness.
                let power = recorder.averagePower(forChannel: 0)
                self.levels.append(min(1, max(0, (power + 45) / 30)))
                if self.levels.count > 160 {
                    self.levels.removeFirst(self.levels.count - 160)
                }
                self.lastLevelDate = .now
                // Sleep until a fixed deadline so samples arrive at a steady cadence for the scrolling waveform.
                deadline += .seconds(Self.meteringInterval)
                do {
                    try await Task.sleep(until: deadline, clock: .continuous)
                } catch {
                    return
                }
            }
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.file == url, self.phase == .recording else { return }
            if flag {
                self.recordingLimitReached?()
            } else {
                let onError = self.reportError
                self.cancel()
                onError?("Recording was interrupted. Please try again.")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let url = recorder.url
        let message = error?.localizedDescription ?? "Audio recording failed."
        Task { @MainActor [weak self] in
            guard let self, self.file == url else { return }
            let onError = self.reportError
            self.cancel()
            onError?(message)
        }
    }
}
