import Foundation

public protocol TTSProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isOfflineCapable: Bool { get }
    func speak(_ text: String, language: Language) async throws
    func stop() async
}

@MainActor
public final class TTSCoordinator {
    private var providers: [String: TTSProvider] = [:]
    private var playbackProvider: TTSProvider?
    private var playbackTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    public var defaultProviderId: String = "system" {
        didSet { if oldValue != defaultProviderId { stopPlayback() } }
    }

    public init() {}

    public func register(_ provider: TTSProvider) {
        providers[provider.id] = provider
    }

    public func provider(id: String) -> TTSProvider? { providers[id] }

    public func activeProvider() -> TTSProvider? {
        if let p = providers[defaultProviderId] { return p }
        return providers["system"]
    }

    public func speak(_ text: String, language: Language) async {
        guard !Task.isCancelled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        play(text, language: language)
        await playbackTask?.value
    }

    public func play(_ text: String, language: Language, onCompletion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stopPlayback()
        guard let provider = activeProvider() else {
            onCompletion?(.failure(ProviderError.notConfigured))
            return
        }

        playbackProvider = provider
        let pendingStop = stopTask
        playbackTask = Task {
            await pendingStop?.value
            do {
                try Task.checkCancellation()
                try await provider.speak(text, language: language)
                try Task.checkCancellation()
                onCompletion?(.success(()))
            } catch {
                onCompletion?(.failure(Task.isCancelled ? CancellationError() : error))
            }
        }
    }

    public func stop() async {
        stopPlayback()
        await stopTask?.value
    }

    public func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        guard let provider = playbackProvider else { return }
        playbackProvider = nil
        let pendingStop = stopTask
        stopTask = Task {
            await pendingStop?.value
            await provider.stop()
        }
    }
}
