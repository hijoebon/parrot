import AppKit
import SwiftUI
import ParrotCore

@MainActor
final class LearningReviewWindow {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        state.refreshLearningHistory()
        if window == nil {
            let hosting = NSHostingController(rootView: LearningReviewView(state: state))
            let win = NSWindow(contentViewController: hosting)
            configureTitle(for: win)
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 820, height: 520))
            win.contentMinSize = NSSize(width: 700, height: 440)
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            WindowPlacement.center(window)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshTitle() {
        if let window {
            configureTitle(for: window)
        }
    }

    private func configureTitle(for window: NSWindow) {
        let title = L("今日复习")
        window.title = title
        window.setAccessibilityTitle(title)
    }
}

@MainActor
final class VocabularyWindow {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        state.refreshLearningHistory()
        if window == nil {
            let hosting = NSHostingController(rootView: VocabularyView(state: state))
            let win = NSWindow(contentViewController: hosting)
            configureTitle(for: win)
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 900, height: 540))
            win.contentMinSize = NSSize(width: 700, height: 460)
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            WindowPlacement.center(window)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshTitle() {
        if let window {
            configureTitle(for: window)
        }
    }

    private func configureTitle(for window: NSWindow) {
        let title = L("单词本")
        window.title = title
        window.setAccessibilityTitle(title)
    }
}

private struct LearningReviewView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: AppSettings

    @State private var selectedID: String?
    @State private var selectedAnswer: String?
    @State private var feedbackText: String = ""

    init(state: AppState) {
        self.state = state
        self.settings = state.settings
    }

    private var cards: [LearningReviewCard] {
        LearningRecommendationEngine.reviewCards(from: state.learningVocabularyItems, limit: reviewLimit)
    }

    private var reviewLimit: Int {
        switch state.settings.learningReviewIntensity {
        case "standard": return 18
        case "intense": return 30
        default: return 12
        }
    }

    private var reviewDurationText: String {
        switch state.settings.learningReviewIntensity {
        case "standard": return "5 分钟队列"
        case "intense": return "10 分钟队列"
        default: return "3 分钟队列"
        }
    }

    private var selectedCard: LearningReviewCard? {
        if let selectedID,
           let card = cards.first(where: { $0.id == selectedID }) {
            return card
        }
        return cards.first
    }

    var body: some View {
        HStack(spacing: 0) {
            queueColumn
            Divider()
            reviewDetail
        }
        .frame(minWidth: 700, minHeight: 440)
        .onAppear {
            state.refreshLearningHistory()
            selectedID = selectedCard?.id
        }
        .onChange(of: cards.map(\.id)) { _ in
            if selectedID == nil || !cards.contains(where: { $0.id == selectedID }) {
                selectedID = cards.first?.id
                selectedAnswer = nil
                feedbackText = ""
            }
        }
    }

    private var queueColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L(reviewDurationText))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Text(L("%d 个来自历史翻译，高频表达优先。", cards.count))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.label2)
            }
            .padding(Theme.Spacing.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            if cards.isEmpty {
                emptyQueue
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            Button {
                                selectedID = card.id
                                selectedAnswer = nil
                                feedbackText = ""
                            } label: {
                                HStack(spacing: Theme.Spacing.s8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(card.expression.term)
                                            .font(Theme.Font.body)
                                            .foregroundStyle(Theme.Palette.label)
                                            .lineLimit(1)
                                        Text("\(card.mode) · \(card.expression.displayCount)")
                                            .font(Theme.Font.caption)
                                            .foregroundStyle(Theme.Palette.label3)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text("\(index + 1)")
                                        .font(Theme.Font.caption.monospacedDigit())
                                        .foregroundStyle(Theme.Palette.label2)
                                        .frame(minWidth: 24, minHeight: 20)
                                        .background(Theme.Palette.bgControl)
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                .background(selectedCard?.id == card.id ? Theme.Palette.bgSelection : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.s8)
                }
            }
        }
        .frame(width: 250)
        .background(Theme.Palette.bgSidebar)
    }

    private var emptyQueue: some View {
        VStack(spacing: Theme.Spacing.s8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Palette.label3)
            Text(L("暂无可复习表达"))
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Palette.label2)
            Text(L("完成几次英译或译英后，高频表达会出现在这里。"))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.label3)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var reviewDetail: some View {
        if let card = selectedCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    HStack(spacing: Theme.Spacing.s8) {
                        LearningWindowTag(card.mode)
                        Text(card.origin)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.label3)
                        Spacer()
                        FrequencyBadge(count: card.expression.occurrenceCount)
                    }
                    Text(card.title)
                        .font(Theme.Font.term)
                        .foregroundStyle(Theme.Palette.label)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.prompt)
                        .font(Theme.Font.result)
                        .foregroundStyle(Theme.Palette.label2)
                    VStack(spacing: Theme.Spacing.s8) {
                        ForEach(card.options, id: \.self) { option in
                            Button {
                                selectedAnswer = option
                                let correct = isCorrect(option, card: card)
                                settings.recordLearningReview(card.expression, correct: correct)
                                feedbackText = correct
                                    ? L("回答正确。该表达进入下一掌握阶段。")
                                    : L("答案是 %@。该表达会保留在今日队列。", card.correctAnswer)
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(Theme.Font.body)
                                    Spacer()
                                    if selectedAnswer != nil, isCorrect(option, card: card) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.s12)
                                .frame(minHeight: 38)
                                .foregroundStyle(optionForeground(option, card: card))
                                .background(optionBackground(option, card: card))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(optionBorder(option, card: card), lineWidth: 0.5))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
                .background(Theme.Palette.bgContent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.group).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))

                if !feedbackText.isEmpty {
                    Text(feedbackText)
                        .font(Theme.Font.callout)
                        .foregroundStyle(selectedAnswer.map { isCorrect($0, card: card) } == true ? Theme.Palette.success : Theme.Palette.warning)
                        .padding(.horizontal, Theme.Spacing.s12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((selectedAnswer.map { isCorrect($0, card: card) } == true ? Theme.Palette.success : Theme.Palette.warning).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                }

                HStack {
                    Spacer()
                    Button {
                        feedbackText = L("已保留在今日队列，稍后会再次出现。")
                    } label: {
                        Text(L("稍后再练"))
                            .font(Theme.Font.callout)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    Button {
                        moveToNextCard()
                    } label: {
                        Label(L("下一张"), systemImage: "arrow.right")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.Palette.bgCanvas)
        } else {
            emptyReviewDetail
        }
    }

    private var emptyReviewDetail: some View {
        VStack(spacing: Theme.Spacing.s8) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 34))
                .foregroundStyle(Theme.Palette.label3)
            Text(L("没有复习卡片"))
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Palette.label2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.bgCanvas)
    }

    private func isCorrect(_ option: String, card: LearningReviewCard) -> Bool {
        LearningRecommendationEngine.key(for: option) == LearningRecommendationEngine.key(for: card.correctAnswer)
    }

    private func optionForeground(_ option: String, card: LearningReviewCard) -> Color {
        guard let selectedAnswer else { return Theme.Palette.label }
        if isCorrect(option, card: card) { return Theme.Palette.success }
        if selectedAnswer == option { return Theme.Palette.danger }
        return Theme.Palette.label2
    }

    private func optionBackground(_ option: String, card: LearningReviewCard) -> Color {
        guard let selectedAnswer else { return Theme.Palette.bgControl }
        if isCorrect(option, card: card) { return Theme.Palette.success.opacity(0.14) }
        if selectedAnswer == option { return Theme.Palette.danger.opacity(0.12) }
        return Theme.Palette.bgControl
    }

    private func optionBorder(_ option: String, card: LearningReviewCard) -> Color {
        guard let selectedAnswer else { return Theme.Palette.separator }
        if isCorrect(option, card: card) { return Theme.Palette.success.opacity(0.45) }
        if selectedAnswer == option { return Theme.Palette.danger.opacity(0.45) }
        return Theme.Palette.separator
    }

    private func moveToNextCard() {
        guard let current = selectedCard,
              let index = cards.firstIndex(where: { $0.id == current.id }) else { return }
        let next = cards[(index + 1) % cards.count]
        selectedID = next.id
        selectedAnswer = nil
        feedbackText = ""
    }
}

private struct VocabularyView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: AppSettings

    private enum Scope: String, CaseIterable, Identifiable {
        case all, favorites, due
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .favorites: return "收藏"
            case .due: return "待复习"
            }
        }
    }

    private enum Editor: Identifiable {
        case add
        case edit(LearningVocabularyEntry)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let entry): return entry.id
            }
        }
    }

    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var selectedID: String?
    @State private var editor: Editor?
    @State private var cachedItems: [LearningVocabularyItem] = []
    @State private var removedEntries: [LearningVocabularyEntry] = []

    init(state: AppState) {
        self.state = state
        self.settings = state.settings
    }

    private var visibleItems: [LearningVocabularyItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return cachedItems.filter { item in
            if scope == .due && !item.isDue { return false }
            if scope == .favorites && !item.isFavorite { return false }
            guard !q.isEmpty else { return true }
            return [item.expression.term, item.entry?.meaning ?? "", item.entry?.sourceSentence ?? ""]
                .contains { $0.localizedStandardContains(q) }
        }
    }

    private var selectedItem: LearningVocabularyItem? {
        visibleItems.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                listColumn
                    .frame(minWidth: 270, idealWidth: 300, maxWidth: 370)
                detailColumn
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            if let removedEntry = removedEntries.last {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(L("已移除 %@", removedEntry.term))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L("撤销"), action: undoRemoval)
                        .accessibilityIdentifier("vocabulary.undo")
                }
                .font(.system(size: 12))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .frame(minWidth: 700, minHeight: 460)
        .onAppear {
            reloadVocabularyItems()
            reconcileSelection()
        }
        .onChange(of: settings.learningVocabularyEntries) { _ in
            reloadVocabularyItems()
            reconcileSelection()
        }
        .onChange(of: visibleItems.map(\.id)) { _ in reconcileSelection() }
        .sheet(item: $editor) { mode in
            switch mode {
            case .add:
                VocabularyEntryEditor(
                    title: "添加单词",
                    term: "",
                    meaning: "",
                    sourceSentence: "",
                    onCancel: { editor = nil },
                    onSave: { term, meaning, source in
                        let id = settings.addLearningVocabularyTerm(term: term, meaning: meaning, sourceSentence: source)
                        if let id { finishSave(id) }
                        return id
                    }
                )
            case .edit(let entry):
                VocabularyEntryEditor(
                    title: "编辑单词",
                    term: entry.term,
                    meaning: entry.meaning,
                    sourceSentence: entry.sourceSentence,
                    onCancel: { editor = nil },
                    onSave: { term, meaning, source in
                        let id = settings.updateLearningVocabularyEntry(entry.id, term: term, meaning: meaning, sourceSentence: source)
                        if let id { finishSave(id) }
                        return id
                    }
                )
            }
        }
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("单词本"))
                    .font(.system(size: 16, weight: .semibold))
                Text("\(cachedItems.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button { editor = .add } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 25, height: 25)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L("添加单词"))
                .accessibilityLabel(L("添加单词"))
                .accessibilityIdentifier("vocabulary.add")
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("搜索单词、释义或原句"), text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("vocabulary.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("清除搜索"))
                    .accessibilityLabel(L("清除搜索"))
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Picker(L("筛选单词"), selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(L(scope.title)).tag(scope)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            if visibleItems.isEmpty {
                emptyList
            } else {
                List(selection: $selectedID) {
                    ForEach(visibleItems) { item in
                        VocabularyRow(item: item)
                            .tag(item.id)
                            .contextMenu {
                                if let entry = item.entry {
                                    Button(L("编辑单词")) { editor = .edit(entry) }
                                    Button(item.isFavorite ? L("取消收藏") : L("收藏")) {
                                        settings.toggleLearningVocabularyFavorite(item.id)
                                    }
                                    Divider()
                                    Button(L("移除单词")) { remove(item) }
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("vocabulary.list")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyList: some View {
        VStack(spacing: 9) {
            Image(systemName: query.isEmpty ? "text.book.closed" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L(emptyTitle))
                .font(.system(size: 13, weight: .medium))
            Text(L(emptyDescription))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if cachedItems.isEmpty && query.isEmpty {
                Button(L("添加单词")) { editor = .add }
                    .padding(.top, 3)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !query.isEmpty { return "没有找到匹配的单词" }
        if scope == .favorites { return "还没有收藏" }
        if scope == .due, !cachedItems.isEmpty { return "暂时没有待复习单词" }
        return "留下想记住的单词"
    }

    private var emptyDescription: String {
        if !query.isEmpty { return "试试其他关键词，或清除搜索。" }
        if scope == .favorites { return "点亮单词旁的星标，方便以后找到。" }
        if scope == .due, !cachedItems.isEmpty { return "到复习时间的单词会出现在这里。" }
        return "在翻译结果中加入，或点上方的 + 手动添加。"
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let item = selectedItem {
            vocabularyDetail(item)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                Text(L(cachedItems.isEmpty ? "你的单词，会留在这里" : "选择一个单词"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func vocabularyDetail(_ item: LearningVocabularyItem) -> some View {
        let expression = item.expression
        let meaning = item.entry?.meaning ?? ""
        let sourceSentence = item.entry?.sourceSentence ?? ""
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()
                Button {
                    settings.toggleLearningVocabularyFavorite(item.id)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(item.isFavorite ? Color(nsColor: .systemYellow) : .secondary)
                }
                .help(L(item.isFavorite ? "取消收藏" : "收藏"))
                .accessibilityLabel(L(item.isFavorite ? "取消收藏" : "收藏"))
                .accessibilityIdentifier("vocabulary.favorite")
                Button {
                    state.speakTranslation(expression.term)
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .help(L("朗读"))
                .accessibilityLabel(L("朗读"))
                Button(L("编辑")) {
                    if let entry = item.entry { editor = .edit(entry) }
                }
                .accessibilityIdentifier("vocabulary.edit")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13))
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(expression.term)
                            .font(Theme.Font.term)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("vocabulary.detail.term")
                        if let phonetic = expression.phonetic, !phonetic.isEmpty {
                            Text(phonetic)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    detailSection("释义", meaning, emptyText: "还没有释义，点“编辑”补充。")
                    if !sourceSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailSection("原句", sourceSentence)
                    }
                    Divider()
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L(expression.masteryStage >= 5 ? "已掌握" : "学习中"))
                                .font(.system(size: 12, weight: .medium))
                            Text(L("下次复习：%@", item.nextReviewLabel))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if expression.masteryStage < 5 {
                            Button(L("标记掌握")) {
                                settings.markLearningMastered(expression, sceneLabel: item.sceneLabel)
                            }
                            .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel(L("已掌握"))
                        }
                    }
                    if let entry = item.entry {
                        let dateStyle = Date.FormatStyle(
                            date: .abbreviated,
                            time: .omitted,
                            locale: Locale(identifier: L10n.languageCode())
                        )
                        Text(L("添加于 %@", entry.savedAt.formatted(dateStyle)))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button(L("移除单词")) { remove(item) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("vocabulary.remove")
                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func detailSection(_ title: String, _ text: String, emptyText: String = "") -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L(title))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L(emptyText))
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            } else {
                Text(text)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reloadVocabularyItems() {
        cachedItems = state.learningVocabularyItems.filter(\.isSaved)
    }

    private func reconcileSelection() {
        if selectedID == nil || !visibleItems.contains(where: { $0.id == selectedID }) {
            selectedID = visibleItems.first?.id
        }
    }

    private func finishSave(_ id: String) {
        scope = .all
        query = ""
        reloadVocabularyItems()
        selectedID = id
        editor = nil
    }

    private func remove(_ item: LearningVocabularyItem) {
        guard let entry = item.entry else { return }
        removedEntries.append(entry)
        settings.removeLearningVocabularyEntry(item.id)
        reloadVocabularyItems()
        reconcileSelection()
    }

    private func undoRemoval() {
        guard let entry = removedEntries.popLast() else { return }
        settings.restoreLearningVocabularyEntry(entry)
        scope = .all
        query = ""
        reloadVocabularyItems()
        selectedID = entry.id
    }
}

private struct VocabularyRow: View {
    let item: LearningVocabularyItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(item.expression.term)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L("已收藏"))
                }
            }
            Text((item.entry?.meaning ?? "").isEmpty ? L("未填写释义") : (item.entry?.meaning ?? ""))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct LearningWindowTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(L(text).uppercased())
            .font(Theme.Font.tag)
            .lineLimit(1)
            .foregroundStyle(Theme.Palette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Palette.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
