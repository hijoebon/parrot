import AVFoundation
import OSLog
import ParrotCore

@MainActor
public final class SystemTTSProvider: NSObject, TTSProvider, AVSpeechSynthesizerDelegate {
    public enum VoiceQuality: Equatable, Sendable {
        case standard
        case enhanced
        case premium
    }

    public struct VoiceAvailability: Equatable, Sendable {
        public let name: String
        public let quality: VoiceQuality
    }

    public let id = "system"
    public let displayName = "离线语音合成"
    public let isOfflineCapable = true
    private let synth = AVSpeechSynthesizer()
    private let playbackLog = Logger(subsystem: "com.parrot.app.speech", category: "SystemVoice")
    private var playback: Playback?

    private struct Playback {
        let id: UUID
        let utterance: AVSpeechUtterance
        let continuation: CheckedContinuation<Void, Error>
    }

    public override init() {
        super.init()
        synth.delegate = self
    }

    public static func voiceAvailability(for language: Language) -> VoiceAvailability? {
        guard let code = voiceCode(for: language),
              let voice = preferredVoice(for: code),
              voice.identifier.hasPrefix("com.apple."),
              !isPersonalOrNovelty(voice) else { return nil }
        let quality: VoiceQuality
        switch voice.quality {
        case .enhanced: quality = .enhanced
        case .premium: quality = .premium
        case .default: quality = .standard
        @unknown default: quality = .standard
        }
        return VoiceAvailability(name: voice.name, quality: quality)
    }

    public func speak(_ text: String, language: Language) async throws {
        try Task.checkCancellation()
        let playbackID = UUID()
        let utterance = AVSpeechUtterance(string: text)
        if let code = Self.voiceCode(for: language) {
            utterance.voice = Self.preferredVoice(for: code)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                stopPlayback()
                playback = Playback(id: playbackID, utterance: utterance, continuation: continuation)
                synth.speak(utterance)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard self?.playback?.id == playbackID else { return }
                self?.stopPlayback()
            }
        }
    }

    public func stop() async {
        stopPlayback()
    }

    private func stopPlayback() {
        guard let playback else { return }
        self.playback = nil
        synth.stopSpeaking(at: .immediate)
        playback.continuation.resume(throwing: CancellationError())
    }

    private func finishPlayback(of utterance: AVSpeechUtterance, result: Result<Void, Error>) {
        guard let playback, playback.utterance === utterance else { return }
        self.playback = nil
        playback.continuation.resume(with: result)
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.playback?.utterance === utterance,
                  let voice = utterance.voice, voice.quality != .default else { return }
            if #available(macOS 14, iOS 17, *), voice.voiceTraits.contains(.isPersonalVoice) { return }
            self.playbackLog.notice("Started system voice \(voice.identifier, privacy: .public) locale \(voice.language, privacy: .public)")
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finishPlayback(of: utterance, result: .success(())) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finishPlayback(of: utterance, result: .failure(CancellationError())) }
    }

    private static func preferredVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let code = languageCode.replacingOccurrences(of: "_", with: "-")
        let systemVoice = AVSpeechSynthesisVoice(language: code)
        let preferredLocale = code.contains("-") ? code : (systemVoice?.language ?? code)
        let isLanguageOnly = !preferredLocale.contains("-")
        let preferredTag = preferredLocale.lowercased()

        let higherQualityVoices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            let tag = voice.language.lowercased()
            let matchesLocale = tag == preferredTag || (isLanguageOnly && tag.hasPrefix(preferredTag + "-"))
            return matchesLocale
                && (voice.quality == .premium || voice.quality == .enhanced)
                && !isPersonalOrNovelty(voice)
        }

        return higherQualityVoices.first { $0.quality == .premium }
            ?? higherQualityVoices.first { $0.quality == .enhanced }
            ?? systemVoice
    }

    private static func isPersonalOrNovelty(_ voice: AVSpeechSynthesisVoice) -> Bool {
        if #available(macOS 14, iOS 17, *) {
            return voice.voiceTraits.contains(.isNoveltyVoice) || voice.voiceTraits.contains(.isPersonalVoice)
        }
        return false
    }

    private static func voiceCode(for language: Language) -> String? {
        switch language {
        case .zh: return "zh-CN"
        case .en: return "en-US"
        case .ja: return "ja-JP"
        case .ko: return "ko-KR"
        case .fr: return "fr-FR"
        case .de: return "de-DE"
        case .es: return "es-ES"
        case .ru: return "ru-RU"
        case .custom(let c): return c
        case .auto: return nil
        }
    }
}
