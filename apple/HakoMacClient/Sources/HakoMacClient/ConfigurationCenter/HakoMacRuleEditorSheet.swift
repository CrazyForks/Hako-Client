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
     
     
     
     
     
     
    public var candidates: (@MainActor () async throws -> ConfigurationRuleTargetCandidates)? = nil
     
     
     
    public var geoValues: HakoMacGeoValueLoader? = nil
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
        case ruleSet(String?)
        case duplicate
        var id: String {
            switch self {
            case .rule(let id): "rule-\(id?.uuidString ?? "new")"
            case .group(let id): "group-\(id?.uuidString ?? "new")"
            case .ruleSet(let id): "rule-set-\(id ?? "new")"
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
    @State private var nodeCandidates = ConfigurationRuleTargetCandidates(sections: [])
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
        .task {
            if let candidates = actions.candidates, let loaded = try? await candidates() {
                nodeCandidates = ConfigurationRuleTargetCandidates(sections: loaded.sections.filter { $0.kind == .source })
            }
        }
        .sheet(item: $sheet) { item in
            Group {
            if let state {
                switch item {
                case .rule(let id):
                    HakoMacRuleRowEditor(
                        draft: state.draft, rowID: id,
                        nodeCandidates: nodeCandidates,
                        createGroup: { document in try mutateThrowing { draft in try draft.setGroup(document, groupID: nil) } },
                        geoValues: actions.geoValues,
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
                        all: state.draft.groups, nodeCandidates: nodeCandidates,
                        commit: { document in try mutateThrowing { draft in try draft.setGroup(document, groupID: id) } },
                        close: { sheet = nil }
                    )
                case .ruleSet(let id):
                    let value = id.flatMap { setID in state.localSets.first { $0.id == setID } }
                    HakoMacLocalRuleSetEditor(
                        value: value,
                        policy: value.flatMap { state.draft.ruleSetPolicy(HakoMacRuleSetKey.local($0)) }
                            ?? state.draft.groups.first?.name ?? "DIRECT",
                        candidates: Self.policyCandidates(groups: state.draft.groups, nodes: nodeCandidates),
                        geoValues: actions.geoValues,
                        download: actions.download,
                        save: { set, policy in
                             
                             
                             
                             
                             
                            try await runThrowing {
                                let next = try await actions.saveLocal(set)
                                adopt(next, keepDraft: true)
                                try mutateThrowing { draft in
                                    try draft.attachRuleSet(
                                        key: HakoMacRuleSetKey.local(set), name: set.name, rules: set.rules, policy: policy
                                    )
                                }
                            }
                        },
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
                     
                     
                    .moveDisabled(row.isFinal)
            }
             
             
            .onMove { offsets, destination in
                mutate { $0.moveRows(fromOffsets: offsets, toOffset: destination) }
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
             
             
             
             
            Button { mutate { $0.moveRow(row.id, offset: -1) } } label: { Text(hako: .copy("Move Up")) }
                .disabled(row.isFinal || draft.rows.first?.id == row.id)
            Button { mutate { $0.moveRow(row.id, offset: 1) } } label: { Text(hako: .copy("Move Down")) }
                 
                 
                 
                 
                .disabled(row.isFinal || Self.isRowAboveFinal(row, in: draft))
            Divider()
            Button(role: .destructive) { mutate { $0.remove([row.id]) } } label: { Text(hako: .copy("Delete")) }
        }
        .accessibilityIdentifier("configuration-center.rule-editor.rule.\(row.id.uuidString)")
    }

     
     
    static let groupIconSize: CGFloat = 22

    private func groupsSection(_ draft: ConfigurationRuleDraft) -> some View {
        Section {
            HakoMacListAddRow(.copy("Add Group")) { sheet = .group(nil) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.rule-editor.add-group")
            ForEach(draft.groups) { group in
                HStack(spacing: HakoTheme.Spacing.compact) {
                     
                     
                     
                     
                    HakoTowerGroupIconView(icon: HakoTowerGroupIcon.read(group.document), size: Self.groupIconSize) { EmptyView() }
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
                HakoMacListAddRow(.copy("Add Rule Set")) { sheet = .ruleSet(nil) }
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
                         
                        Button { sheet = .ruleSet(set.id) } label: { Text(hako: .copy("Edit")) }
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

     
     
     
     
     
    static func groupName(in document: OrderedJSON) -> String? {
        guard case let .string(name)? = document.topLevelValue("name"), !name.isEmpty else { return nil }
        return name
    }

    static func policyCandidates(
        groups: [ConfigurationRuleDraft.Group], nodes: ConfigurationRuleTargetCandidates
    ) -> ConfigurationRuleTargetCandidates {
        let named = ConfigurationRuleTargetCandidates.make(groups: groups.map(\.name), sources: [])
        return ConfigurationRuleTargetCandidates(sections: named.sections + nodes.sections.filter { $0.kind == .source })
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

     
     
     
     
    static func isRowAboveFinal(_ row: ConfigurationRuleDraft.Row, in draft: ConfigurationRuleDraft) -> Bool {
        let rows = draft.rows
        guard rows.count >= 2, rows[rows.count - 1].isFinal else { return false }
        return rows[rows.count - 2].id == row.id
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
             
             
             
             
            let rebased = current.draft.rebased(onto: next.draft)
            current.draft = rebased.draft
            current.localSets = next.localSets
            current.resetDocument = next.resetDocument
            state = current
            baseline = next.draft
            installedRuleSets = Self.installedRuleSets(in: rebased.draft)
            if !rebased.droppedRuleSets.isEmpty {
                let names = rebased.droppedRuleSets.map { key in
                    next.localSets.first { "local-" + $0.id == key }?.name ?? key
                }
                error = HakoCopy.format("Rules on removed rule sets were left out: %@", locale: locale, names.joined(separator: ", "))
            }
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
                 
                 
                 
                 
                dismiss()
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
     
     
     
    let nodeCandidates: ConfigurationRuleTargetCandidates
    let rowID: UUID?
     
     
     
     
     
    let createGroup: ((OrderedJSON) throws -> Void)?
     
     
     
    let geoValues: HakoMacGeoValueLoader?
    let commit: (String, Bool, String) -> Void
    let close: () -> Void
    @State private var raw: String
    @State private var enabled: Bool
    @State private var note: String
    @State private var action: HakoStructuredRule.Action
    @State private var content: String
    @State private var target: String
     
     
     
    @State private var src: Bool
    @State private var noResolve: Bool
    @State private var additionalParams: [String]
     
     
     
    @State private var structured: Bool
    @State private var pickingTarget = false
    @State private var addingGroup = false
    @State private var pickingGeo = false
    @State private var pickedFrom: HakoMacGeoResource?

    init(draft: ConfigurationRuleDraft, rowID: UUID?,
         nodeCandidates: ConfigurationRuleTargetCandidates = .init(sections: []),
         createGroup: ((OrderedJSON) throws -> Void)? = nil,
         geoValues: HakoMacGeoValueLoader? = nil,
         commit: @escaping (String, Bool, String) -> Void, close: @escaping () -> Void) {
        self.draft = draft
        self.nodeCandidates = nodeCandidates
        self.rowID = rowID
        self.createGroup = createGroup
        self.geoValues = geoValues
        self.commit = commit
        self.close = close
        let row = rowID.flatMap { id in draft.rows.first { $0.id == id } }
        _raw = State(initialValue: row?.raw ?? "")
        _enabled = State(initialValue: row.map { draft.isEnabled($0.raw) } ?? true)
        _note = State(initialValue: row.map { draft.note(for: $0.raw) } ?? "")
        let parsed = row.flatMap { HakoStructuredRule.parse($0.raw) }
        _action = State(initialValue: parsed?.action ?? .domainSuffix)
        _content = State(initialValue: parsed?.content ?? "")
        _target = State(initialValue: parsed?.target ?? "DIRECT")
        _src = State(initialValue: parsed?.src ?? false)
        _noResolve = State(initialValue: parsed?.noResolve ?? false)
        _additionalParams = State(initialValue: parsed?.additionalParams ?? [])
        _structured = State(initialValue: row == nil || parsed != nil)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var candidates: ConfigurationRuleTargetCandidates {
        HakoMacRuleEditorSheet.policyCandidates(groups: draft.groups, nodes: nodeCandidates)
    }

    private var assembled: String {
        HakoStructuredRule(
            action: action,
            content: action.needsContent ? content.trimmingCharacters(in: .whitespaces) : "",
            target: target,
            noResolve: noResolve,
            src: src,
            additionalParams: additionalParams
        ).rawValue
    }

    private var canSave: Bool { !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HakoMacSheetFrame(
            title: rowID == nil ? .copy("Add Rule") : .copy("Rule"),
            subtitle: .verbatim(raw),
            width: 560,
            height: pickingGeo ? 520 : (structured ? 480 : 340)
        ) {
            if pickingGeo, let resource = action.hakoMacGeoResource, let geoValues {
                HakoMacGeoValuePickerPage(
                    resource: resource, current: content, load: geoValues,
                    identifier: "configuration-center.rule-editor.rule.geo"
                ) { picked in
                    content = picked
                    pickedFrom = resource
                    pickingGeo = false
                }
            } else if pickingTarget {
                HakoMacTargetPickerPage(
                    candidates: candidates, current: target,
                    identifier: "configuration-center.rule-editor.rule.target",
                     
                     
                     
                    addGroup: createGroup == nil ? nil : { addingGroup = true }
                ) { picked in
                    target = picked
                    pickingTarget = false
                }
            } else {
            HakoMacSheetForm {
                if structured {
                    Section {
                        Picker(selection: $action) {
                            ForEach(HakoStructuredRule.Action.allCases, id: \.self) { item in
                                Text(verbatim: item.rawValue).tag(item)
                            }
                        } label: {
                            Text(hako: .copy("Rule Type"))
                        }
                        .accessibilityIdentifier("configuration-center.rule-editor.rule.action")
                        if let resource = action.hakoMacGeoResource, geoValues != nil {
                            HakoMacGeoValueRow(
                                resource: resource, value: content,
                                identifier: "configuration-center.rule-editor.rule.geo"
                            ) { pickingGeo = true }
                        } else if action.needsContent {
                             
                             
                            LabeledContent {
                                TextField(text: $content, prompt: Text(verbatim: action.contentPlaceholder)) { Text(hako: .copy(action.contentLabel)) }
                                    .labelsHidden()
                                    .font(.body.monospaced())
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("configuration-center.rule-editor.rule.content")
                            } label: {
                                 
                                 
                                 
                                 
                                Text(hako: .copy(action.contentLabel))
                            }
                        }
                        HakoMacTargetRow(title: .copy("Target"), value: target, identifier: "configuration-center.rule-editor.rule.target") {
                            pickingTarget = true
                        }
                    }
                    .onChange(of: action) { changed in
                         
                         
                         
                        if pickedFrom != nil, changed.hakoMacGeoResource != pickedFrom { content = ""; pickedFrom = nil }
                    }
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
            }
        } leading: {
            if pickingGeo {
                Button { pickingGeo = false } label: { Text(hako: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule.geo.back")
            } else if pickingTarget {
                Button { pickingTarget = false } label: { Text(hako: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule.target.back")
            }
        } trailing: {
            if !pickingGeo {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.rule-editor.rule.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.rule-editor.rule.done",
                primaryDisabled: !canSave,
                onClose: close,
                onPrimary: { commit(raw.trimmingCharacters(in: .whitespacesAndNewlines), enabled, note); close() }
            )
            }
        }
         
         
         
        .onAppear { if rowID == nil { raw = assembled } }
         
         
         
         
        .onChange(of: assembled) { value in if structured { raw = value } }
         
         
         
        .sheet(isPresented: $addingGroup) {
            HakoMacRuleGroupEditor(
                group: nil, all: draft.groups, nodeCandidates: nodeCandidates,
                commit: { document in
                    try createGroup?(document)
                    if let name = HakoMacRuleEditorSheet.groupName(in: document) {
                        target = name
                        pickingTarget = false
                    }
                },
                close: { addingGroup = false }
            )
        }
    }
}

 
 
 
 
 
 
 
 
 
 
struct HakoMacRuleGroupEditor: View {
    let group: ConfigurationRuleDraft.Group?
    let all: [ConfigurationRuleDraft.Group]
     
     
    let nodeCandidates: ConfigurationRuleTargetCandidates
    let commit: (OrderedJSON) throws -> Void
    let close: () -> Void
    @State private var pickingNode = false
    @State private var name: String
    @State private var icon: String
    @State private var kind: String
    @State private var selected: [String]
    @State private var includeAll: Bool
    @State private var filter: String
    @State private var error: String?

    init(group: ConfigurationRuleDraft.Group?, all: [ConfigurationRuleDraft.Group], nodeCandidates: ConfigurationRuleTargetCandidates = .init(sections: []),
         commit: @escaping (OrderedJSON) throws -> Void, close: @escaping () -> Void) {
        self.group = group
        self.nodeCandidates = nodeCandidates
        self.all = all
        self.commit = commit
        self.close = close
        let seed = Self.fields(of: group)
        _name = State(initialValue: seed.name)
        _icon = State(initialValue: seed.icon)
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
         
        var icon = ""
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
        fields.icon = HakoTowerGroupIcon.read(group.document)
        return fields
    }

     
     
     
    static func document(base: OrderedJSON?, fields: Fields) -> OrderedJSON {
        var document = (base ?? .object([])).settingTopLevel("name", to: .string(fields.name))
         
        document = HakoTowerGroupIcon.apply(fields.icon, to: document)
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

    private var fields: Fields { Fields(name: name, kind: kind, selected: selected, includeAll: includeAll, filter: filter, icon: icon) }
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
            if pickingNode {
                HakoMacTargetPickerPage(candidates: nodeCandidates, current: "", identifier: "configuration-center.rule-editor.group.add-node") { picked in
                    if !selected.contains(picked) { selected.append(picked) }
                    pickingNode = false
                }
            } else {
            HakoMacSheetForm {
                 
                Section {
                    TextField(text: $name, prompt: Text(hako: .copy("e.g. 🎬 Netflix"))) { Text(hako: .copy("Group Name")) }
                        .accessibilityIdentifier("configuration-center.rule-editor.group.name")
                    TextField(text: $icon, prompt: Text(verbatim: "https://…")) { Text(hako: .copy("Icon URL")) }
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("configuration-center.rule-editor.group.icon")
                     
                     
                     
                    if let echo = HakoTowerGroupIconEcho.of(icon) {
                        HStack {
                            Text(hako: .copy(echo.label))
                                .foregroundStyle(echo == .nothingDraws ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            Spacer(minLength: HakoTheme.Spacing.compact)
                            switch echo {
                            case .emoji(let emoji): Text(verbatim: emoji).foregroundStyle(.secondary)
                            case .symbol(let symbol): Image(systemName: symbol.rawValue).foregroundStyle(.secondary)
                            case .image(let host): Text(verbatim: host).foregroundStyle(.secondary)
                            case .nothingDraws: EmptyView()
                            }
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("configuration-center.rule-editor.group.icon.echo")
                    }
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
                    if !nodeCandidates.sections.isEmpty {
                         
                         
                        HakoMacTargetRow(title: .copy("Add Node"), value: "", identifier: "configuration-center.rule-editor.group.add-node") {
                            pickingNode = true
                        }
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
            }
        } leading: {
            if pickingNode {
                Button { pickingNode = false } label: { Text(hako: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.group.add-node.back")
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
     
     
     
    enum Kind: Hashable { case link, manual }

     
     
     
    struct Line: Identifiable, Equatable {
        let id = UUID()
        var raw: String
         
         
         
         
         
         
         
        var action: HakoStructuredRule.Action? {
            let head = raw.split(separator: ",", maxSplits: 1).first ?? ""
            return HakoStructuredRule.Action(
                rawValue: head.trimmingCharacters(in: .whitespaces).uppercased()
            )
        }
        var value: String {
            let parts = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count > 1 ? String(parts[1]) : ""
        }
    }

    let value: ConfigurationLocalRuleSet?
    let candidates: ConfigurationRuleTargetCandidates
    let geoValues: HakoMacGeoValueLoader?
    let download: @MainActor (String) async throws -> [String]
     
    let save: (ConfigurationLocalRuleSet, String) async throws -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @State private var name: String
    @State private var link: String
    @State private var lines: [Line]
    @State private var kind: Kind
    @State private var policy: String
    @State private var pickingPolicy = false
     
     
    @State private var addingLine = false
     
     
     
     
     
     
     
     
    static let lineActions: [HakoStructuredRule.Action] =
        HakoStructuredRule.Action.allCases.filter { $0.category != .logic }

    @State private var lineAction: HakoStructuredRule.Action = .domainSuffix
    @State private var lineContent = ""
    @State private var pickingGeo = false
    @State private var pickedFrom: HakoMacGeoResource?
    @State private var busy = false
    @State private var error: String?

    init(
        value: ConfigurationLocalRuleSet?, policy: String, candidates: ConfigurationRuleTargetCandidates,
        geoValues: HakoMacGeoValueLoader? = nil,
        download: @escaping @MainActor (String) async throws -> [String],
        save: @escaping (ConfigurationLocalRuleSet, String) async throws -> Void,
        close: @escaping () -> Void
    ) {
        self.value = value
        self.candidates = candidates
        self.geoValues = geoValues
        self.download = download
        self.save = save
        self.close = close
        let input = value?.input ?? ""
        let isLink = Self.looksLikeLink(input)
        _name = State(initialValue: value?.name ?? "")
        _link = State(initialValue: isLink ? input : "")
        _lines = State(initialValue: isLink ? [] : Self.lines(from: input))
        _kind = State(initialValue: isLink ? .link : .manual)
        _policy = State(initialValue: policy)
    }

     
    static func looksLikeLink(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.contains("\n") && (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
    }

     
     
    static func lines(from input: String) -> [Line] {
        input.split(separator: "\n", omittingEmptySubsequences: true)
            .map { Line(raw: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.raw.isEmpty }
    }

    private var input: String {
        kind == .link ? link.trimmingCharacters(in: .whitespacesAndNewlines) : lines.map(\.raw).joined(separator: "\n")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !policy.isEmpty && !busy && !pickingPolicy && !addingLine
            && (kind == .link ? Self.looksLikeLink(link) : !lines.isEmpty)
    }

     
    private var assembledLine: String {
        var parts = [lineAction.rawValue]
        if lineAction.needsContent { parts.append(lineContent.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return parts.joined(separator: ",")
    }

    private var canAddLine: Bool {
        !lineAction.needsContent || !lineContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var title: HakoDisplayText {
        if pickingGeo, let resource = lineAction.hakoMacGeoResource { return resource.rowTitle }
        if addingLine { return .copy("Add Rule") }
        if pickingPolicy { return .copy("Select Policy") }
        return .copy(value == nil ? "New Rule Set" : "Edit Rule Set")
    }

    var body: some View {
        HakoMacSheetFrame(
            title: title, subtitle: (pickingPolicy || addingLine) ? nil : .copy("My Rules"),
            width: 560, height: 520
        ) {
            if pickingGeo, let resource = lineAction.hakoMacGeoResource, let geoValues {
                HakoMacGeoValuePickerPage(
                    resource: resource, current: lineContent, load: geoValues,
                    identifier: "configuration-center.rule-editor.rule-set.geo"
                ) { picked in
                    lineContent = picked
                    pickedFrom = resource
                    pickingGeo = false
                }
            } else if addingLine {
                lineForm
            } else if pickingPolicy {
                HakoMacTargetPickerPage(
                    candidates: candidates, current: policy,
                    identifier: "configuration-center.rule-editor.rule-set.policy"
                ) { picked in
                    policy = picked
                    pickingPolicy = false
                }
            } else {
                form
            }
        } leading: {
            if pickingGeo {
                Button { pickingGeo = false } label: { Text(hako: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.geo.back")
            } else if addingLine {
                Button { addingLine = false } label: { Text(hako: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.back")
            } else if pickingPolicy {
                Button { pickingPolicy = false } label: { Text(hako: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.policy.back")
            }
        } trailing: {
            if addingLine, !pickingGeo {
                HakoMacSheetButtons(
                    closeIdentifier: "configuration-center.rule-editor.rule-set.line.cancel",
                    primaryTitle: .copy("Add"),
                    primaryIdentifier: "configuration-center.rule-editor.rule-set.line.add",
                    primaryDisabled: !canAddLine,
                    onClose: { addingLine = false },
                    onPrimary: addLine
                )
            } else if !pickingPolicy, !pickingGeo {
                HakoMacSheetButtons(
                    closeIdentifier: "configuration-center.rule-editor.rule-set.cancel",
                    primaryTitle: .copy("Save"),
                    primaryIdentifier: "configuration-center.rule-editor.rule-set.save",
                    primaryDisabled: !canSave,
                    isBusy: busy,
                    onClose: close,
                    onPrimary: commit
                )
            }
        }
        .onChange(of: lineAction) { changed in
             
             
            if changed.hakoMacGeoResource != pickedFrom { lineContent = ""; pickedFrom = nil }
        }
    }

    private var form: some View {
        HakoMacSheetForm {
            Section {
                TextField(text: $name, prompt: Text(hako: .copy("e.g. 🎬 Netflix"))) { Text(hako: .copy("Name")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.name")
            }
            Section {
                Picker(selection: $kind) {
                    Text(hako: .copy("Link")).tag(Kind.link)
                    Text(hako: .copy("Manual")).tag(Kind.manual)
                } label: {
                    Text(hako: .copy("Rules From"))
                }
                .pickerStyle(.segmented)
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.rule-editor.rule-set.kind")
                if kind == .link {
                    TextField(text: $link, prompt: Text(verbatim: "https://")) { Text(hako: .copy("Link")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.input")
                } else {
                     
                     
                     
                    ForEach(lines) { line in
                        HakoMacRuleSetLineRow(line: line)
                            .disabled(busy)
                            .contextMenu {
                                Button(role: .destructive) {
                                    lines.removeAll { $0.id == line.id }
                                } label: {
                                    Text(hako: .copy("Delete"))
                                }
                            }
                    }
                    .onDelete { offsets in lines.remove(atOffsets: offsets) }
                    HakoMacListAddRow(.copy("Add Rule")) {
                        lineAction = .domainSuffix
                        lineContent = ""
                        pickedFrom = nil
                        addingLine = true
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.open")
                }
            } footer: {
                Text(hako: .copy(kind == .link
                    ? "A text, YAML or MRS rule set the app downloads and keeps updated."
                    : "Add the rules this set matches. The policy is chosen below, not written on each rule."))
            }
            Section {
                HakoMacTargetRow(
                    title: .copy("Policy"), value: policy,
                    identifier: "configuration-center.rule-editor.rule-set.policy.row"
                ) { pickingPolicy = true }
                .disabled(busy)
            } footer: {
                Text(hako: .copy("Traffic matching these rules goes to this policy. Saving adds the rule set to the current rules."))
            }
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.error")
                }
            }
        }
    }

     
     
     
    private var lineForm: some View {
        HakoMacSheetForm {
            Section {
                Picker(selection: $lineAction) {
                    ForEach(Self.lineActions, id: \.self) { item in
                        Text(verbatim: item.rawValue).tag(item)
                    }
                } label: {
                    Text(hako: .copy("Rule Type"))
                }
                .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.action")
                if let resource = lineAction.hakoMacGeoResource, geoValues != nil {
                    HakoMacGeoValueRow(
                        resource: resource, value: lineContent,
                        identifier: "configuration-center.rule-editor.rule-set.line.geo"
                    ) { pickingGeo = true }
                } else if lineAction.needsContent {
                    LabeledContent {
                        TextField(text: $lineContent, prompt: Text(verbatim: lineAction.contentPlaceholder)) {
                            Text(hako: .copy(lineAction.contentLabel))
                        }
                        .labelsHidden()
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.content")
                    } label: {
                        Text(hako: .copy(lineAction.contentLabel))
                    }
                }
                LabeledContent {
                    Text(verbatim: assembledLine).font(.body.monospaced())
                } label: {
                    Text(hako: .copy("Rule"))
                }
            }
        }
    }

    private func addLine() {
        guard canAddLine else { return }
        lines.append(Line(raw: assembledLine))
        addingLine = false
    }

    private func commit() {
        guard canSave else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let trimmed = input
                let rules = try await download(trimmed)
                let set = ConfigurationLocalRuleSet(
                    id: value?.id ?? UUID().uuidString.lowercased(),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines), input: trimmed, rules: rules
                )
                try await save(set, policy)
                close()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

 
 
struct HakoMacRuleSetLineRow: View {
    let line: HakoMacLocalRuleSetEditor.Line

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            if let action = line.action {
                Text(verbatim: action.rawValue)
                Spacer()
                if !line.value.isEmpty {
                    Text(verbatim: line.value)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                 
                Text(verbatim: line.raw)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("configuration-center.rule-editor.rule-set.line.\(line.raw)")
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
