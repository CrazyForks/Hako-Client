import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
public struct HakoMacRuleEditorState: Equatable, Sendable {
    public var draft: ConfigurationRuleDraft
    public var localSets: [ConfigurationLocalRuleSet]
    public var resetDocument: String

    public init(draft: ConfigurationRuleDraft, localSets: [ConfigurationLocalRuleSet], resetDocument: String) {
        self.draft = draft
        self.localSets = localSets
        self.resetDocument = resetDocument
    }
}

 
 
public struct HakoMacRuleEditorActions {
     
    public var load: @MainActor () async throws -> HakoMacRuleEditorState
     
     
    public var save: @MainActor (ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft
     
    public var saveLocal: @MainActor (ConfigurationLocalRuleSet) async throws -> HakoMacRuleEditorState
     
    public var deleteLocal: @MainActor (String) async throws -> HakoMacRuleEditorState
     
    public var copy: @MainActor (ConfigurationRuleDraft, String) async throws -> Void
     
    public var download: @MainActor (String) async throws -> [String]

    public init(
        load: @escaping @MainActor () async throws -> HakoMacRuleEditorState,
        save: @escaping @MainActor (ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft,
        saveLocal: @escaping @MainActor (ConfigurationLocalRuleSet) async throws -> HakoMacRuleEditorState,
        deleteLocal: @escaping @MainActor (String) async throws -> HakoMacRuleEditorState,
        copy: @escaping @MainActor (ConfigurationRuleDraft, String) async throws -> Void,
        download: @escaping @MainActor (String) async throws -> [String]
    ) {
        self.load = load
        self.save = save
        self.saveLocal = saveLocal
        self.deleteLocal = deleteLocal
        self.copy = copy
        self.download = download
    }

    public static var unavailable: HakoMacRuleEditorActions {
        HakoMacRuleEditorActions(
            load: { throw ConfigurationLibraryError.unreadable },
            save: { _ in throw ConfigurationLibraryError.unreadable },
            saveLocal: { _ in throw ConfigurationLibraryError.unreadable },
            deleteLocal: { _ in throw ConfigurationLibraryError.unreadable },
            copy: { _, _ in throw ConfigurationLibraryError.unreadable },
            download: { _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
 
 
public enum HakoMacRuleSetKey {
    public static func catalog(_ entry: ConfigurationRuleCatalogEntry) -> String { "catalog-" + entry.id }
    public static func local(_ set: ConfigurationLocalRuleSet) -> String { "local-" + set.id }
}

 
 
 
 
 
 
public struct HakoMacRuleEditorSheet: View {
    private enum Sheet: Identifiable {
        case rule(UUID?)
        case group(UUID?)
        case ruleSet
        case source
        case duplicate
        var id: String {
            switch self {
            case .rule(let id): "rule-\(id?.uuidString ?? "new")"
            case .group(let id): "group-\(id?.uuidString ?? "new")"
            case .ruleSet: "rule-set"
            case .source: "source"
            case .duplicate: "duplicate"
            }
        }
    }

    private let actions: HakoMacRuleEditorActions
    private let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var state: HakoMacRuleEditorState?
    @State private var baseline: ConfigurationRuleDraft?
     
     
    @State private var edited = false
    @State private var loadError: String?
    @State private var error: String?
    @State private var busy = false
    @State private var sheet: Sheet?
    @State private var confirmsDiscard = false
    @State private var confirmsReset = false

    public init(actions: HakoMacRuleEditorActions, saved: @escaping () -> Void = {}) {
        self.actions = actions
        self.saved = saved
    }

    private var dirty: Bool { edited && state != nil && baseline != nil }

    public var body: some View {
        HakoMacSheetFrame(
            title: .verbatim(state?.draft.label ?? ""),
            subtitle: state.map { HakoDisplayText.format("%@ rules", [String($0.draft.rows.count)]) },
            width: 680,
            height: 640
        ) {
            if let state {
                content(state)
            } else if let loadError {
                HakoMacSheetPlaceholder(
                    title: .copy("Rule Library"), message: loadError,
                    retry: { Task { await load() } },
                    retryIdentifier: "configuration-center.rule-editor.retry"
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } leading: {
            Menu {
                Button { sheet = .duplicate } label: { Text(hako: .copy("Duplicate")) }
                Button { sheet = .source } label: { Text(hako: .copy("Edit Rules Source")) }
                Divider()
                Button(role: .destructive) { confirmsReset = true } label: { Text(hako: .copy("Reset")) }
            } label: {
                Text(hako: .copy("Manage"))
            }
            .fixedSize()
            .disabled(busy || state == nil)
            .accessibilityIdentifier("configuration-center.rule-editor.more")
            if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.rule-editor.error")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.cancel",
                primaryTitle: .copy("Save"),
                primaryIdentifier: "configuration-center.rule-editor.save",
                primaryDisabled: !dirty || busy,
                isBusy: busy,
                onClose: { if dirty { confirmsDiscard = true } else { dismiss() } },
                onPrimary: save
            )
        }
        .task { if state == nil { await load() } }
        .sheet(item: $sheet) { item in
            if let state {
                switch item {
                case .rule(let id):
                    HakoMacRuleRowEditor(
                        draft: state.draft, rowID: id,
                        commit: { raw, enabled, note in mutate { draft in
                            if let id {
                                draft.setRule(raw, enabled: enabled, note: note, rowID: id)
                            } else {
                                draft.insertRuleFirst(raw)
                                if let first = draft.rows.first { draft.setRule(raw, enabled: enabled, note: note, rowID: first.id) }
                            }
                        } },
                        close: { sheet = nil }
                    )
                case .group(let id):
                    HakoMacRuleGroupEditor(
                        document: id.flatMap { gid in state.draft.groups.first { $0.id == gid }?.document.serialized() } ?? "",
                        commit: { text in try mutateThrowing { draft in try draft.setGroup(OrderedJSON.parse(text), groupID: id) } },
                        close: { sheet = nil }
                    )
                case .ruleSet:
                    HakoMacLocalRuleSetEditor(
                        download: actions.download,
                        commit: { value in try await runThrowing { let next = try await actions.saveLocal(value); adopt(next, keepDraft: true) } },
                        close: { sheet = nil }
                    )
                case .source:
                    HakoMacRuleSourceEditor(
                        text: (try? state.draft.document().serialized()) ?? state.draft.originalDocument.serialized(),
                        commit: { text in try mutateThrowing { draft in try draft.replaceContents(OrderedJSON.parse(text)) } },
                        close: { sheet = nil }
                    )
                case .duplicate:
                    HakoMacNamePrompt(
                        title: .copy("Duplicate"),
                        initial: HakoCopy.string("My Rules", locale: locale),
                        commit: { name in try await runThrowing { try await actions.copy(state.draft, name); saved(); dismiss() } },
                        close: { sheet = nil }
                    )
                }
            }
        }
        .alert(Text(hako: .copy("Discard Changes")), isPresented: $confirmsDiscard) {
            Button(role: .destructive) { dismiss() } label: { Text(hako: .copy("Discard Changes")) }
            Button(role: .cancel) {} label: { Text(hako: .copy("Cancel")) }
        } message: {
            Text(hako: .copy("This profile has changes that have not been saved."))
        }
        .alert(Text(hako: .copy("Reset")), isPresented: $confirmsReset) {
            Button(role: .destructive) {
                if let state { try? mutateThrowing { draft in try draft.replaceContents(OrderedJSON.parse(state.resetDocument)) } }
            } label: {
                Text(hako: .copy("Reset"))
            }
            Button(role: .cancel) {} label: { Text(hako: .copy("Cancel")) }
        }
    }

     

    private func content(_ state: HakoMacRuleEditorState) -> some View {
        List {
            rulesSection(state.draft)
            groupsSection(state.draft)
            ruleSetsSection(state)
        }
        .listStyle(.inset)
        .hakoFrameWatch("configuration-rule-editor")
        .accessibilityIdentifier("configuration-center.rule-editor")
    }

    private func rulesSection(_ draft: ConfigurationRuleDraft) -> some View {
        Section {
            HakoMacListAddRow(.copy("Add Rule")) { sheet = .rule(nil) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.rule-editor.add-rule")
            ForEach(draft.rows) { row in
                ruleRow(row, draft: draft)
            }
        } header: {
            Text(hako: .copy("Rules"))
        }
    }

    private func ruleRow(_ row: ConfigurationRuleDraft.Row, draft: ConfigurationRuleDraft) -> some View {
        let enabled = draft.isEnabled(row.raw)
        let note = draft.note(for: row.raw)
        return Button {
            sheet = .rule(row.id)
        } label: {
            HStack(spacing: HakoTheme.Spacing.compact) {
                HakoSymbolImage(symbol: enabled ? .checkmarkCircleFill : .circle)
                    .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                    .frame(width: HakoTheme.Control.pointerRowTarget)
                VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                    Text(verbatim: row.raw)
                        .font(.body.monospaced())
                        .foregroundStyle(enabled ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !note.isEmpty {
                        Text(verbatim: note).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: HakoTheme.Spacing.row)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .contextMenu {
            Button { sheet = .rule(row.id) } label: { Text(hako: .copy("Edit")) }
            Button {
                mutate { $0.setRule(row.raw, enabled: !enabled, note: note, rowID: row.id) }
            } label: {
                Text(hako: .copy("Enabled"))
            }
            Divider()
            Button { moveRow(row.id, up: true, in: draft) } label: { Text(hako: .copy("Move Up")) }
                .disabled(draft.rows.first?.id == row.id)
            Button { moveRow(row.id, up: false, in: draft) } label: { Text(hako: .copy("Move Down")) }
                .disabled(draft.rows.last?.id == row.id)
            Divider()
            Button(role: .destructive) { mutate { $0.remove([row.id]) } } label: { Text(hako: .copy("Delete")) }
        }
        .accessibilityIdentifier("configuration-center.rule-editor.rule.\(row.id.uuidString)")
    }

    private func groupsSection(_ draft: ConfigurationRuleDraft) -> some View {
        Section {
            HakoMacListAddRow(.copy("Add Group")) { sheet = .group(nil) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.rule-editor.add-group")
            ForEach(draft.groups) { group in
                Button {
                    sheet = .group(group.id)
                } label: {
                    HStack(spacing: HakoTheme.Spacing.compact) {
                        VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                            Text(verbatim: group.name)
                            Text(verbatim: group.type).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: HakoTheme.Spacing.row)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .contextMenu {
                    Button { sheet = .group(group.id) } label: { Text(hako: .copy("Edit")) }
                    Divider()
                    Button { moveGroup(group.id, up: true, in: draft) } label: { Text(hako: .copy("Move Up")) }
                        .disabled(draft.groups.first?.id == group.id)
                    Button { moveGroup(group.id, up: false, in: draft) } label: { Text(hako: .copy("Move Down")) }
                        .disabled(draft.groups.last?.id == group.id)
                    Divider()
                    Button(role: .destructive) {
                        try? mutateThrowing { try $0.removeGroups([group.id]) }
                    } label: {
                        Text(hako: .copy("Delete"))
                    }
                }
                .accessibilityIdentifier("configuration-center.rule-editor.group.\(group.id.uuidString)")
            }
        } header: {
            Text(hako: .copy("Policy Groups"))
        }
    }

    private func ruleSetsSection(_ state: HakoMacRuleEditorState) -> some View {
        let draft = state.draft
        return Group {
            Section {
                HakoMacListAddRow(.copy("Add Rule Set")) { sheet = .ruleSet }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.rule-editor.add-rule-set")
                ForEach(state.localSets) { set in
                    let key = HakoMacRuleSetKey.local(set)
                    HakoMacChoiceRow(
                        title: .verbatim(set.name),
                        subtitle: .format("%@ rules", [String(set.rules.count)]),
                        style: .multiple,
                        isSelected: draft.containsRuleSet(key),
                        identifier: "configuration-center.rule-editor.local.\(set.id)",
                        toggle: {
                            try? mutateThrowing { value in
                                if value.containsRuleSet(key) { value.removeRuleSet(key) }
                                else { try value.addRuleSet(key: key, name: set.name, rules: set.rules, defaultRoute: "proxy") }
                            }
                        }
                    )
                    .disabled(busy)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await run { let next = try await actions.deleteLocal(set.id); adopt(next, keepDraft: true) } }
                        } label: {
                            Text(hako: .copy("Delete"))
                        }
                    }
                }
            } header: {
                Text(hako: .copy("My Rules"))
            }
            Section {
                ForEach(ConfigurationRuleCatalog.builtIn.entries) { entry in
                    let key = HakoMacRuleSetKey.catalog(entry)
                    HakoMacChoiceRow(
                        title: .verbatim(entry.displayName),
                        subtitle: .verbatim(entry.defaultRoute.rawValue),
                        style: .multiple,
                        isSelected: draft.containsRuleSet(key),
                        identifier: "configuration-center.rule-editor.catalog.\(entry.id)",
                        toggle: { toggleCatalog(entry, key: key, draft: draft) }
                    )
                    .disabled(busy)
                }
            } header: {
                Text(hako: .copy("Rule Sets"))
            }
        }
    }

     

    private func mutate(_ change: (inout ConfigurationRuleDraft) -> Void) {
        guard var current = state else { return }
        change(&current.draft)
        state = current
        edited = true
        error = nil
    }

    private func mutateThrowing(_ change: (inout ConfigurationRuleDraft) throws -> Void) throws {
        guard var current = state else { return }
        do {
            try change(&current.draft)
            state = current
            edited = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    private func moveRow(_ id: UUID, up: Bool, in draft: ConfigurationRuleDraft) {
        guard let index = draft.rows.firstIndex(where: { $0.id == id }) else { return }
        let target: UUID?
        if up {
            guard index > 0 else { return }
            target = draft.rows[index - 1].id
        } else {
            guard index + 1 < draft.rows.count else { return }
            target = index + 2 < draft.rows.count ? draft.rows[index + 2].id : nil
        }
        mutate { $0.move([id], before: target) }
    }

    private func moveGroup(_ id: UUID, up: Bool, in draft: ConfigurationRuleDraft) {
        guard let index = draft.groups.firstIndex(where: { $0.id == id }) else { return }
        let target: UUID?
        if up {
            guard index > 0 else { return }
            target = draft.groups[index - 1].id
        } else {
            guard index + 1 < draft.groups.count else { return }
            target = index + 2 < draft.groups.count ? draft.groups[index + 2].id : nil
        }
        mutate { $0.moveGroups([id], before: target) }
    }

    private func toggleCatalog(_ entry: ConfigurationRuleCatalogEntry, key: String, draft: ConfigurationRuleDraft) {
        if draft.containsRuleSet(key) {
            mutate { $0.removeRuleSet(key) }
            return
        }
        Task {
            await run {
                let rules = try await actions.download(entry.sourceURLString)
                try mutateThrowing { value in
                    try value.addRuleSet(key: key, name: entry.displayName, rules: rules, defaultRoute: entry.defaultRoute.rawValue)
                }
            }
        }
    }

     

    private func load() async {
        loadError = nil
        do {
            let loaded = try await actions.load()
            adopt(loaded, keepDraft: false)
        } catch {
            loadError = error.localizedDescription
        }
    }

     
     
     
    private func adopt(_ next: HakoMacRuleEditorState, keepDraft: Bool) {
        if keepDraft, var current = state {
            current.localSets = next.localSets
            current.resetDocument = next.resetDocument
            state = current
        } else {
            state = next
            baseline = next.draft
            edited = false
        }
    }

    private func save() {
        guard let state, dirty, !busy else { return }
        Task {
            await run {
                let reloaded = try await actions.save(state.draft)
                var current = state
                current.draft = reloaded
                self.state = current
                baseline = reloaded
                edited = false
                saved()
            }
        }
    }

    @discardableResult
    private func run(_ operation: () async throws -> Void) async -> Bool {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await operation()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

     
    private func runThrowing(_ operation: () async throws -> Void) async throws {
        busy = true
        error = nil
        defer { busy = false }
        try await operation()
    }
}

 

 
 
struct HakoMacRuleRowEditor: View {
    let draft: ConfigurationRuleDraft
    let rowID: UUID?
    let commit: (String, Bool, String) -> Void
    let close: () -> Void
    @State private var raw: String
    @State private var enabled: Bool
    @State private var note: String
    @State private var action: HakoStructuredRule.Action = .domainSuffix
    @State private var content = ""
    @State private var target = "DIRECT"

    init(draft: ConfigurationRuleDraft, rowID: UUID?, commit: @escaping (String, Bool, String) -> Void, close: @escaping () -> Void) {
        self.draft = draft
        self.rowID = rowID
        self.commit = commit
        self.close = close
        let row = rowID.flatMap { id in draft.rows.first { $0.id == id } }
        _raw = State(initialValue: row?.raw ?? "")
        _enabled = State(initialValue: row.map { draft.isEnabled($0.raw) } ?? true)
        _note = State(initialValue: row.map { draft.note(for: $0.raw) } ?? "")
    }

    private var targets: [String] {
        var names = draft.groups.map(\.name).filter { !$0.isEmpty }
        for fixed in ["DIRECT", "REJECT"] where !names.contains(fixed) { names.append(fixed) }
        return names
    }

    private var assembled: String {
        var parts = [action.rawValue]
        if action.needsContent { parts.append(content.trimmingCharacters(in: .whitespacesAndNewlines)) }
        parts.append(target)
        return parts.joined(separator: ",")
    }

    private var canSave: Bool { !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HakoMacSheetFrame(
            title: rowID == nil ? .copy("Add Rule") : .copy("Rule"),
            subtitle: .verbatim(raw),
            width: 560,
            height: rowID == nil ? 480 : 340
        ) {
            HakoMacSheetForm {
                if rowID == nil {
                    Section {
                        Picker(selection: $action) {
                            ForEach(HakoStructuredRule.Action.allCases, id: \.self) { item in
                                Text(verbatim: item.rawValue).tag(item)
                            }
                        } label: {
                            Text(hako: .copy("Rule Type"))
                        }
                        .accessibilityIdentifier("configuration-center.rule-editor.rule.action")
                        if action.needsContent {
                            TextField(text: $content, prompt: Text(verbatim: action.contentPlaceholder)) {
                                Text(verbatim: action.contentLabel)
                            }
                            .font(.body.monospaced())
                            .accessibilityIdentifier("configuration-center.rule-editor.rule.content")
                        }
                        Picker(selection: $target) {
                            ForEach(targets, id: \.self) { name in Text(verbatim: name).tag(name) }
                        } label: {
                            Text(hako: .copy("Policy Groups"))
                        }
                        .accessibilityIdentifier("configuration-center.rule-editor.rule.target")
                    }
                    .onChange(of: assembled) { value in raw = value }
                }
                Section {
                    TextField(text: $raw, prompt: Text(verbatim: "DOMAIN-SUFFIX,example.com,DIRECT")) { Text(hako: .copy("Rule")) }
                        .font(.body.monospaced())
                        .accessibilityIdentifier("configuration-center.rule-editor.rule.raw")
                    Toggle(isOn: $enabled) { Text(hako: .copy("Enabled")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.rule.enabled")
                    TextField(text: $note, prompt: Text(hako: .copy("Comment"))) { Text(hako: .copy("Comment")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.rule.comment")
                }
            }
            .accessibilityIdentifier("configuration-center.rule-editor.rule-sheet")
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.rule.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.rule-editor.rule.done",
                primaryDisabled: !canSave,
                onClose: close,
                onPrimary: { commit(raw.trimmingCharacters(in: .whitespacesAndNewlines), enabled, note); close() }
            )
        }
        .onAppear { if rowID == nil { raw = assembled } }
    }
}

 
 
 
struct HakoMacRuleGroupEditor: View {
    let document: String
    let commit: (String) throws -> Void
    let close: () -> Void
    @State private var text: String
    @State private var error: String?

    init(document: String, commit: @escaping (String) throws -> Void, close: @escaping () -> Void) {
        self.document = document
        self.commit = commit
        self.close = close
        _text = State(initialValue: document.isEmpty ? "{\n  \"name\": \"\",\n  \"type\": \"select\",\n  \"proxies\": [\"DIRECT\"]\n}" : document)
    }

    var body: some View {
        HakoMacSheetFrame(
            title: document.isEmpty ? .copy("Add Group") : .copy("Group"),
            subtitle: .copy("Policy Groups"),
            width: 560, height: 440
        ) {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .padding(12)
                .accessibilityIdentifier("configuration-center.rule-editor.group.text")
        } leading: {
            if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.rule-editor.group.error")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.group.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.rule-editor.group.done",
                primaryDisabled: text == document || text.isEmpty,
                onClose: close,
                onPrimary: { do { try commit(text); close() } catch { self.error = error.localizedDescription } }
            )
        }
    }
}

 
struct HakoMacRuleSourceEditor: View {
    let text: String
    let commit: (String) throws -> Void
    let close: () -> Void
    @State private var draft: String
    @State private var error: String?

    init(text: String, commit: @escaping (String) throws -> Void, close: @escaping () -> Void) {
        self.text = text
        self.commit = commit
        self.close = close
        _draft = State(initialValue: text)
    }

    var body: some View {
        HakoMacSheetFrame(title: .copy("Edit Rules Source"), width: 700, height: 580) {
            TextEditor(text: $draft)
                .font(.body.monospaced())
                .padding(12)
                .accessibilityIdentifier("configuration-center.rule-editor.source.text")
        } leading: {
            if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.rule-editor.source.error")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.source.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.rule-editor.source.done",
                primaryDisabled: draft == text,
                onClose: close,
                onPrimary: { do { try commit(draft); close() } catch { self.error = error.localizedDescription } }
            )
        }
    }
}

 
 
struct HakoMacLocalRuleSetEditor: View {
    let download: @MainActor (String) async throws -> [String]
    let commit: (ConfigurationLocalRuleSet) async throws -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var input = ""
    @State private var busy = false
    @State private var error: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    var body: some View {
        HakoMacSheetFrame(title: .copy("Add Rule Set"), subtitle: .copy("My Rules"), width: 560, height: 440) {
            HakoMacSheetForm {
                Section {
                    TextField(text: $name, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.name")
                    TextEditor(text: $input)
                        .font(.body.monospaced())
                        .frame(minHeight: 140)
                        .disabled(busy)
                        .accessibilityLabel(Text(hako: .copy("Rule Set")))
                        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.input")
                }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration-center.rule-editor.rule-set.error")
                    }
                }
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.rule-set.cancel",
                primaryTitle: .copy("Save"),
                primaryIdentifier: "configuration-center.rule-editor.rule-set.save",
                primaryDisabled: !canSave,
                isBusy: busy,
                onClose: close,
                onPrimary: save
            )
        }
    }

    private func save() {
        guard canSave else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                let rules = try await download(trimmed)
                try await commit(ConfigurationLocalRuleSet(name: name.trimmingCharacters(in: .whitespacesAndNewlines), input: trimmed, rules: rules))
                close()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

 
struct HakoMacNamePrompt: View {
    let title: HakoDisplayText
    let initial: String
    let commit: (String) async throws -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @State private var name: String
    @State private var busy = false
    @State private var error: String?

    init(title: HakoDisplayText, initial: String, commit: @escaping (String) async throws -> Void, close: @escaping () -> Void) {
        self.title = title
        self.initial = initial
        self.commit = commit
        self.close = close
        _name = State(initialValue: initial)
    }

    var body: some View {
        HakoMacSheetFrame(title: title, width: 480, height: 230) {
            HakoMacSheetForm {
                Section {
                    TextField(text: $name, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.rule-editor.duplicate.name")
                }
                if let error {
                    Section { Text(verbatim: error).foregroundStyle(.red) }
                }
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.duplicate.cancel",
                primaryTitle: .copy("Save"),
                primaryIdentifier: "configuration-center.rule-editor.duplicate.save",
                primaryDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy,
                isBusy: busy,
                onClose: close,
                onPrimary: {
                    busy = true
                    error = nil
                    Task { @MainActor in
                        defer { busy = false }
                        do { try await commit(name.trimmingCharacters(in: .whitespacesAndNewlines)); close() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            )
        }
    }
}
