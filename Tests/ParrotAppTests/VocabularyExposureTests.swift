import Foundation
import Testing
import ParrotCore
@testable import ParrotApp

@Test func vocabularyExposureCountsDistinctPersistedTranslations() {
    let older = Date(timeIntervalSince1970: 1_000)
    let newer = Date(timeIntervalSince1970: 2_000)
    let repeated = TranslationRecord(
        sourceText: "Latency, latency, and timing.",
        translated: "Latency and timing.",
        providerId: "primary",
        outcomes: [
            .init(providerId: "primary", displayName: "Primary", translated: "Latency and timing."),
            .init(providerId: "fallback", displayName: "Fallback", translated: "Latency and duration.")
        ],
        sourceLang: "en", targetLang: "en", createdAt: newer
    )
    let earlier = TranslationRecord(
        sourceText: "这次有延迟。",
        translated: "There was LATENCY.",
        providerId: "primary",
        sourceLang: "zh", targetLang: "en", createdAt: older
    )
    let stats = LearningRecommendationEngine.vocabularyExposureStats(
        records: [repeated, earlier, repeated], terms: ["latency", "LATENCY", "duration", "unseen", ""]
    )

    #expect(stats["latency"] == LearningVocabularyExposure(appearanceCount: 2, lastSeenAt: newer))
    #expect(stats["duration"] == LearningVocabularyExposure(appearanceCount: 1, lastSeenAt: newer))
    #expect((stats["unseen"] ?? .unseen).appearanceCount == 0)
    #expect((stats["unseen"] ?? .unseen).lastSeenAt == nil)
    #expect(stats.count == 2)
}

@Test func vocabularyExposureNormalizesPhrasesAndKeepsWordBoundaries() {
    let date = Date(timeIntervalSince1970: 1_000)
    let record = TranslationRecord(
        sourceText: "Café\n au lait and C++. Shipyard ships _ship. мирный.",
        translated: "The world says МИР.",
        providerId: "test",
        sourceLang: "en", targetLang: "ru", createdAt: date
    )
    let stats = LearningRecommendationEngine.vocabularyExposureStats(
        records: [record], terms: ["CAFE  AU LAIT", "C++", "ship", "мир", "мирн", "   "]
    )
    let seen = LearningVocabularyExposure(appearanceCount: 1, lastSeenAt: date)

    #expect(stats["cafe au lait"] == seen)
    #expect(stats["c++"] == seen)
    #expect(stats["мир"] == seen)
    #expect(stats["ship"] == nil)
    #expect(stats["мирн"] == nil)
}

@Test func vocabularyExposureFindsTermsInsideUnspacedEastAsianText() {
    let date = Date(timeIntervalSince1970: 1_000)
    let record = TranslationRecord(
        sourceText: "调用API时先阅读中文文档。",
        translated: "このカタカナを読む。한글을 읽는다。".decomposedStringWithCanonicalMapping,
        providerId: "test",
        sourceLang: "zh", targetLang: "ja", createdAt: date
    )
    let stats = LearningRecommendationEngine.vocabularyExposureStats(
        records: [record], terms: ["API", "中文", "カタカナ", "한글", "文案"]
    )

    #expect(Set(stats.keys) == ["api", "中文", "カタカナ", "한글"])
    #expect(stats.values.allSatisfy { $0.appearanceCount == 1 && $0.lastSeenAt == date })
}
