import Foundation
import Testing
import ParrotCore
@testable import ParrotApp

@MainActor
@Test func vocabularyAddingDeduplicatesWhitespaceAndCaseWithoutErasingNotes() throws {
    try withVocabularySettings { settings, _, _ in
        let originalID = try #require(settings.addLearningVocabularyTerm(
            term: "  Context\n window  ", meaning: "上下文窗口", sourceSentence: "Open the context window."
        ))
        settings.toggleLearningVocabularyFavorite(originalID)
        let repeatedID = settings.addLearningVocabularyTerm(term: "context\tWINDOW")

        #expect(repeatedID == originalID)
        #expect(settings.learningVocabularyEntries.count == 1)
        let entry = try #require(settings.learningVocabularyEntry(for: " CONTEXT   window "))
        #expect(entry.meaning == "上下文窗口")
        #expect(entry.sourceSentence == "Open the context window.")
        #expect(entry.isFavorite)
        #expect(settings.learningSavedExpressionIDs == [originalID])
        #expect(settings.addLearningVocabularyTerm(term: " \n\t ") == nil)
    }
}

@MainActor
@Test func vocabularyEditingRenamesIdentityAndPersistsLearningHistory() throws {
    try withVocabularySettings { settings, defaults, fileURL in
        let savedAt = Date(timeIntervalSince1970: 100)
        let reviewedAt = Date(timeIntervalSince1970: 200)
        let nextReviewAt = Date(timeIntervalSince1970: 300)
        let original = LearningVocabularyEntry(
            id: "latncy", term: "latncy", meaning: "延迟", sourceSentence: "Network latncy increased.",
            sceneLabel: "技术文档", occurrenceCount: 7, masteryStage: 5, wrongCount: 2,
            isFavorite: true, isManual: true, savedAt: savedAt, updatedAt: savedAt,
            lastReviewedAt: reviewedAt, nextReviewAt: nextReviewAt
        )
        settings.restoreLearningVocabularyEntry(original)

        let newID = try #require(settings.updateLearningVocabularyEntry(
            original.id, term: " latency ", meaning: "网络延迟", sourceSentence: "Network latency increased."
        ))
        let reloaded = AppSettings(defaults: defaults, terminologyStore: TerminologyStore(fileURL: fileURL))
        let edited = try #require(reloaded.learningVocabularyEntry(for: "latency"))

        #expect(newID == "latency")
        #expect(reloaded.learningVocabularyEntries.count == 1)
        #expect(edited.id == newID)
        #expect(edited.meaning == "网络延迟")
        #expect(edited.sourceSentence == "Network latency increased.")
        #expect(edited.savedAt == savedAt)
        #expect(edited.lastReviewedAt == reviewedAt)
        #expect(edited.nextReviewAt == nextReviewAt)
        #expect(edited.masteryStage == 5)
        #expect(edited.wrongCount == 2)
        #expect(edited.occurrenceCount == 7)
        #expect(edited.isFavorite)
        #expect(reloaded.learningSavedExpressionIDs == [newID])
        #expect(reloaded.learningMasteredExpressionIDs == [newID])
    }
}

@MainActor
@Test func vocabularyRenamingIntoAnExistingWordMergesWithoutLosingReviewMetadata() throws {
    try withVocabularySettings { settings, _, _ in
        let original = LearningVocabularyEntry(
            id: "ship", term: "ship", meaning: "发布", masteryStage: 2, wrongCount: 3,
            isFavorite: true, savedAt: Date(timeIntervalSince1970: 100)
        )
        let existing = LearningVocabularyEntry(
            id: "ship it", term: "ship it", meaning: "发布它", sourceSentence: "We can ship it tomorrow.",
            occurrenceCount: 8, masteryStage: 4,
            savedAt: Date(timeIntervalSince1970: 200), lastReviewedAt: Date(timeIntervalSince1970: 300)
        )
        settings.restoreLearningVocabularyEntry(original)
        settings.restoreLearningVocabularyEntry(existing)

        let resultingID = settings.updateLearningVocabularyEntry(
            original.id, term: "SHIP  IT", meaning: "发布上线", sourceSentence: "Let's ship it."
        )
        let merged = try #require(settings.learningVocabularyEntry(for: "ship it"))

        #expect(resultingID == existing.id)
        #expect(settings.learningVocabularyEntries.count == 1)
        #expect(merged.meaning == "发布上线\n\n发布它")
        #expect(merged.sourceSentence == "Let's ship it.\n\nWe can ship it tomorrow.")
        #expect(merged.isFavorite)
        #expect(merged.masteryStage == 4)
        #expect(merged.wrongCount == 3)
        #expect(merged.occurrenceCount == 8)
        #expect(merged.savedAt == original.savedAt)
        #expect(merged.lastReviewedAt == existing.lastReviewedAt)
        #expect(settings.learningSavedExpressionIDs == [existing.id])
    }
}

@MainActor
@Test func vocabularyRenameCollisionRetainsExistingNotesWhenEditedFieldsAreBlank() throws {
    try withVocabularySettings { settings, _, _ in
        let original = LearningVocabularyEntry(id: "ship", term: "ship", meaning: "发布")
        let existing = LearningVocabularyEntry(
            id: "ship it", term: "ship it", meaning: "发布它", sourceSentence: "We can ship it tomorrow."
        )
        settings.restoreLearningVocabularyEntry(original)
        settings.restoreLearningVocabularyEntry(existing)

        let resultingID = settings.updateLearningVocabularyEntry(
            original.id, term: "ship it", meaning: " \n ", sourceSentence: "\t "
        )
        let merged = try #require(settings.learningVocabularyEntry(for: "ship it"))

        #expect(resultingID == existing.id)
        #expect(settings.learningVocabularyEntries.count == 1)
        #expect(merged.meaning == existing.meaning)
        #expect(merged.sourceSentence == existing.sourceSentence)
    }
}

@MainActor
@Test func vocabularyOrdinaryEditsAndNoncollidingRenamesCanClearNotes() throws {
    try withVocabularySettings { settings, _, _ in
        let original = LearningVocabularyEntry(
            id: "latncy", term: "latncy", meaning: "延迟", sourceSentence: "Network latncy increased."
        )
        settings.restoreLearningVocabularyEntry(original)

        let sameID = settings.updateLearningVocabularyEntry(
            original.id, term: original.term, meaning: " ", sourceSentence: "\n"
        )
        let edited = try #require(settings.learningVocabularyEntry(for: original.term))
        #expect(sameID == original.id)
        #expect(edited.meaning.isEmpty)
        #expect(edited.sourceSentence.isEmpty)

        _ = settings.addLearningVocabularyTerm(
            term: original.term, meaning: "网络延迟", sourceSentence: "Network latency increased."
        )
        let renamedID = settings.updateLearningVocabularyEntry(
            original.id, term: "latency", meaning: "", sourceSentence: ""
        )
        let renamed = try #require(settings.learningVocabularyEntry(for: "latency"))
        #expect(renamedID == "latency")
        #expect(renamed.meaning.isEmpty)
        #expect(renamed.sourceSentence.isEmpty)
    }
}

@MainActor
@Test func vocabularyRemovingAndRestoringPreservesTheWholeEntry() throws {
    try withVocabularySettings { settings, _, _ in
        let entry = LearningVocabularyEntry(
            id: "proposal", term: "proposal", meaning: "提案", sourceSentence: "Review the proposal.",
            sceneLabel: "商务", occurrenceCount: 4, masteryStage: 5, wrongCount: 2,
            isFavorite: true, savedAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200),
            lastReviewedAt: Date(timeIntervalSince1970: 300), nextReviewAt: Date(timeIntervalSince1970: 400)
        )
        settings.restoreLearningVocabularyEntry(entry)
        settings.removeLearningVocabularyEntry(entry.id)
        #expect(settings.learningVocabularyEntry(for: entry.term) == nil)
        #expect(settings.learningSavedExpressionIDs.isEmpty)
        #expect(settings.learningMasteredExpressionIDs.isEmpty)

        settings.restoreLearningVocabularyEntry(entry)
        #expect(settings.learningVocabularyEntries == [entry])
        #expect(settings.learningSavedExpressionIDs == [entry.id])
        #expect(settings.learningMasteredExpressionIDs == [entry.id])
    }
}

@Test func vocabularyDuplicateStoredIDsDoNotCrashAndUseTheLatestContent() throws {
    let old = LearningVocabularyEntry(
        id: "latency", term: "latency", meaning: "旧释义", updatedAt: Date(timeIntervalSince1970: 100)
    )
    let updated = LearningVocabularyEntry(
        id: "latency", term: "latency", meaning: "网络延迟", updatedAt: Date(timeIntervalSince1970: 200)
    )
    let items = LearningRecommendationEngine.vocabularyItems(
        records: [], occurrenceCounts: [:], vocabularyEntries: [old, updated]
    )

    #expect(items.count == 1)
    #expect(items.first?.expression.meaning == "网络延迟")
}

@MainActor
private func withVocabularySettings(
    _ body: (AppSettings, UserDefaults, URL) throws -> Void
) rethrows {
    let suiteName = "parrot.vocabulary-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
    let fileURL = directory.appendingPathComponent("terminology.json")
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
    let settings = AppSettings(defaults: defaults, terminologyStore: TerminologyStore(fileURL: fileURL))
    try body(settings, defaults, fileURL)
}
