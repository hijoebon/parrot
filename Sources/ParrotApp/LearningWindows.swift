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
private final class VocabularyWindowPresentation: ObservableObject {
    @Published var isOpen = false
}

@MainActor
final class VocabularyWindow: NSObject, NSWindowDelegate {
    private let state: AppState
    private let presentation = VocabularyWindowPresentation()
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        state.refreshLearningHistory()
        if window == nil {
            let hosting = NSHostingController(rootView: VocabularyView(state: state, presentation: presentation))
            let win = NSWindow(contentViewController: hosting)
            configureTitle(for: win)
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.setContentSize(NSSize(width: 900, height: 540))
            win.contentMinSize = NSSize(width: 700, height: 460)
            window = win
        }
        presentation.isOpen = true
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            WindowPlacement.center(window)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        presentation.isOpen = false
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
    @ObservedObject var presentation: VocabularyWindowPresentation

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

    private enum SortField: String, CaseIterable, Identifiable {
        case added, name, appearances, lastSeen, views, lastViewed, nextReview
        var id: String { rawValue }

        var title: String {
            switch self {
            case .added: return "添加时间"
            case .name: return "单词名称"
            case .appearances: return "出现记录"
            case .lastSeen: return "最近出现"
            case .views: return "查看次数"
            case .lastViewed: return "最近查看"
            case .nextReview: return "下次复习"
            }
        }
    }

    private struct ExposureRequest: Equatable {
        let isOpen: Bool
        let terms: [String]
    }

    @AppStorage("wordbook.sortField") private var sortField: SortField = .added
    @AppStorage("wordbook.sortAscending") private var sortAscending = false
    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var selectedID: String?
    @State private var explicitlyViewedID: String?
    @State private var editor: Editor?
    @State private var cachedItems: [LearningVocabularyItem] = []
    @State private var removedEntries: [LearningVocabularyEntry] = []
    @State private var exposureStats: [String: LearningVocabularyExposure] = [:]
    @State private var measuredTerms: Set<String> = []

    init(state: AppState, presentation: VocabularyWindowPresentation) {
        self.state = state
        self.settings = state.settings
        self.presentation = presentation
    }

    private var visibleItems: [LearningVocabularyItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return cachedItems.filter { item in
            if scope == .due && !item.isDue { return false }
            if scope == .favorites && !item.isFavorite { return false }
            guard !q.isEmpty else { return true }
            return [item.expression.term, item.entry?.meaning ?? "", item.entry?.sourceSentence ?? "",
                    item.entry?.source?.title ?? "", item.entry?.source?.url?.absoluteString ?? ""]
                .contains { $0.localizedStandardContains(q) }
        }
        .sorted(by: comesBefore)
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
        .onChange(of: presentation.isOpen) { isOpen in
            if !isOpen { explicitlyViewedID = nil }
        }
        .task(id: exposureRequest) { [exposureRequest] in
            await observeHistory(for: exposureRequest)
        }
        .sheet(item: $editor) { mode in
            switch mode {
            case .add:
                VocabularyEntryEditor(
                    title: "添加单词",
                    term: "",
                    meaning: "",
                    sourceSentence: "",
                    onCancel: { editor = nil },
                    onSave: { term, meaning, sentence, source in
                        let id = settings.addLearningVocabularyTerm(
                            term: term, meaning: meaning, sourceSentence: sentence, source: source
                        )
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
                    source: entry.source,
                    onCancel: { editor = nil },
                    onSave: { term, meaning, sentence, source in
                        let id = settings.updateLearningVocabularyEntry(
                            entry.id, term: term, meaning: meaning, sourceSentence: sentence, source: source
                        )
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
                TextField(L("搜索单词、释义、原句或来源"), text: $query)
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

            sortControls

            if visibleItems.isEmpty {
                emptyList
            } else {
                List(selection: userSelection) {
                    ForEach(visibleItems) { item in
                        VocabularyRow(
                            item: item,
                            exposure: exposure(for: item),
                            latestDate: sortField == .lastViewed ? item.entry?.lastViewedAt : exposure(for: item)?.lastSeenAt,
                            latestDateTitle: sortField == .lastViewed ? "最近查看" : "最近出现"
                        )
                            .simultaneousGesture(TapGesture().onEnded { selectWord(item.id) })
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

    private var sortControls: some View {
        HStack(spacing: 8) {
            Text(L("排序"))
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
            Picker(L("排序"), selection: $sortField) {
                ForEach(SortField.allCases) { field in
                    Text(L(field.title)).tag(field)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .accessibilityIdentifier("vocabulary.sort.field")

            Button { sortAscending.toggle() } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(L(sortAscending ? "切换为降序" : "切换为升序"))
            .accessibilityLabel(L("排序方向"))
            .accessibilityValue(L(sortAscending ? "升序" : "降序"))
            .accessibilityIdentifier("vocabulary.sort.direction")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
                StopSpeechButton()
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
                    state.speakVocabulary(expression.term, context: sourceSentence)
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
                    if !sourceSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.entry?.source != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            if !sourceSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                detailSection("原句", sourceSentence, onSpeak: {
                                    Speaker.shared.speak(sourceSentence, language: .auto)
                                })
                            }
                            if let source = item.entry?.source {
                                sourceReference(source)
                            }
                        }
                    }
                    activitySection(item)
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

    @ViewBuilder
    private func sourceReference(_ source: LearningVocabularySource) -> some View {
        if let url = source.url {
            let host = url.host ?? url.absoluteString
            Link(destination: url) {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title ?? host)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if source.title != nil {
                            Text(host)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.Palette.bgControl, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .help(url.absoluteString)
            .accessibilityLabel(L("打开来源：%@", source.title ?? host))
            .accessibilityValue(host)
            .accessibilityIdentifier("vocabulary.detail.sourceLink")
            .contextMenu {
                Button(L("复制来源链接")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        } else if let title = source.title {
            Label {
                Text(title)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "doc.text")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .accessibilityLabel(L("来源文档：%@", title))
            .accessibilityIdentifier("vocabulary.detail.sourceDocument")
        }
    }

    private func activitySection(_ item: LearningVocabularyItem) -> some View {
        let stats = exposure(for: item)
        let dateStyle = Date.FormatStyle(
            date: .abbreviated, time: .shortened, locale: Locale(identifier: L10n.languageCode())
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("出现与查看"))
                .font(Theme.Font.callout.weight(.semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                activityValue("出现记录", stats.map { countText($0.appearanceCount) } ?? L("统计中…"),
                              identifier: "vocabulary.activity.appearances")
                activityValue("最近出现", stats?.lastSeenAt?.formatted(dateStyle)
                    ?? L(stats == nil ? "统计中…" : "无出现记录"),
                              identifier: "vocabulary.activity.lastSeen")
                activityValue("查看次数", countText(item.entry?.viewCount ?? 0),
                              identifier: "vocabulary.activity.views")
                activityValue("最近查看", item.entry?.lastViewedAt?.formatted(dateStyle) ?? L("从未查看"),
                              identifier: "vocabulary.activity.lastViewed")
            }
            Text(L("在翻译历史的原文或译文中匹配到单词时，每条记录计一次。主动选中词条查看详情时计一次查看。"))
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.bgControl.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func activityValue(_ title: String, _ value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(title))
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.Font.callout.weight(.medium).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func countText(_ count: Int) -> String {
        count.formatted(.number.locale(Locale(identifier: L10n.languageCode())))
    }

    private func detailSection(_ title: String, _ text: String, emptyText: String = "", onSpeak: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L(title))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                if let onSpeak {
                    IconButton("speaker.wave.2", help: "朗读句子", size: 11, action: onSpeak)
                }
            }
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

    private var exposureRequest: ExposureRequest {
        ExposureRequest(isOpen: presentation.isOpen, terms: settings.learningVocabularyEntries.map(\.term).sorted())
    }

    private func observeHistory(for request: ExposureRequest) async {
        guard request.isOpen, !request.terms.isEmpty else {
            if request.terms.isEmpty {
                exposureStats = [:]
                measuredTerms = []
            }
            return
        }
        let history = state.history
        let changes = await history.contentUpdates()
        for await _ in changes {
            guard !Task.isCancelled else { return }
            let records = await history.all()
            let scan = Task.detached(priority: .utility) {
                LearningRecommendationEngine.vocabularyExposureStats(records: records, terms: request.terms)
            }
            let stats = await withTaskCancellationHandler {
                await scan.value
            } onCancel: {
                scan.cancel()
            }
            guard !Task.isCancelled, exposureRequest == request else { return }
            exposureStats = stats
            measuredTerms = Set(request.terms.map(LearningRecommendationEngine.key(for:)))
        }
    }

    private func exposure(for item: LearningVocabularyItem) -> LearningVocabularyExposure? {
        let key = LearningRecommendationEngine.key(for: item.expression.term)
        guard measuredTerms.contains(key) else { return nil }
        return exposureStats[key] ?? .unseen
    }

    private func comesBefore(_ lhs: LearningVocabularyItem, _ rhs: LearningVocabularyItem) -> Bool {
        let nameOrder = lhs.expression.term.localizedStandardCompare(rhs.expression.term)
        let order: ComparisonResult
        switch sortField {
        case .name:
            if nameOrder != .orderedSame { return nameOrder == (sortAscending ? .orderedAscending : .orderedDescending) }
            order = .orderedSame
        case .added:
            order = compare(lhs.entry?.savedAt, rhs.entry?.savedAt)
        case .appearances:
            order = compare(exposure(for: lhs)?.appearanceCount, exposure(for: rhs)?.appearanceCount)
        case .lastSeen:
            order = compare(exposure(for: lhs)?.lastSeenAt, exposure(for: rhs)?.lastSeenAt)
        case .views:
            order = compare(lhs.entry?.viewCount, rhs.entry?.viewCount)
        case .lastViewed:
            order = compare(lhs.entry?.lastViewedAt, rhs.entry?.lastViewedAt)
        case .nextReview:
            order = compare(lhs.entry?.nextReviewAt, rhs.entry?.nextReviewAt)
        }
        if order != .orderedSame { return order == .orderedAscending }
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func compare<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        guard let lhs else { return rhs == nil ? .orderedSame : .orderedDescending }
        guard let rhs else { return .orderedAscending }
        guard lhs != rhs else { return .orderedSame }
        return (lhs < rhs) == sortAscending ? .orderedAscending : .orderedDescending
    }

    private var userSelection: Binding<String?> {
        Binding(get: { selectedID }, set: { id in
            if let id { selectWord(id) } else { selectedID = nil }
        })
    }

    private func selectWord(_ id: String) {
        selectedID = id
        guard presentation.isOpen, explicitlyViewedID != id else { return }
        explicitlyViewedID = id
        settings.recordLearningVocabularyView(id)
    }

    private func reconcileSelection() {
        if selectedID == nil || !visibleItems.contains(where: { $0.id == selectedID }) {
            selectedID = visibleItems.first?.id
            explicitlyViewedID = nil
        }
    }

    private func finishSave(_ id: String) {
        scope = .all
        query = ""
        reloadVocabularyItems()
        selectedID = id
        explicitlyViewedID = nil
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
        explicitlyViewedID = nil
    }
}

private struct VocabularyRow: View {
    let item: LearningVocabularyItem
    let exposure: LearningVocabularyExposure?
    let latestDate: Date?
    let latestDateTitle: String

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

            HStack(spacing: 9) {
                let count = exposure.map { String($0.appearanceCount) } ?? "…"
                Label(count, systemImage: "doc.text")
                    .help(L("出现记录"))
                    .accessibilityLabel(L("出现记录：%@", count))
                let views = String(item.entry?.viewCount ?? 0)
                Label(views, systemImage: "eye")
                    .help(L("查看次数"))
                    .accessibilityLabel(L("查看次数：%@", views))
                Spacer(minLength: 0)
                if let latestDate {
                    let date = latestDate.formatted(Date.FormatStyle(
                        date: .numeric, time: .omitted, locale: Locale(identifier: L10n.languageCode())
                    ))
                    Text(date)
                        .lineLimit(1)
                        .help(L(latestDateTitle))
                        .accessibilityLabel("\(L(latestDateTitle)) \(date)")
                }
            }
            .font(Theme.Font.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vocabulary.row.\(item.id)")
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
