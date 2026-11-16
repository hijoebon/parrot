import SwiftUI
import ParrotCore

/// Routes read-aloud to the configured TTS provider (default: system offline).
@MainActor
final class Speaker: ObservableObject {
    private struct Playback {
        let id = UUID()
        let isPreview: Bool
    }

    static let shared = Speaker()
    weak var coordinator: TTSCoordinator?
    var onFailure: ((Error) -> Void)?
    @Published private var playback: Playback?

    var isPlaying: Bool { playback != nil }
    var isPreviewing: Bool { playback?.isPreview == true }

    func speak(_ text: String, language: Language) {
        play(text, language: language, isPreview: false, onFailure: onFailure)
    }

    func preview(_ text: String, language: Language, onFailure: @escaping (Error) -> Void) {
        play(text, language: language, isPreview: true, onFailure: onFailure)
    }

    func stop() {
        playback = nil
        coordinator?.stopPlayback()
    }

    private func play(
        _ text: String,
        language: Language,
        isPreview: Bool,
        onFailure: ((Error) -> Void)?
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let coordinator else {
            onFailure?(ProviderError.notConfigured)
            return
        }
        let request = Playback(isPreview: isPreview)
        playback = request
        let resolvedLanguage = language == .auto ? (LanguageDetector().detect(text) ?? .auto) : language
        coordinator.play(text, language: resolvedLanguage) { [weak self] result in
            guard self?.playback?.id == request.id else { return }
            self?.playback = nil
            if case .failure(let error) = result, !(error is CancellationError) {
                onFailure?(error)
            }
        }
    }

    static func recoveryMessage(for error: Error) -> String {
        switch error as? ProviderError {
        case .notConfigured, .auth:
            return L("请检查语音服务的密钥和区域后重试。")
        case .rateLimited:
            return L("语音服务已达到限额，请稍后重试。")
        case .unsupportedLanguage:
            return L("当前语音服务不支持此语言，请切换朗读引擎。")
        case .service:
            return L("语音服务暂时无法朗读。请检查配置，或切换为离线语音。")
        default:
            return L("无法播放语音。请重试，或在朗读设置中切换引擎。")
        }
    }
}

@MainActor
struct StopSpeechButton: View {
    @ObservedObject private var speaker = Speaker.shared

    var body: some View {
        if speaker.isPlaying {
            IconButton("stop.fill", help: "停止朗读", action: speaker.stop)
                .accessibilityIdentifier("speech.stop")
        }
    }
}
