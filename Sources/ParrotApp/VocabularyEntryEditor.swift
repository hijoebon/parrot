import SwiftUI

/// Shared by the translation popover and the wordbook, so saving and editing
/// always expose the same small, editable form.
struct VocabularyEntryEditor: View {
    let title: String
    let onCancel: () -> Void
    let onSave: (String, String, String, LearningVocabularySource?) -> String?
    let lookup: ((String) async -> String?)?

    @Environment(\.dismiss) private var dismiss
    @State private var term: String
    @State private var meaning: String
    @State private var sourceSentence: String
    @State private var sourceTitle: String
    @State private var sourceLink: String
    @State private var isEditingSource = false
    @State private var hasInvalidSourceLink = false
    @State private var errorMessage: String?
    @State private var lookupFailed = false
    @State private var isLookingUp = false
    @State private var lookupTask: Task<Void, Never>?
    @State private var lookupGeneration = UUID()
    @State private var generatedMeaning: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case term, meaning, source, sourceTitle, sourceLink
    }

    init(
        title: String,
        term: String,
        meaning: String,
        sourceSentence: String,
        source: LearningVocabularySource? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, String, LearningVocabularySource?) -> String?,
        lookup: ((String) async -> String?)? = nil,
        clearInitialMeaningOnTermChange: Bool = false
    ) {
        self.title = title
        self.onCancel = onCancel
        self.onSave = onSave
        self.lookup = lookup
        _term = State(initialValue: term)
        _meaning = State(initialValue: meaning)
        _sourceSentence = State(initialValue: sourceSentence)
        _sourceTitle = State(initialValue: source?.title ?? "")
        _sourceLink = State(initialValue: source?.url?.absoluteString ?? "")
        _generatedMeaning = State(initialValue: clearInitialMeaningOnTermChange && !meaning.isEmpty ? meaning : nil)
    }

    private var canSave: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L(title))
                .font(.system(size: 18, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 14) {
                fieldLabel("单词或短语")
                TextField(L("例如：take a break"), text: $term, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .term)
                    .accessibilityLabel(L("单词或短语"))
                    .accessibilityIdentifier("vocabulary.term")

                HStack {
                    fieldLabel("释义", optional: true)
                    Spacer()
                    if lookup != nil, meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if isLookingUp {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.65)
                            Text(L("正在获取…"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Button(L(lookupFailed ? "重试" : "获取释义"), action: beginLookup)
                                .buttonStyle(.link)
                                .font(.system(size: 11))
                                .disabled(!canSave)
                        }
                    }
                }
                TextField(L("记下你想保留的意思"), text: $meaning, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focusedField, equals: .meaning)
                    .accessibilityLabel(L("释义"))
                    .accessibilityIdentifier("vocabulary.meaning")

                if lookupFailed {
                    Text(L("未能获取释义，可手动填写。"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                fieldLabel("原句", optional: true)
                TextField(L("保留语境，方便以后回想"), text: $sourceSentence, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .source)
                    .accessibilityLabel(L("原句"))
                    .accessibilityIdentifier("vocabulary.source")

                sourceFields
            }
            .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("vocabulary.error")
            }

            HStack(spacing: 10) {
                Spacer()
                Button(L("取消")) {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(L("保存"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("vocabulary.save")
            }
        }
        .padding(22)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            focusedField = .term
            if meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { beginLookup() }
        }
        .onDisappear { cancelLookup() }
        .onChange(of: term) { _ in
            errorMessage = nil
            lookupFailed = false
            cancelLookup()
            if let generatedMeaning, meaning == generatedMeaning {
                meaning = ""
            }
            generatedMeaning = nil
        }
        .onChange(of: meaning) { _ in
            if let generatedMeaning, meaning != generatedMeaning {
                self.generatedMeaning = nil
            }
            if !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lookupFailed = false
            }
        }
    }

    private var sourceFields: some View {
        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = sourceLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = title.isEmpty ? (URL(string: address)?.host ?? address) : title
        return VStack(alignment: .leading, spacing: 9) {
            Button {
                isEditingSource.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: summary.isEmpty ? "plus.circle" : (address.isEmpty ? "doc.text" : "link"))
                    Text(summary.isEmpty ? L(isEditingSource ? "来源" : "添加来源") : summary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: isEditingSource ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(summary.isEmpty && !isEditingSource ? L("添加来源") : L("编辑来源"))
            .accessibilityValue([summary, L(isEditingSource ? "已展开" : "已折叠")]
                .filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityIdentifier("vocabulary.provenance.edit")

            if isEditingSource {
                VStack(alignment: .leading, spacing: 7) {
                    TextField(L("网页标题或文档名"), text: $sourceTitle)
                        .focused($focusedField, equals: .sourceTitle)
                        .accessibilityLabel(L("网页标题或文档名"))
                        .accessibilityIdentifier("vocabulary.provenance.title")

                    TextField(L("网页链接（https://…）"), text: $sourceLink)
                        .focused($focusedField, equals: .sourceLink)
                        .accessibilityLabel(L("网页链接"))
                        .accessibilityIdentifier("vocabulary.provenance.url")
                        .onChange(of: sourceLink) { _ in hasInvalidSourceLink = false }

                    if hasInvalidSourceLink {
                        Text(L("请输入以 https:// 或 http:// 开头的有效网页链接。"))
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("vocabulary.provenance.error")
                    }

                    if !title.isEmpty || !address.isEmpty {
                        Button(L("清除来源")) {
                            sourceTitle = ""
                            sourceLink = ""
                            hasInvalidSourceLink = false
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .accessibilityIdentifier("vocabulary.provenance.clear")
                    }
                }
            }
        }
    }

    private func fieldLabel(_ text: String, optional: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(L(text))
                .font(.system(size: 12, weight: .medium))
            if optional {
                Text(L("选填"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.bottom, -8)
    }

    private func save() {
        guard canSave else { return }
        let address = sourceLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = LearningVocabularySource(title: sourceTitle, url: URL(string: address))
        if !address.isEmpty, source?.url == nil {
            hasInvalidSourceLink = true
            isEditingSource = true
            focusedField = .sourceLink
            return
        }
        if onSave(term, meaning, sourceSentence, source) != nil {
            dismiss()
        } else {
            errorMessage = L("未能保存，请检查单词后重试。")
        }
    }

    private func cancelLookup() {
        lookupTask?.cancel()
        lookupTask = nil
        lookupGeneration = UUID()
        isLookingUp = false
    }

    private func beginLookup() {
        guard let lookup, canSave,
              meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        cancelLookup()
        lookupFailed = false
        isLookingUp = true
        let requestedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = lookupGeneration
        lookupTask = Task { @MainActor in
            let result = await lookup(requestedTerm)
            guard !Task.isCancelled, lookupGeneration == generation else { return }
            isLookingUp = false
            lookupTask = nil
            guard term.trimmingCharacters(in: .whitespacesAndNewlines) == requestedTerm,
                  meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if let result = result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty {
                generatedMeaning = result
                meaning = result
            } else {
                lookupFailed = true
            }
        }
    }
}
