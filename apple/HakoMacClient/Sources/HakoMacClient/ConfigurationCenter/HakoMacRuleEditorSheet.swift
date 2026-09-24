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
     
     
     
    public var documentText: (@Sendable (String) throws -> String)? = nil
    public var documentFromText: (@Sendable (String) throws -> String)? = nil

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
        case duplicate
        var id: String {
            switch self {
            case .rule(let id): "rule-\(id?.uuidString ?? "new")"
            case .group(let id): "group-\(id?.uuidString ?? "new")"
            case .ruleSet: "rule-set"
            case .duplicate: "duplicate"
            }
        }
    }

     
     
    public enum Pane: String, CaseIterable, Identifiable {
        case rules, groups, ruleSets, source
        public var id: String { rawValue }
        var title: HakoDisplayText {
            switch self {
            case .rules: .copy("Rules")
            case .groups: .copy("Policy Groups")
            case .ruleSets: .copy("Rule Sets")
            case .source: .copy("Source")
            }
        }
    }

    private let actions: HakoMacRuleEditorActions
    private let saved: () -> Void
     
     
     
     
    @State private var dismiss = HakoDismissHandle()
    @Environment(\.locale) private var locale
    @State private var state: HakoMacRuleEditorState?
    @State private var baseline: ConfigurationRuleDraft?
     
     
    @State private var edited = false
     
     
     
    @State private var installedRuleSets: Set<String> = []
    @State private var loadError: String?
    @State private var error: String?
    @State private var busy = false
    @State private var sheet: Sheet?
    @State private var confirmsDiscard = false
    @State private var confirmsReset = false
    @State private var pane: Pane = .rules
    @State private var sourceText = ""
     
    @State private var shownSourceText = ""

    public init(actions: HakoMacRuleEditorActions, initialPane: Pane = .rules, saved: @escaping () -> Void = {}) {
        self.actions = actions
        self.saved = saved
        _pane = State(initialValue: initialPane)
    }

    private var dirty: Bool { edited && state != nil && baseline != nil }

    public var body: some View {
        HakoMacSheetFrame(
            title: .verbatim(state?.draft.label ?? ""),
            subtitle: state.map { HakoDisplayText.count($0.draft.rows.count, one: "%@ rule", other: "%@ rules") },
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
             
             
            Button { sheet = .duplicate } label: { Text(hako: .copy("Copy Rule Scheme")) }
                .disabled(busy || state == nil)
                .accessibilityIdentifier("configuration-center.rule-editor.save-as")
            if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.rule-editor.error")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.cancel",
                 
                primaryTitle: .copy("OK"),
                primaryIdentifier: "configuration-center.rule-editor.save",
                primaryDisabled: !dirty || busy,
                isBusy: busy,
                onClose: { if dirty { confirmsDiscard = true } else { dismiss() } },
                onPrimary: save
            )
        }
        .task { if state == nil { await load() } }
        .sheet(item: $sheet) { item in
            Group {
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
                        group: id.flatMap { gid in state.draft.groups.first { $0.id == gid } },
                        all: state.draft.groups,
                        commit: { document in try mutateThrowing { draft in try draft.setGroup(document, groupID: id) } },
                        close: { sheet = nil }
                    )
                case .ruleSet:
                    HakoMacLocalRuleSetEditor(
                        download: actions.download,
                        commit: { value in try await runThrowing { let next = try await actions.saveLocal(value); adopt(next, keepDraft: true) } },
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
            .hakoModalPresentation(.fitted)
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
        .hakoCapturesDismiss(dismiss)
    }

     

    private func content(_ state: HakoMacRuleEditorState) -> some View {
        HStack(spacing: 0) {
            List(selection: $pane) {
                ForEach(Pane.allCases) { item in
                    Text(hako: item.title).tag(item)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 150)
            .accessibilityIdentifier("configuration-center.rule-editor.pane")
            Divider()
            Group {
                switch pane {
                case .rules: List { rulesSection(state.draft) }.listStyle(.inset)
                case .groups: List { groupsSection(state.draft) }.listStyle(.inset)
                case .ruleSets: List { ruleSetsSection(state) }.listStyle(.inset)
                case .source: sourcePane(state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .hakoFrameWatch("configuration-rule-editor")
        .accessibilityIdentifier("configuration-center.rule-editor")
    }

     
     
     
    private func sourcePane(_ state: HakoMacRuleEditorState) -> some View {
        let currentJSON = Self.sourceText(state)
        return VStack(spacing: 0) {
            TextEditor(text: $sourceText)
                .font(.body.monospaced())
                .padding(12)
                .accessibilityIdentifier("configuration-center.rule-editor.source.text")
            Divider()
            HStack {
                Button(role: .destructive) { confirmsReset = true } label: { Text(hako: .copy("Reset")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.source.reset")
                Spacer()
                Button { applySourceText() } label: { Text(hako: .copy("Done")) }
                    .disabled(busy || sourceText == shownSourceText)
                    .accessibilityIdentifier("configuration-center.rule-editor.source.done")
            }
            .padding(10)
        }
        .task(id: currentJSON) {
             
            let convert = actions.documentText
            let text = await Task.detached { (try? convert?(currentJSON)) ?? currentJSON }.value
            shownSourceText = text
            sourceText = text
        }
    }

     
     
     
    private func applySourceText() {
        let text = sourceText
        let convert = actions.documentFromText
        busy = true
        Task {
            defer { busy = false }
            do {
                let root = try await Task.detached { try OrderedJSON.parse(try convert?(text) ?? text) }.value
                if case .object(let entries) = root,
                   entries.contains(where: { !ConfigurationRuleDocument.keys.contains($0.key) }) {
                    throw HakoMacRuleSourceError.foreignKeys
                }
                try mutateThrowing { draft in try draft.replaceContents(root) }
            } catch HakoMacRuleSourceError.foreignKeys {
                error = HakoCopy.string("Only rules and policy groups belong here. Add nodes in Node Library.", locale: locale)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private static func sourceText(_ state: HakoMacRuleEditorState) -> String {
        (try? state.draft.document().serialized()) ?? state.draft.originalDocument.serialized()
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
        return HStack(spacing: HakoTheme.Spacing.compact) {
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
        .hakoMacPressableRow { sheet = .rule(row.id) }
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
                HStack(spacing: HakoTheme.Spacing.compact) {
                    VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                        Text(verbatim: group.name)
                        Text(verbatim: group.type).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: HakoTheme.Spacing.row)
                }
                .hakoMacPressableRow { sheet = .group(group.id) }
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
                        subtitle: .count(set.rules.count, one: "%@ rule", other: "%@ rules"),
                        style: .multiple,
                        isSelected: installedRuleSets.contains(key),
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
                        isSelected: installedRuleSets.contains(key),
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

     

     
     
     
    nonisolated static func installedRuleSets(in draft: ConfigurationRuleDraft) -> Set<String> {
        var keys = Set<String>()
        for row in draft.rows where row.raw.hasPrefix("RULE-SET,") {
            let parts = row.raw.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 { keys.insert(String(parts[1])) }
        }
        return keys
    }

    private func mutate(_ change: (inout ConfigurationRuleDraft) -> Void) {
        guard var current = state else { return }
        change(&current.draft)
        state = current
        installedRuleSets = Self.installedRuleSets(in: current.draft)
        edited = true
        error = nil
    }

    private func mutateThrowing(_ change: (inout ConfigurationRuleDraft) throws -> Void) throws {
        guard var current = state else { return }
        do {
            try change(&current.draft)
            state = current
            installedRuleSets = Self.installedRuleSets(in: current.draft)
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
            installedRuleSets = Self.installedRuleSets(in: next.draft)
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
                installedRuleSets = Self.installedRuleSets(in: reloaded)
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
    let group: ConfigurationRuleDraft.Group?
    let all: [ConfigurationRuleDraft.Group]
    let commit: (OrderedJSON) throws -> Void
    let close: () -> Void
    @State private var name: String
    @State private var kind: String
    @State private var selected: [String]
    @State private var includeAll: Bool
    @State private var filter: String
    @State private var error: String?

    init(group: ConfigurationRuleDraft.Group?, all: [ConfigurationRuleDraft.Group], commit: @escaping (OrderedJSON) throws -> Void, close: @escaping () -> Void) {
        self.group = group
        self.all = all
        self.commit = commit
        self.close = close
        let seed = Self.fields(of: group)
        _name = State(initialValue: seed.name)
        _kind = State(initialValue: seed.kind)
        _selected = State(initialValue: seed.selected)
        _includeAll = State(initialValue: seed.includeAll)
        _filter = State(initialValue: seed.filter)
    }

    struct Fields: Equatable {
        var name = ""
        var kind = "select"
        var selected: [String] = []
        var includeAll = false
        var filter = ""
    }

     
    static func fields(of group: ConfigurationRuleDraft.Group?) -> Fields {
        guard let group else { return Fields() }
        var fields = Fields(name: group.name, kind: group.type)
        if case .array(let values) = group.document.topLevelValue("proxies") {
            fields.selected = values.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
        fields.includeAll = group.document.topLevelValue("include-all") == .scalar("true")
            || group.document.topLevelValue("include-all-proxies") == .scalar("true")
        if case .string(let value) = group.document.topLevelValue("filter") { fields.filter = value }
        return fields
    }

     
     
     
    static func document(base: OrderedJSON?, fields: Fields) -> OrderedJSON {
        var document = (base ?? .object([])).settingTopLevel("name", to: .string(fields.name))
        let previousType: String? = { if case .string(let value) = base?.topLevelValue("type") { return value }; return nil }()
        if fields.kind != previousType, case .object(let entries) = document {
            let typeFields: Set<String> = ["url", "interval", "tolerance", "strategy", "lazy", "expected-status", "max-failed-times"]
            document = .object(entries.filter { !typeFields.contains($0.key) })
        }
        document = document.settingTopLevel("type", to: .string(fields.kind))
            .settingTopLevel("proxies", to: .array(fields.selected.map(OrderedJSON.string)))
            .settingTopLevel("include-all", to: .scalar(fields.includeAll ? "true" : "false"))
            .settingTopLevel("include-all-proxies", to: .scalar("false"))
            .settingTopLevel("filter", to: .string(fields.filter))
        if fields.kind == "url-test" || fields.kind == "fallback" {
            if document.topLevelValue("url") == nil { document = document.settingTopLevel("url", to: .string("https://www.gstatic.com/generate_204")) }
            if document.topLevelValue("interval") == nil { document = document.settingTopLevel("interval", to: .scalar("300")) }
        }
        return document
    }

    private var fields: Fields { Fields(name: name, kind: kind, selected: selected, includeAll: includeAll, filter: filter) }
    private var dirty: Bool { fields != Self.fields(of: group) }
    private var canCommit: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!selected.isEmpty || includeAll) }
    private var kinds: [String] { Array(Set([group?.type ?? "select", "select", "url-test", "fallback"])).sorted() }
    private var options: [String] {
        var seen = Set<String>()
        return (["DIRECT", "REJECT"] + all.filter { $0.id != group?.id }.map(\.name) + selected).filter { seen.insert($0).inserted }
    }
    private var available: [String] {
        let chosen = Set(selected)
        return options.filter { !chosen.contains($0) }
    }

    var body: some View {
        HakoMacSheetFrame(
            title: group == nil ? .copy("Add Group") : .copy("Group"),
            subtitle: .copy("Policy Groups"),
            width: 560, height: 640
        ) {
            HakoMacSheetForm {
                 
                Section {
                    TextField(text: $name, prompt: Text(hako: .copy("e.g. 🎬 Netflix"))) { Text(hako: .copy("Group Name")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.name")
                    Picker(selection: $kind) {
                        ForEach(kinds, id: \.self) { Text(verbatim: $0).tag($0) }
                    } label: {
                        Text(hako: .copy("Group Type"))
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("configuration-center.rule-editor.group.type")
                } footer: {
                    Text(hako: .copy("Changing the group type changes how routes are chosen."))
                }
                Section {
                    if selected.isEmpty {
                        Text(hako: .copy("None")).foregroundStyle(.secondary)
                    }
                    ForEach(Array(selected.enumerated()), id: \.element) { index, item in
                        HStack(spacing: HakoTheme.Spacing.compact) {
                            Text(verbatim: item)
                            Spacer()
                            Button { move(item, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                                .accessibilityLabel(Text(hako: .copy("Move Up")))
                                .accessibilityIdentifier("configuration-center.rule-editor.group.up")
                            Button { move(item, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == selected.count - 1)
                                .accessibilityLabel(Text(hako: .copy("Move Down")))
                                .accessibilityIdentifier("configuration-center.rule-editor.group.down")
                            Button { selected.removeAll { $0 == item } } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel(Text(hako: .copy("Delete")))
                                .accessibilityIdentifier("configuration-center.rule-editor.group.remove")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text(hako: .copy("Selected (in priority order)"))
                }
                Section {
                    if available.isEmpty {
                        Text(hako: .copy("None")).foregroundStyle(.secondary)
                    }
                    ForEach(available, id: \.self) { item in
                        Button { selected.append(item) } label: {
                            HStack {
                                Text(verbatim: item).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("configuration-center.rule-editor.group.add-policy")
                    }
                } header: {
                    Text(hako: .copy("Available"))
                }
                Section {
                    Toggle(isOn: $includeAll) { Text(hako: .copy("Include all proxies")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.include-all")
                    TextField(text: $filter, prompt: Text(verbatim: "(HK|SG)")) { Text(hako: .copy("Include filter")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.filter")
                } header: {
                    Text(hako: .copy("Node Name Match"))
                }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration-center.rule-editor.group.error")
                    }
                }
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.group.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.rule-editor.group.done",
                primaryDisabled: !canCommit || !dirty,
                onClose: close,
                onPrimary: {
                    do {
                        try commit(Self.document(base: group?.document, fields: fields))
                        close()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            )
        }
    }

    private func move(_ item: String, by offset: Int) {
        guard let index = selected.firstIndex(of: item) else { return }
        let target = index + offset
        guard selected.indices.contains(target) else { return }
        selected.swapAt(index, target)
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

private enum HakoMacRuleSourceError: Error { case foreignKeys }
