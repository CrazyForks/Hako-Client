import SwiftUI
import HakoClientKit

 
 
 
 
 
enum HakoTowerRulesErrorText {
    static func describe(_ error: Error) -> String {
        let sentence = error.localizedDescription
        guard let library = error as? ConfigurationLibraryError, library == .invalidIdentifier,
              let note = ConfigurationLibraryDiagnostics.lastIdentifierNote else { return sentence }
        return sentence + " [" + note + "]"
    }
}

public struct HakoTowerRulesLibraryView: View {
    public let palette: HakoProductPalette
    public let library: ConfigurationLibrarySnapshot
    public let busy: Bool
    public let error: String?
    public let open: (String) -> Void
    public let refresh: (String) -> Void
    public let delete: (String) -> Void
    public let add: () -> Void
    public let close: () -> Void
    public let showsClose: Bool
    public var collections: [ConfigurationCollectionEntry] = []
    public var openCollection: (ConfigurationCollectionEntry) -> Void = { _ in }
    public let updateAll: (() -> Void)?
    public let updateProgress: String?
    public let updateStatus: String?
    @State private var deleting: ConfigurationRuleScheme?
    @Environment(\.locale) private var locale

    public init(library: ConfigurationLibrarySnapshot, palette: HakoProductPalette, busy: Bool, error: String?,
        open: @escaping (String) -> Void, refresh: @escaping (String) -> Void,
        delete: @escaping (String) -> Void, add: @escaping () -> Void, close: @escaping () -> Void, showsClose: Bool,
        collections: [ConfigurationCollectionEntry] = [], openCollection: @escaping (ConfigurationCollectionEntry) -> Void = { _ in },
        updateAll: (() -> Void)? = nil, updateProgress: String? = nil, updateStatus: String? = nil) {
        self.updateAll = updateAll; self.updateProgress = updateProgress; self.updateStatus = updateStatus
        self.collections = collections; self.openCollection = openCollection
        self.palette = palette
        self.library = library; self.busy = busy; self.error = error
        self.open = open; self.refresh = refresh; self.delete = delete; self.add = add
        self.close = close; self.showsClose = showsClose
    }
    private var schemes: [ConfigurationRuleScheme] {
        library.visibleRuleSchemes
    }
    private func record(_ scheme: ConfigurationRuleScheme) -> ConfigurationSourceRecord? {
         
         
        if ConfigurationBuiltins.isNative(scheme.id) {
            return ConfigurationBuiltins.records.first { $0.id == scheme.sourceID }
        }
        return library.sources.first { $0.id == scheme.sourceID } ?? ConfigurationBuiltins.records.first { $0.id == scheme.sourceID }
    }
    private func displayLabel(_ scheme: ConfigurationRuleScheme) -> String {
        let id = scheme.id
        if id == ConfigurationBuiltins.basicRuleID { return HakoCopy.string("Default Configuration", locale: locale) }
        if id == ConfigurationBuiltins.lazyRuleID { return HakoCopy.string("Lazy Configuration", locale: locale) }
        if scheme.baseSchemeID.map(ConfigurationBuiltins.isNative) == true {
            return scheme.label + " · " + HakoCopy.string("Custom", locale: locale)
        }
        return scheme.label
    }
    private func bundled(_ scheme: ConfigurationRuleScheme) -> Bool { scheme.kind == .builtin }
    public var body: some View {
         
         
         
        let schemes = self.schemes
        return HakoConfigurationLibraryList(palette: palette, accessibilityIdentifier: "configuration.library.rules.content") {
            if updateAll == nil, let error { Text(verbatim: error).foregroundStyle(.orange) }
            ForEach(HakoConfigurationRuleLibrarySection.allCases, id: \.self) { group in
                let items = schemes.filter { group.contains($0, library: library) }
                let entries = collections.filter { entry in
                    guard entry.id.kind == .rules, entry.source.isRetainedSnapshot != true else { return false }
                    if let owner = schemes.first(where: { $0.sourceID == entry.source.id && $0.collectionKey == nil }) {
                        return group.contains(owner, library: library)
                    }
                    return group.contains(entry.source)
                }
                if !items.isEmpty || !entries.isEmpty {
                    section(group.title, items: items, entries: entries)
                }
            }
            if let updateAll {
                Section {
                    HakoConfigurationUpdateButton(title: "Update All Rule Sets", isUpdating: busy, disabled: false, action: updateAll)
                        .accessibilityIdentifier("configuration.library.rules.update-all")
                } footer: {
                    HakoConfigurationUpdateStatus(progress: updateProgress, status: updateStatus, error: error)
                }
            }
            HakoConfigurationLibraryAddCard(kind: .rules, palette: palette, nativeList: true,
                disabled: busy, action: add)
                .accessibilityIdentifier("configuration.library.rules.add-card")
        }
        .allowsHitTesting(!busy)
        .overlay {
            if busy && schemes.isEmpty { ProgressView().allowsHitTesting(false) }
        }
        .hakoPageTitle("Profile Center")
        .hakoToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) { if showsClose { HakoSheetCloseButton(dismiss: close) } }
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button(action: add) {
                        Image(systemName: HakoSymbol.plusCircle.rawValue).hakoToolbarGlyph()
                    }
                    .disabled(busy)
                    .accessibilityLabel(HakoCopy.key(HakoConfigurationAddition.rules.entryTitle))
                    .accessibilityIdentifier("configuration.library.rules.add")
                }.hakoReaderControlGroupStyle()
            }
        }
        .hakoRegistersDeparture(isDirty: false, isBusy: busy, save: { $0(false) }, discard: {})
        .hakoDeleteConfirmation(deleting.map(displayLabel) ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            actionTitle: .copy("Delete Rule Scheme"),
            message: .copy("Saved profiles keep their current rules and stop following this scheme."),
            identifier: "configuration.rules.library.delete.confirm") { [deleting] in
                if let deleting { delete(deleting.id) }
            }
    }
    @ViewBuilder
    private func section(_ title: String, items: [ConfigurationRuleScheme], entries: [ConfigurationCollectionEntry]) -> some View {
         
        let roots = items.filter { scheme in
            !entries.contains { $0.source.id == scheme.sourceID && $0.collection.name == scheme.collectionKey }
        }
        let rootSources = Set(roots.map(\.sourceID))
        let collectionSources = library.availableSources.filter { source in
            !rootSources.contains(source.id) && entries.contains { $0.source.id == source.id }
        }
        HakoConfigurationLibraryCard(title: .copy(title), count: roots.count + collectionSources.count, palette: palette, nativeList: true) {
            ForEach(roots) { scheme in
                Button { open(scheme.id) } label: {
                    HakoConfigurationLibraryRow(title: displayLabel(scheme),
                        count: HakoConfigurationSourceCopy.ruleSummary(record(scheme), locale: locale))
                }.buttonStyle(.plain)
                    .padding(.vertical, HakoMacSettingsMetrics.rowVerticalInset(touch: HakoTheme.Spacing.row))
                    .contextMenu {
                        Button("View Details") { open(scheme.id) }
                        if case .subscription = record(scheme)?.origin { Button("Refresh Rules") { refresh(scheme.id) } }
                        if !bundled(scheme) { Button("Delete", role: .destructive) { deleting = scheme } }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        if !bundled(scheme) {
                            Button("Delete", role: .destructive) { deleting = scheme }
                                 
                                 
                                .tint(.red)
                                .accessibilityIdentifier("configuration.rules.library.delete")
                        }
                    }
                let children = entries.filter { $0.source.id == scheme.sourceID }
                if !children.isEmpty {
                    collectionDisclosure(children, sourceID: scheme.sourceID)
                }
            }
             
            ForEach(collectionSources) { source in
                collectionDisclosure(entries.filter { $0.source.id == source.id }, sourceID: source.id, title: source.label)
            }
        }
    }

    private func collectionDisclosure(_ entries: [ConfigurationCollectionEntry], sourceID: String, title: String? = nil) -> some View {
        DisclosureGroup {
            ForEach(entries) { entry in
                Button { openCollection(entry) } label: {
                    HakoConfigurationLibraryRow(title: entry.collection.name,
                        count: HakoConfigurationCollectionCopy.summary(entry))
                }.buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("configuration.collection.\(entry.source.id).\(entry.id.kind.rawValue).\(entry.collection.name)")
            }
        } label: {
            VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                if let title { Text(verbatim: title).foregroundStyle(.primary) }
                Text(hako: .format("Rule Sets (%@)", [String(entries.count)]))
                    .font(title == nil ? .subheadline : .caption).foregroundStyle(.secondary)
            }
        }
        .hakoRowDisclosure()
        .padding(.vertical, title == nil ? 8 : HakoTheme.Spacing.row)
        .accessibilityIdentifier("configuration.rules.collections.\(sourceID)")
    }

}

 
 
 
 
public struct HakoTowerRuleEditing: Equatable, Sendable {
    public let raw: String
    public let isEnabled: Bool
    public let note: String
    public init(raw: String, isEnabled: Bool, note: String) { self.raw = raw; self.isEnabled = isEnabled; self.note = note }
}

 
 
 
 
 
 
public struct HakoTowerRuleEditorRequest {
    public let editing: HakoTowerRuleEditing?
    public let draft: ConfigurationRuleDraft
    public let options: HakoRulePolicyOptions
    public let showsTarget: Bool
    public let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    public init(editing: HakoTowerRuleEditing?, draft: ConfigurationRuleDraft, options: HakoRulePolicyOptions,
        showsTarget: Bool, createGroup: ((@escaping (String?) -> Void) -> AnyView)?) {
        self.editing = editing; self.draft = draft; self.options = options; self.showsTarget = showsTarget; self.createGroup = createGroup
    }
}

public struct HakoTowerRuleCustomizationView: View {
    @State private var draft: ConfigurationRuleDraft
    @State private var baseline: ConfigurationRuleDraft
    @State private var hasUnsavedChanges = false
    @State private var installedRuleSets: Set<String>
    @State private var baselineRuleSets: Set<String>
    @State private var localSets: [ConfigurationLocalRuleSet]
    @State private var search = ""
    @State private var category: ConfigurationRuleCatalogCategory?
    @State private var reordering = false
     
     
    @State private var loadingRuleSets: Set<String> = []
    @State private var busy = false
    @State private var error: String?
    @State private var modal: Modal?
    @State private var confirmsReset = false
    @State private var deletingLocal: ConfigurationLocalRuleSet?
    @State private var deletingGroup: UUID?
    @State private var confirmsLeave = false
    private let pushed: Bool
    @AppStorage("hako.configuration.ruleGroupEmoji") private var emojis = true
    private let save: (ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft
    private let download: (String) async throws -> [String]
    private let saveLocal: (ConfigurationLocalRuleSet) async throws -> (ConfigurationRuleDraft, [ConfigurationLocalRuleSet])
    private let deleteLocal: (String) async throws -> (ConfigurationRuleDraft, [ConfigurationLocalRuleSet])
    private let copy: (ConfigurationRuleDraft, String) async throws -> Void
    private let resetDocument: String
    private let palette: HakoProductPalette
    private let close: () -> Void
    private let manualEditor: (ConfigurationRuleDraft, @escaping (ConfigurationRuleDraft) async throws -> Void) -> AnyView
     
     
     
     
     
     
    private let ruleEditor: (HakoTowerRuleEditorRequest, @escaping (String, Bool, String) -> Void) -> AnyView
     
     
    private let nodeCandidates: (() async -> [ConfigurationRuleTargetCandidates.Section])?
    @State private var nodeSections: [ConfigurationRuleTargetCandidates.Section] = []
    private enum Modal: String, Identifiable { case identity, group, local, copy, manual, rule; var id: String { rawValue } }
    @State private var groupID: UUID?
    @State private var localID: String?
     
    @State private var ruleID: UUID?
    @State private var ordered = HakoOrderedWork()
    @Environment(\.hakoInsideProductModalPresentation) private var insideProductModal
    public init(draft: ConfigurationRuleDraft, localSets: [ConfigurationLocalRuleSet], resetDocument: String, palette: HakoProductPalette, pushed: Bool = false, ruleSetKeys: Set<String> = [],
        save: @escaping (ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft, download: @escaping (String) async throws -> [String],
        saveLocal: @escaping (ConfigurationLocalRuleSet) async throws -> (ConfigurationRuleDraft, [ConfigurationLocalRuleSet]), deleteLocal: @escaping (String) async throws -> (ConfigurationRuleDraft, [ConfigurationLocalRuleSet]),
        copy: @escaping (ConfigurationRuleDraft, String) async throws -> Void, close: @escaping () -> Void,
        manualEditor: @escaping (ConfigurationRuleDraft, @escaping (ConfigurationRuleDraft) async throws -> Void) -> AnyView,
        ruleEditor: @escaping (HakoTowerRuleEditorRequest, @escaping (String, Bool, String) -> Void) -> AnyView,
        nodeCandidates: (() async -> [ConfigurationRuleTargetCandidates.Section])? = nil) {
        self.nodeCandidates = nodeCandidates
        self.ruleEditor = ruleEditor
        _draft = State(initialValue: draft); _baseline = State(initialValue: draft); _installedRuleSets = State(initialValue: ruleSetKeys); _baselineRuleSets = State(initialValue: ruleSetKeys); _localSets = State(initialValue: localSets)
        self.palette = palette
        self.pushed = pushed
        self.resetDocument = resetDocument; self.save = save; self.download = download; self.saveLocal = saveLocal
        self.deleteLocal = deleteLocal; self.copy = copy; self.close = close; self.manualEditor = manualEditor
    }
     
     
     
     
     
     
     
    private var policyOptions: HakoRulePolicyOptions {
        let document = draft.currentDocument()
        var seen = Set<String>()
        var nodes: [HakoRulePolicySnapshot] = []
        if case .array(let entries) = document.topLevelValue("proxies") {
            for entry in entries {
                guard case .string(let name) = entry.topLevelValue("name"), !name.isEmpty, seen.insert(name).inserted else { continue }
                var type = ""
                if case .string(let value) = entry.topLevelValue("type") { type = value }
                nodes.append(HakoRulePolicySnapshot(name: name, type: type))
            }
        }
        for section in nodeSections {
            for name in section.names where seen.insert(name).inserted {
                nodes.append(HakoRulePolicySnapshot(name: name, type: section.sourceLabel ?? ""))
            }
        }
        var ruleSets: [String] = []
        if case .object(let fields) = document.topLevelValue("rule-providers") { ruleSets = fields.map(\.key).sorted() }
        var subRules: [String]?
        if case .object(let fields) = document.topLevelValue("sub-rules") { subRules = fields.map(\.key).sorted() }
        return HakoRulePolicyOptions(
            groups: draft.groups.map { HakoRulePolicySnapshot(name: $0.name, type: $0.type) },
            proxies: nodes, ruleSets: ruleSets, subRuleNames: subRules)
    }
     
     
     
     
    private func groupCreator(_ done: @escaping (String?) -> Void) -> AnyView {
        AnyView(HakoTowerGroupEditor(group: HakoTowerGroupEditor.blankGroup, all: draft.groups, identityOnly: false, nodeSections: nodeSections, save: { value in
            try await apply { snapshot in var changed = snapshot; try changed.setGroup(value, groupID: nil); return changed }
            var name = ""
            if case .string(let value) = value.topLevelValue("name") { name = value }
            done(name.isEmpty ? nil : name)
        }, close: { done(nil) }))
    }
    private var visibleGroups: [ConfigurationRuleDraft.Group] { draft.groups.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) } }
    private var entries: [ConfigurationRuleCatalogEntry] { ConfigurationRuleCatalog.builtIn.entries.filter { (category == nil || $0.category == category) && $0.matches(search) } }
    public var body: some View {
        List {
            if let error { Text(verbatim: error).foregroundStyle(.orange) }
             
             
             
             
            HakoTowerInlineRules(rows: draft.rows, version: draft.version,
                query: search, palette: palette, remove: { draft.remove([$0]) },
                move: { offsets, destination in
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { draft.moveRows(fromOffsets: offsets, toOffset: destination) }
                    hasUnsavedChanges = true
                },
                ruleSetNames: ruleSetNames, addRule: { ruleID = nil; modal = .rule }, edit: { ruleID = $0; modal = .rule })
            Section {
                ForEach(visibleGroups) { group in
                    Button { groupID = group.id; modal = .group } label: {
                        HStack(spacing: 10) {
                            if emojis {
                                HakoTowerGroupIconView(icon: HakoTowerGroupIcon.read(group.document), size: HakoTheme.Layout.proxyGroupIconSize) {
                                    if let symbol = emoji(group.name) { Text(verbatim: symbol).font(.title3) }
                                    else { Image(systemName: "rectangle.3.group").font(.body).foregroundStyle(.secondary) }
                                }.frame(width: 28, height: 28)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                                    .accessibilityIdentifier("configuration.rules.group.row.icon")
                            }
                            Text(verbatim: displayName(group.name)).foregroundStyle(Color.primary)
                                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                            Spacer(minLength: 12)
                            Text(verbatim: summary(group)).font(.subheadline).foregroundStyle(Color.secondary)
                                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 140, alignment: .trailing)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.frame(minHeight: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .moveDisabled(!search.isEmpty)
                        .contextMenu {
                            Button("修改名称与图标") { groupID = group.id; modal = .identity }
                            Button("Delete", role: .destructive) { deletingGroup = group.id }
                        }
                        .accessibilityAction(named: Text("修改名称与图标")) { groupID = group.id; modal = .identity }
                }.onDelete { offsets in
                    guard let index = offsets.first, visibleGroups.indices.contains(index) else { return }
                    deletingGroup = visibleGroups[index].id
                }.onMove { offsets, destination in
                    var ids = draft.groups.map(\.id); ids.move(fromOffsets: offsets, toOffset: destination)
                    var changed = draft
                    changed.reorderGroups(ids)
                    draft = changed; hasUnsavedChanges = true
                }
                 
                 
                 
                if search.isEmpty {
                    HakoAddRow(Text(hako: .copy("Add Policy Group"))) { groupID = nil; modal = .group }
                        .accessibilityIdentifier("configuration.rules.group.add")
                }
            } header: { HStack { Text("Policy Groups"); Spacer(); Text(hako: .format("%@ groups", [String(visibleGroups.count)])) } }
            if reordering {
                localRuleSetsSection
                Section {
                    ForEach(entries) { entry in
                        Button { toggleCatalog(entry) } label: {
                            HStack(spacing: 12) {
                                Text(entry.emoji).font(.title3).frame(width: 36, height: 36).background(.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) { Text(verbatim: entry.name).font(.body).foregroundStyle(.primary); Text(verbatim: entry.provider.displayName + " · " + route(entry.defaultRoute)).font(.caption).foregroundStyle(.secondary) }
                                Spacer(minLength: 8)
                                mark(installedRuleSets.contains("catalog-" + entry.id),
                                     loading: loadingRuleSets.contains("catalog-" + entry.id))
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    if entries.isEmpty { Text("No results").foregroundStyle(.secondary) }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Online Rule Library")
                        Text("\(entries.count)").monospacedDigit()
                        Spacer()
                        Picker("Category", selection: $category) {
                            Text("All").tag(Optional<ConfigurationRuleCatalogCategory>.none)
                            ForEach(ConfigurationRuleCatalogCategory.allCases, id: \.self) { item in
                                Text(verbatim: item.displayName).tag(Optional(item))
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().textCase(nil).accessibilityIdentifier("configuration.rules.category")
                    }
                }
            }
            if insideProductModal {
                 
                 
                Section("More") {
                    Toggle("显示策略组图标", isOn: $emojis).accessibilityIdentifier("configuration.rules.emojis")
                    Button("Edit Rules Source") { modal = .manual }
                    Button("Save as New Scheme") { modal = .copy }
                    Button("Restore Initial Rules", role: .destructive) { confirmsReset = true }
                }.disabled(busy)
            }
        }
        .modifier(HakoTowerReorderMode(active: reordering))
        .modifier(HakoTowerSelectionFeedback(trigger: installedRuleSets))
        .modifier(HakoTowerSearchPlacement(text: $search, palette: palette))
        .hakoPageTitle("Rule Customization")
         
         
         
        .hakoProductModalRoot(
            title: "Rule Customization",
            actionTitle: reordering ? "结束编辑" : "编辑",
            actionDisabled: busy,
            action: {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { reordering.toggle() }
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal, !pushed {
                HakoModalActionBar(primaryTitle: "Done", primaryDisabled: busy, isBusy: busy,
                    onPrimary: { if hasUnsavedChanges { persist(draft, then: close) } else { close() } })
            }
        }
        .hakoToolbarUnlessInPanel {
            ToolbarItem(placement: pushed ? .primaryAction : .cancellationAction) {
                Menu {
                    Toggle("显示策略组图标", isOn: $emojis).accessibilityIdentifier("configuration.rules.emojis")
                    Button("Edit Rules Source") { modal = .manual }
                    Button("Save as New Scheme") { modal = .copy }
                    Divider()
                    Button("Restore Initial Rules", role: .destructive) { confirmsReset = true }
                } label: { Label("More", systemImage: "ellipsis").foregroundStyle(.tint) }.disabled(busy)
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Button {
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { reordering.toggle() }
                } label: { HakoActionProgressLabel(.copy(reordering ? "结束编辑" : "编辑"), isBusy: busy && pushed) }.foregroundStyle(.tint).disabled(busy)
                if !pushed {
                    Button { if hasUnsavedChanges { persist(draft, then: close) } else { close() } } label: { HakoActionProgressLabel(.copy("Done"), isBusy: busy) }.foregroundStyle(.tint).disabled(busy)
                }
            }
        }
        .hakoBackButtonHidden(pushed && (hasUnsavedChanges || busy))
        .hakoToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                if pushed && (hasUnsavedChanges || busy) {
                    Button("Back") { confirmsLeave = true }
                        .accessibilityLabel("Back").disabled(busy)
                }
            }
        }
        .hakoUnsavedChangesAlert(isPresented: $confirmsLeave,
            message: .copy("This profile has changes that have not been saved."), isBusy: busy,
            save: { persist(draft, then: close) },
            discard: { draft = baseline; installedRuleSets = baselineRuleSets; hasUnsavedChanges = false; close() })
        .hakoRegistersDeparture(isDirty: hasUnsavedChanges, isBusy: busy, save: { completion in persist(draft, completion: completion) }, discard: { draft = baseline; installedRuleSets = baselineRuleSets; hasUnsavedChanges = false })
        .task { if let nodeCandidates, nodeSections.isEmpty { nodeSections = await nodeCandidates() } }
        .hakoProductModal(item: $modal, role: .form) { kind in
            HakoSingleColumnNavigationContainer {
                switch kind {
                case .identity, .group:
                    if let id = groupID, let group = draft.groups.first(where: { $0.id == id }) {
                        HakoTowerGroupEditor(group: group, all: draft.groups, identityOnly: kind == .identity, nodeSections: nodeSections, save: { value in
                            let snapshot = draft
                            let changed = try await Task.detached { var valueDraft = snapshot; try valueDraft.setGroup(value, groupID: id); return valueDraft }.value
                            let saved = try await save(changed); await receiveSaved(saved); modal = nil
                        }, close: { modal = nil })
                    } else if kind == .group {
                         
                        HakoTowerGroupEditor(group: HakoTowerGroupEditor.blankGroup, all: draft.groups, identityOnly: false, nodeSections: nodeSections, save: { value in
                            let snapshot = draft
                            let changed = try await Task.detached { var valueDraft = snapshot; try valueDraft.setGroup(value, groupID: nil); return valueDraft }.value
                            let saved = try await save(changed); await receiveSaved(saved); modal = nil
                        }, close: { modal = nil })
                    }
                case .local:
                    HakoTowerLocalRuleEditor(
                        value: localSets.first { $0.id == localID },
                        policy: localID.flatMap { draft.ruleSetPolicy("local-" + $0) } ?? draft.groups.first?.name ?? "DIRECT",
                        options: policyOptions,
                        palette: palette,
                        buildRule: { accept in ruleEditor(.init(editing: nil, draft: draft, options: policyOptions, showsTarget: false, createGroup: nil)) { raw, _, _ in accept(raw) } },
                        createGroup: groupCreator,
                        save: { name, input, policy in
                            let rules = try await download(input)
                            let id = localID ?? UUID().uuidString.lowercased()
                            let value = ConfigurationLocalRuleSet(id: id, name: name, input: input, rules: rules)
                             
                             
                             
                            let updated = try await saveLocal(value)
                            try await receiveHostWrite(updated.0) { scheme in try scheme.updateLocalRuleSet(value) }
                             
                             
                            try await apply { snapshot in
                                var changed = snapshot
                                try changed.attachRuleSet(key: "local-" + id, name: name, rules: rules, policy: policy)
                                return changed
                            }
                            localSets = updated.1; modal = nil
                        }, close: { modal = nil })
                case .copy:
                    HakoTowerNameEditor(title: "Save as New Scheme", name: draft.label + " · 自定义", save: { name in try await copy(draft, name); modal = nil; close() }, close: { modal = nil })
                case .manual:
                    manualEditor(draft) { value in let result = try await save(value); await receiveSaved(result) }
                case .rule:
                    if let id = ruleID, let row = draft.rows.first(where: { $0.id == id }) {
                         
                         
                         
                         
                        ruleEditor(.init(editing: .init(raw: row.raw, isEnabled: draft.isEnabled(row.raw), note: draft.note(for: row.raw)),
                            draft: draft, options: policyOptions, showsTarget: true, createGroup: groupCreator)) { raw, enabled, note in
                            mutate { snapshot in
                                var changed = snapshot
                                changed.setRule(raw, enabled: enabled, note: note, rowID: id)
                                return changed
                            }
                        }
                    } else {
                         
                         
                        ruleEditor(.init(editing: nil, draft: draft, options: policyOptions, showsTarget: true, createGroup: groupCreator)) { raw, enabled, note in
                            mutate { snapshot in
                                var changed = snapshot
                                changed.insertRuleFirst(raw)
                                if let first = changed.rows.first { changed.setRule(raw, enabled: enabled, note: note, rowID: first.id) }
                                return changed
                            }
                        }
                    }
                }
            }.environment(\.hakoProductModalDismiss, { modal = nil })
        }
        .alert("恢复初始规则？", isPresented: $confirmsReset) {
            Button("Restore Initial Rules", role: .destructive) {
                let source = resetDocument
                mutate { snapshot in var value = snapshot; try value.replaceContents(OrderedJSON.parse(source)); return value }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Removes the rules, renames and reordering added after the scheme was created. My Rule Sets stay.") }
        .hakoDeleteConfirmation(draft.groups.first(where: { $0.id == deletingGroup })?.name ?? "",
            isPresented: Binding(get: { deletingGroup != nil }, set: { if !$0 { deletingGroup = nil } }),
            actionTitle: .copy("Delete Rule Group"), message: .copy("This group and its associated rules will be removed from the current scheme."),
            identifier: "configuration.rules.group.delete.confirm") { [deletingGroup] in
                if let id = deletingGroup { mutate { snapshot in var value = snapshot; try value.deleteRoutingGroup(id); return value } }
            }
        .hakoDeleteConfirmation(deletingLocal?.name ?? "",
            isPresented: Binding(get: { deletingLocal != nil }, set: { if !$0 { deletingLocal = nil } }),
            actionTitle: .copy("Delete Rule Set"), message: .copy("This local rule set will be deleted. Rule schemes in the library will also remove rules added from it."),
            identifier: "configuration.rules.local.delete.confirm") { [deletingLocal] in
                if let item = deletingLocal {
                    perform {
                        let updated = try await deleteLocal(item.id)
                        try await receiveHostWrite(updated.0) { scheme in scheme.removeRuleSet("local-" + item.id) }
                        localSets = updated.1
                    }
                }
            }

    }
    private var localRuleSetsSection: some View {
            Section {
                Button { localID = nil; modal = .local } label: {
                    Label { VStack(alignment: .leading, spacing: 3) { Text("New Rule Set").font(.body).foregroundStyle(.primary); Text("Add manually or use a rule set link").font(.caption).foregroundStyle(Color.secondary) } } icon: { Image(systemName: "text.badge.plus").foregroundStyle(.primary) }
                }.buttonStyle(.plain)
                ForEach(localSets.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { item in
                    HStack(spacing: 12) {
                        Button { localID = item.id; modal = .local } label: {
                            HStack { Text("🧩").font(.title3); VStack(alignment: .leading, spacing: 3) { Text(verbatim: item.name).foregroundStyle(.primary); Text(hako: .format("Local · %@ rules", [String(item.rules.count)])).font(.caption).foregroundStyle(.secondary) }; Spacer() }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { toggleLocal(item) } label: {
                            mark(installedRuleSets.contains("local-" + item.id), loading: false)
                        }.buttonStyle(.plain)
                    }.contextMenu {
                        Button("Edit Rule Content") { localID = item.id; modal = .local }
                        Button("Delete Local Rule Set", role: .destructive) { deletingLocal = item }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { deletingLocal = item }
                            .tint(.red)
                            .accessibilityIdentifier("configuration.rules.local.delete")
                    }
                }
            } header: { HStack { Text("My Rule Sets"); Spacer(); Text(hako: .format("%@ items", [String(localSets.count)])) } }

    }
    @ViewBuilder
    private func mark(_ selected: Bool, loading: Bool) -> some View {
        if loading {
            ProgressView()
                .controlSize(.small)
                .frame(width: HakoTheme.Control.minimumHitTarget, height: HakoTheme.Control.minimumHitTarget)
                .accessibilityLabel(Text(HakoCopy.key("Loading")))
        } else {
            Image(systemName: selected ? "minus.circle" : "plus.circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.red : .accentColor)
                .frame(width: HakoTheme.Control.minimumHitTarget, height: HakoTheme.Control.minimumHitTarget)
                .contentShape(Rectangle())
                .accessibilityLabel(Text(HakoCopy.key(selected ? "Remove from Current Rules" : "Add to Current Rules")))
        }
    }
    private func emoji(_ name: String) -> String? {
        guard let first = name.trimmingCharacters(in: .whitespaces).first,
              first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) else { return nil }
        return String(first)
    }
     
    private var ruleSetNames: [String: String] {
        var names: [String: String] = [:]
        for set in localSets { names["local-" + set.id] = set.name }
        for entry in ConfigurationRuleCatalog.builtIn.entries { names["catalog-" + entry.id] = entry.displayName }
        return names
    }
    private func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return emoji(trimmed) == nil ? trimmed : String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    private func summary(_ group: ConfigurationRuleDraft.Group) -> String { if case .array(let values) = group.document.topLevelValue("proxies"), case .string(let value) = values.first { return value }; return group.type == "url-test" ? "自动选择" : "节点匹配" }
    private func route(_ value: ConfigurationRuleCatalogDefaultRoute) -> String { value == .direct ? "直连" : value == .reject ? "拦截" : "代理" }
     
     
     
     
     
    private func toggleCatalog(_ entry: ConfigurationRuleCatalogEntry) {
        let key = "catalog-" + entry.id
        guard !loadingRuleSets.contains(key) else { return }
        if installedRuleSets.contains(key) {
            change { value in var value = value; value.removeRuleSet(key); return value }
            return
        }
        loadingRuleSets.insert(key)
        Task { @MainActor in
            defer { loadingRuleSets.remove(key) }
            do {
                let content = try await download(entry.sourceURLString)
                try await apply { value in
                    var value = value
                    try value.addRuleSet(key: key, name: entry.displayName, rules: content, defaultRoute: entry.defaultRoute.rawValue)
                    return value
                }
            } catch { self.error = HakoTowerRulesErrorText.describe(error) }
        }
    }
    private func toggleLocal(_ item: ConfigurationLocalRuleSet) {
        let key = "local-" + item.id
        let removing = installedRuleSets.contains(key)
        change { snapshot in
            var value = snapshot
            if removing { value.removeRuleSet(key) } else { try value.addRuleSet(key: key, name: item.name, rules: item.rules, defaultRoute: "proxy") }
            return value
        }
    }
     
     
     
    private func apply(_ transform: @escaping @Sendable (ConfigurationRuleDraft) throws -> ConfigurationRuleDraft) async throws {
         
         
         
        try await ordered.run {
            let snapshot = draft
            let value = try await Task.detached { try transform(snapshot) }.value
            let keys = await Task.detached { value.referencedRuleSets }.value
            withAnimation { draft = value; installedRuleSets = keys; hasUnsavedChanges = true }
        }
    }
    private func change(_ transform: @escaping @Sendable (ConfigurationRuleDraft) throws -> ConfigurationRuleDraft) {
        Task { @MainActor in
            do { try await apply(transform) } catch { self.error = HakoTowerRulesErrorText.describe(error) }
        }
    }
    private func receiveSaved(_ value: ConfigurationRuleDraft) async {
        let keys = await Task.detached { value.referencedRuleSets }.value
         
         
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            draft = value; baseline = value; installedRuleSets = keys; baselineRuleSets = keys; hasUnsavedChanges = false
        }
    }
    private func receivePending(_ value: ConfigurationRuleDraft) async {
        let keys = await Task.detached { value.referencedRuleSets }.value
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            draft = value; installedRuleSets = keys; hasUnsavedChanges = true
        }
    }
     
     
     
     
     
    private func receiveHostWrite(_ stored: ConfigurationRuleDraft, applying change: @escaping @Sendable (inout ConfigurationRuleDraft) throws -> Void) async throws {
        try await ordered.run {
            guard hasUnsavedChanges else { await receiveSaved(stored); return }
            let snapshot = draft
            let value = try await Task.detached { var value = snapshot; try change(&value); return value }.value
            let keys = await Task.detached { value.referencedRuleSets }.value
            let storedKeys = await Task.detached { stored.referencedRuleSets }.value
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                draft = value; installedRuleSets = keys; baseline = stored; baselineRuleSets = storedKeys; hasUnsavedChanges = true
            }
        }
    }
    private func mutate(_ transform: @escaping @Sendable (ConfigurationRuleDraft) throws -> ConfigurationRuleDraft) {
        change(transform)
    }
    private func persist(_ value: ConfigurationRuleDraft, then: @escaping () -> Void = {}, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy else { completion(false); return }; busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do { let saved = try await save(value); await receiveSaved(saved); completion(true); then() }
            catch { await receivePending(value); self.error = HakoTowerRulesErrorText.describe(error); completion(false) }
        }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil
        Task { @MainActor in defer { busy = false }; do { try await operation() } catch { self.error = HakoTowerRulesErrorText.describe(error) } }
    }
}

private struct HakoTowerNameEditor: View {
    let title: String
    let initialName: String
    @State private var name: String
    let save: (String) async throws -> Void
    let close: () -> Void
    @State private var busy = false
    @State private var error: String?
    @Environment(\.hakoInsideProductModalPresentation) private var insideProductModal
    init(title: String, name: String, save: @escaping (String) async throws -> Void, close: @escaping () -> Void) {
        self.title = title; initialName = name; _name = State(initialValue: name); self.save = save; self.close = close
    }
    private func commit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { completion(false); return }
        busy = true; error = nil
        Task { @MainActor in defer { busy = false }; do { try await save(name); completion(true) } catch { self.error = HakoTowerRulesErrorText.describe(error); completion(false) } }
    }
    var body: some View {
        Form { Section("Scheme Name") { TextField("Name", text: $name).accessibilityIdentifier("configuration.rules.copy.name") }; if let error { Text(verbatim: error).foregroundStyle(.orange) } }
            .hakoPageTitle(.copy(title)).disabled(busy)
            .hakoToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
                ToolbarItem(placement: .confirmationAction) { Button { commit() } label: { HakoActionProgressLabel(.copy("Save"), isBusy: busy) }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .hakoRegistersDeparture(isDirty: name != initialName, isBusy: busy, save: { commit($0) }, discard: { name = initialName })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    HakoModalActionBar(primaryTitle: "Save", primaryDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, isBusy: busy, onPrimary: { commit() })
                }
            }
    }
}

private struct HakoTowerLocalRuleEditor: View {
     
    enum Kind: String, CaseIterable, Identifiable { case link, manual; var id: String { rawValue } }
    let value: ConfigurationLocalRuleSet?
    let options: HakoRulePolicyOptions
    let palette: HakoProductPalette
     
    let buildRule: (@escaping (String) -> Void) -> AnyView
     
     
     
    let createGroup: ((@escaping (String?) -> Void) -> AnyView)?
    let save: (String, String, String) async throws -> Void
    let close: () -> Void
    @State private var name: String
    @State private var kind: Kind
     
    @State private var input: String
     
    @State private var lines: [String]
    @State private var policy: String
    @State private var pickingPolicy = false
    @State private var addingRule = false
    @State private var busy = false
    @State private var error: String?
    @Environment(\.hakoInsideProductModalPresentation) private var insideProductModal
    private let initialPolicy: String
    init(value: ConfigurationLocalRuleSet?, policy: String, options: HakoRulePolicyOptions, palette: HakoProductPalette,
         buildRule: @escaping (@escaping (String) -> Void) -> AnyView,
         createGroup: ((@escaping (String?) -> Void) -> AnyView)? = nil,
         save: @escaping (String, String, String) async throws -> Void, close: @escaping () -> Void) {
        self.value = value; self.options = options; self.palette = palette; self.buildRule = buildRule; self.createGroup = createGroup; self.save = save; self.close = close
        self.initialPolicy = policy
        let stored = value?.input ?? ""
        let link = Self.looksLikeLink(stored)
        _name = State(initialValue: value?.name ?? ""); _policy = State(initialValue: policy)
        _kind = State(initialValue: link ? .link : .manual)
        _input = State(initialValue: link ? stored : "")
        _lines = State(initialValue: link ? [] : Self.lines(of: stored))
    }
    static func looksLikeLink(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.contains("\n") && (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
    }
     
     
    static func lines(of input: String) -> [String] {
        input.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
    }
    private var contents: String { kind == .link ? input : lines.joined(separator: "\n") }
    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !policy.isEmpty
            && (kind == .link ? Self.looksLikeLink(input) : !lines.isEmpty)
    }
    private func commit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, ready else { completion(false); return }
        busy = true; error = nil
        Task { @MainActor in defer { busy = false }; do { try await save(name, contents, policy); completion(true) } catch { self.error = HakoTowerRulesErrorText.describe(error); completion(false) } }
    }
    var body: some View {
        Form {
            Section { TextField("Name", text: $name, prompt: Text(hako: .copy("e.g. 🎬 Netflix"))).accessibilityIdentifier("configuration.rules.set.name") }
            Section {
                Picker("Rules From", selection: $kind) {
                    Text("Link").tag(Kind.link)
                    Text("Manual").tag(Kind.manual)
                }.pickerStyle(.segmented).accessibilityIdentifier("configuration.rules.set.kind")
                if kind == .link {
                    TextField("Link", text: $input, prompt: Text(verbatim: "https://"))
                        .hakoRuleSetLinkInput()
                        .accessibilityIdentifier("configuration.rules.set.contents")
                } else {
                    if lines.isEmpty {
                         
                         
                        Text("No rules yet. Tap Add Rule and build them one at a time. The policy chosen below applies to all of them.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("configuration.rules.set.empty")
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HakoTowerRuleSummary(row: .init(raw: line), palette: palette)
                    }
                    .onDelete { offsets in lines.remove(atOffsets: offsets) }
                    HakoAddRow(Text(hako: .copy("Add Rule"))) { addingRule = true }
                        .accessibilityIdentifier("configuration.rules.set.rule.add")
                }
            } header: { Text("Rules") } footer: {
                Text(kind == .link
                    ? "A text, YAML or MRS rule set the app downloads and keeps updated."
                    : "Add the rules this set matches. The policy is chosen below, not written on each rule.")
            }
            Section {
                Button { pickingPolicy = true } label: {
                    HStack {
                        Text("Policy").foregroundStyle(.primary)
                        Spacer()
                        Text(verbatim: policy).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("configuration.rules.set.policy")
            } footer: { Text("Traffic matching these rules goes to this policy. Saving adds the rule set to the current rules.") }
            if let error { Text(verbatim: error).foregroundStyle(.orange) }
        }.disabled(busy).hakoPageTitle(.copy(value == nil ? "New Rule Set" : "Edit Rule Set"))
            .hakoToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close).disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button { commit() } label: { HakoActionProgressLabel(.copy("Save"), isBusy: busy) }.disabled(busy || !ready) }
            }
             
             
            .hakoRegistersDeparture(
                isDirty: name != (value?.name ?? "") || policy != initialPolicy
                    || kind != (Self.looksLikeLink(value?.input ?? "") ? .link : .manual)
                    || input != (Self.looksLikeLink(value?.input ?? "") ? (value?.input ?? "") : "")
                    || lines != (Self.looksLikeLink(value?.input ?? "") ? [] : Self.lines(of: value?.input ?? "")),
                isBusy: busy, save: { commit($0) },
                discard: {
                    name = value?.name ?? ""; policy = initialPolicy
                    let stored = value?.input ?? ""; let link = Self.looksLikeLink(stored)
                    kind = link ? .link : .manual; input = link ? stored : ""; lines = link ? [] : Self.lines(of: stored)
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    HakoModalActionBar(primaryTitle: "Save", primaryDisabled: !ready, isBusy: busy, onPrimary: { commit() })
                }
            }
            .background {
                HakoRoutedViewDestination(isPresented: $pickingPolicy) {
                    HakoRulePolicyPickerView(
                        title: "Select Policy",
                        builtIns: HakoRulePolicyBuiltIns.ruleSet,
                        axPrefix: "configuration.rules.set.policy",
                        offersGlobal: false,
                        options: options,
                        current: policy,
                        createGroup: createGroup,
                        icon: { symbol in Image(systemName: symbol.rawValue) }
                    ) { policy = $0; pickingPolicy = false }
                    .hakoPushedDetailPage()
                }
                HakoRoutedViewDestination(isPresented: $addingRule) {
                    buildRule { raw in lines.append(raw); addingRule = false }
                        .hakoPushedDetailPage()
                }
            }
    }
}

 
enum HakoTowerRulesUXTestSeams {
    static func looksLikeLink(_ input: String) -> Bool { HakoTowerLocalRuleEditor.looksLikeLink(input) }
    static var blankGroup: ConfigurationRuleDraft.Group { HakoTowerGroupEditor.blankGroup }
}

private extension View {
     
    @ViewBuilder
    func hakoRuleSetLinkInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

 
 
 
 
 
 
 
 
enum HakoTowerGroupCandidates {
    static let builtinMembers = ["DIRECT", "REJECT"]

    static func available(
        groups: [String], excludingGroup: String,
        nodeSections: [ConfigurationRuleTargetCandidates.Section],
        selected: [String], query: String
    ) -> [ConfigurationRuleTargetCandidates.Section] {
        let taken = Set(selected)
        var sections = [
            ConfigurationRuleTargetCandidates.Section(id: "builtin", kind: .builtin, names: builtinMembers),
            ConfigurationRuleTargetCandidates.Section(id: "groups", kind: .groups, names: groups.filter { $0 != excludingGroup }),
        ]
        sections.append(contentsOf: nodeSections)
        let offered = sections.compactMap { section -> ConfigurationRuleTargetCandidates.Section? in
            var seen = Set<String>()
             
            let names = section.names.filter { !taken.contains($0) && (section.kind == .builtin || !builtinMembers.contains($0)) }
                .filter { seen.insert($0).inserted }
            return names.isEmpty ? nil : ConfigurationRuleTargetCandidates.Section(id: section.id, kind: section.kind, sourceLabel: section.sourceLabel, names: names)
        }
        return ConfigurationRuleTargetCandidates(sections: offered).filtered(by: query).sections
    }
}

 
 
 
 
public enum HakoTowerGroupIcon {
    public static func read(_ document: OrderedJSON) -> String {
        if case .string(let value) = document.topLevelValue("icon") { return value }
        return ""
    }

    public static func apply(_ icon: String, to document: OrderedJSON) -> OrderedJSON {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? document.removingTopLevel("icon") : document.settingTopLevel("icon", to: .string(trimmed))
    }
}

 
 
 
 
 
public enum HakoTowerGroupIconEcho: Equatable {
    case emoji(String)
    case symbol(HakoSymbol)
    case image(host: String)
    case nothingDraws

    public static func of(_ icon: String) -> HakoTowerGroupIconEcho? {
        switch HakoProxyGroupIconKind.of(icon) {
        case .none: return nil
        case .emoji(let value)?: return .emoji(value)
        case .symbol(let symbol)?: return .symbol(symbol)
        case .remote(let host)?: return .image(host: host)
        case .unrecognized?: return .nothingDraws
        }
    }

     
     
    public var label: String {
        switch self {
        case .emoji, .symbol: return "Shows as"
        case .image: return "Image on"
        case .nothingDraws: return "Saved with the group, but nothing draws it."
        }
    }
}

 
 
 
 
public struct HakoGroupIconImagesKey: EnvironmentKey {
    public static let defaultValue = false
}

extension EnvironmentValues {
    public var hakoGroupIconImages: Bool {
        get { self[HakoGroupIconImagesKey.self] }
        set { self[HakoGroupIconImagesKey.self] = newValue }
    }
}

 
 
 
public enum HakoTowerGroupIconPresentation: Equatable {
    case emoji(String)
    case symbol(HakoSymbol)
    case image(String)

    public static func of(_ icon: String, showsImages: Bool) -> HakoTowerGroupIconPresentation? {
        switch HakoProxyGroupIconKind.of(icon) {
        case .emoji(let value)?: return .emoji(value)
        case .symbol(let symbol)?: return .symbol(symbol)
        case .remote?: return showsImages ? .image(icon.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        case .unrecognized?, .none: return nil
        }
    }
}

 
 
 
 
public struct HakoTowerGroupIconView<Fallback: View>: View {
    let icon: String
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback
    @Environment(\.hakoGroupIconImages) private var showsImages

     
     
    public init(icon: String, size: CGFloat, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.icon = icon
        self.size = size
        self.fallback = fallback
    }

    public var body: some View {
        switch HakoTowerGroupIconPresentation.of(icon, showsImages: showsImages) {
        case .emoji(let value)?:
            Text(verbatim: value).font(.title3)
        case .symbol(let symbol)?:
            Image(systemName: symbol.rawValue).font(.body).foregroundStyle(.secondary)
        case .image(let address)?:
            ProxyGroupIconView(address: address, size: size, connected: true) {
                RoundedRectangle(cornerRadius: HakoTheme.Layout.proxyGroupIconCornerRadius, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: HakoTheme.Layout.proxyGroupIconCornerRadius, style: .continuous))
        case nil:
            fallback()
        }
    }
}

struct HakoTowerGroupIconEchoRow: View {
    let icon: String

    var body: some View {
        if let echo = HakoTowerGroupIconEcho.of(icon) {
            HStack {
                Text(LocalizedStringKey(echo.label))
                    .foregroundStyle(echo == .nothingDraws ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Spacer(minLength: 8)
                switch echo {
                case .emoji(let emoji): Text(verbatim: emoji).foregroundStyle(.secondary)
                case .symbol(let symbol): Image(systemName: symbol.rawValue).foregroundStyle(.secondary)
                case .image(let host): Text(verbatim: host).foregroundStyle(.secondary)
                case .nothingDraws: EmptyView()
                }
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("configuration.rules.group.icon.echo")
        }
    }
}

private struct HakoTowerGroupEditor: View {
    let group: ConfigurationRuleDraft.Group
    let all: [ConfigurationRuleDraft.Group]
    let identityOnly: Bool
     
     
    let nodeSections: [ConfigurationRuleTargetCandidates.Section]
    let save: (OrderedJSON) async throws -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var name: String
    @State private var icon: String
    @State private var kind: String
    @State private var selected: [String]
    @State private var includeAll: Bool
    @State private var filter: String
    @State private var busy = false
    @State private var error: String?
    @Environment(\.hakoInsideProductModalPresentation) private var insideProductModal
     
     
    static var blankGroup: ConfigurationRuleDraft.Group {
        .init(id: UUID(), document: .object([("name", .string("")), ("type", .string("select")), ("proxies", .array([]))]))
    }
    init(group: ConfigurationRuleDraft.Group, all: [ConfigurationRuleDraft.Group], identityOnly: Bool,
        nodeSections: [ConfigurationRuleTargetCandidates.Section] = [],
        save: @escaping (OrderedJSON) async throws -> Void, close: @escaping () -> Void) {
        self.group = group; self.all = all; self.identityOnly = identityOnly; self.nodeSections = nodeSections; self.save = save; self.close = close
        _name = State(initialValue: group.name); _kind = State(initialValue: group.type)
        _icon = State(initialValue: HakoTowerGroupIcon.read(group.document))
        if case .array(let values) = group.document.topLevelValue("proxies") { _selected = State(initialValue: values.compactMap { if case .string(let value) = $0 { return value }; return nil }) }
        else { _selected = State(initialValue: []) }
        _includeAll = State(initialValue: group.document.topLevelValue("include-all") == .scalar("true") || group.document.topLevelValue("include-all-proxies") == .scalar("true"))
        if case .string(let value) = group.document.topLevelValue("filter") { _filter = State(initialValue: value) } else { _filter = State(initialValue: "") }
    }
    private var originalSelected: [String] {
        guard case .array(let values) = group.document.topLevelValue("proxies") else { return [] }
        return values.compactMap { if case .string(let name) = $0 { return name }; return nil }
    }
    private var originalIncludeAll: Bool { group.document.topLevelValue("include-all") == .scalar("true") || group.document.topLevelValue("include-all-proxies") == .scalar("true") }
    private var originalFilter: String { if case .string(let value) = group.document.topLevelValue("filter") { return value }; return "" }
    private var dirty: Bool { name != group.name || icon != HakoTowerGroupIcon.read(group.document) || kind != group.type || selected != originalSelected || includeAll != originalIncludeAll || filter != originalFilter }
    private var availableSections: [ConfigurationRuleTargetCandidates.Section] {
        HakoTowerGroupCandidates.available(
            groups: all.filter { $0.id != group.id }.map(\.name), excludingGroup: group.name,
            nodeSections: nodeSections, selected: selected, query: query
        )
    }
    private func sectionTitle(_ section: ConfigurationRuleTargetCandidates.Section) -> Text {
        switch section.kind {
        case .builtin: return Text("Built-in")
        case .groups: return Text("Policy Groups")
        case .source: return Text(verbatim: section.sourceLabel ?? section.id)
        }
    }
    var body: some View {
        Form {
            if identityOnly {
                Section("名称与图标") {
                    TextField("Group Name", text: $name).accessibilityIdentifier("configuration.rules.group.name")
                    TextField("Icon URL", text: $icon, prompt: Text(verbatim: "https://…")).autocorrectionDisabled().accessibilityIdentifier("configuration.rules.group.icon")
                    HakoTowerGroupIconEchoRow(icon: icon)
                }
            } else {
                Section("名称与图标") {
                    TextField("Group Name", text: $name).accessibilityIdentifier("configuration.rules.group.name")
                    TextField("Icon URL", text: $icon, prompt: Text(verbatim: "https://…")).autocorrectionDisabled().accessibilityIdentifier("configuration.rules.group.icon")
                    HakoTowerGroupIconEchoRow(icon: icon)
                }
                Section {
                    Picker("Group Type", selection: $kind) { ForEach(Array(Set([group.type, "select", "url-test", "fallback"])).sorted(), id: \.self) { Text(verbatim: $0).tag($0) } }.accessibilityIdentifier("configuration.rules.group.type")
                } footer: { Text("Changing the group type changes how routes are chosen.") }
                Section("Selected (in priority order)") {
                    ForEach(selected, id: \.self) { item in
                        HStack { Text(verbatim: item); Spacer(); Button { selected.removeAll { $0 == item } } label: { Image(systemName: "minus.circle").foregroundStyle(.red) }.buttonStyle(.borderless) }
                    }.onMove { selected.move(fromOffsets: $0, toOffset: $1) }
                }
                if !nodeSections.isEmpty {
                    Section("Available") {
                        TextField("Search nodes", text: $query).accessibilityIdentifier("configuration.rules.group.search")
                    }
                }
                ForEach(availableSections) { section in
                    Section {
                        ForEach(section.names, id: \.self) { item in
                            Button { selected.append(item) } label: { HStack { Text(verbatim: item).foregroundStyle(.primary); Spacer(); Image(systemName: "plus.circle") }.contentShape(Rectangle()) }.buttonStyle(.plain)
                        }
                    } header: { sectionTitle(section) }
                }
                Section("Node Name Match") {
                    Toggle("Include all proxies", isOn: $includeAll).accessibilityIdentifier("configuration.rules.group.include-all")
                    TextField("Include filter", text: $filter).accessibilityIdentifier("configuration.rules.group.filter")
                }
            }
            if let error { Text(verbatim: error).foregroundStyle(.orange) }
        }
        .modifier(HakoTowerReorderMode())
        .disabled(busy).hakoPageTitle(.copy(identityOnly ? "修改名称与图标" : group.name.isEmpty ? "New Policy Group" : group.name))
        .hakoToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close).disabled(busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button { commit() } label: { HakoActionProgressLabel(.copy("Save"), isBusy: busy) }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!identityOnly && selected.isEmpty && !includeAll))
            }
        }
        .hakoRegistersDeparture(isDirty: dirty, isBusy: busy, save: { commit($0) }, discard: { name = group.name; icon = HakoTowerGroupIcon.read(group.document); kind = group.type; selected = originalSelected; includeAll = originalIncludeAll; filter = originalFilter })
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                HakoModalActionBar(primaryTitle: "Save", primaryDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!identityOnly && selected.isEmpty && !includeAll), isBusy: busy, onPrimary: { commit() })
            }
        }
    }
    private func commit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, identityOnly || !selected.isEmpty || includeAll else { completion(false); return }
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                var document = HakoTowerGroupIcon.apply(icon, to: group.document.settingTopLevel("name", to: .string(name)))
                if !identityOnly {
                    if kind != group.type, case .object(let fields) = document {
                        let typeFields: Set<String> = ["url", "interval", "tolerance", "strategy", "lazy", "expected-status", "max-failed-times"]
                        document = .object(fields.filter { !typeFields.contains($0.key) })
                    }
                    document = document.settingTopLevel("type", to: .string(kind)).settingTopLevel("proxies", to: .array(selected.map(OrderedJSON.string)))
                        .settingTopLevel("include-all", to: .scalar(includeAll ? "true" : "false"))
                        .settingTopLevel("include-all-proxies", to: .scalar("false")).settingTopLevel("filter", to: .string(filter))
                    if kind == "url-test" || kind == "fallback" {
                        if document.topLevelValue("url") == nil { document = document.settingTopLevel("url", to: .string("https://www.gstatic.com/generate_204")) }
                        if document.topLevelValue("interval") == nil { document = document.settingTopLevel("interval", to: .scalar("300")) }
                    }
                }
                try await save(document); completion(true)
            } catch { self.error = HakoTowerRulesErrorText.describe(error); completion(false) }
        }
    }
}

 
 
private struct HakoTowerSelectionFeedback: ViewModifier {
    let trigger: Set<String>
    func body(content: Content) -> some View {
        if #available(iOS 17, macOS 14, tvOS 17, *) {
            content.sensoryFeedback(.success, trigger: trigger)
        } else {
            content
        }
    }
}

struct HakoTowerReorderMode: ViewModifier {
    var active = true
    func body(content: Content) -> some View {
#if os(iOS)
        content.environment(\.editMode, .constant(active ? .active : .inactive))
#else
        content
#endif
    }
}


private struct HakoTowerSearchPlacement: ViewModifier {
    @Binding var text: String
    let palette: HakoProductPalette
    func body(content: Content) -> some View {
        content.hakoProductModalSearchable(text: $text, prompt: Text("Search Rules"))
#if os(iOS)
            .listStyle(.insetGrouped)
#endif
    }
}

 
struct HakoTowerRuleSummary: View {
    let row: ConfigurationRuleDraft.Row
    let palette: HakoProductPalette
     
     
     
    var ruleSetNames: [String: String] = [:]
    var body: some View {
        let rule = HakoStructuredRule.parse(row.raw)
        let payload = rule.map { $0.action == .ruleSet ? (ruleSetNames[$0.content] ?? $0.content) : $0.content } ?? row.raw
        HakoRuleListRow(row: HakoRuleFrozenRow(.init(raw: row.raw,
            type: rule?.action.rawValue ?? "RAW", payload: payload,
            target: rule?.target ?? "")), palette: palette)
    }
}

 
 
struct HakoTowerRuleSearchSnapshot {
    var query = ""
    var rows: [ConfigurationRuleDraft.Row] = []
    func visible(for query: String, refreshing: Bool) -> [ConfigurationRuleDraft.Row] {
        self.query == query ? rows : []
    }
}

private struct HakoTowerInlineRules: View {
    let rows: [ConfigurationRuleDraft.Row]
    let version: ConfigurationSourceVersion
    let query: String
    let palette: HakoProductPalette
     
     
     
    var remove: ((UUID) -> Void)? = nil
     
     
     
    var move: ((IndexSet, Int) -> Void)? = nil
    var ruleSetNames: [String: String] = [:]
     
    var addRule: (() -> Void)? = nil
     
     
    var edit: ((UUID) -> Void)? = nil
    @State private var results = HakoTowerRuleSearchSnapshot()
    @State private var completedRequest: SearchRequest?

    private struct SearchRequest: Equatable {
        let version: ConfigurationSourceVersion
        let count: Int
        let query: String
    }
    private var request: SearchRequest {
        .init(version: version, count: rows.count,
              query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var body: some View {
        let current = request
        let searching = !current.query.isEmpty && completedRequest != current
        let visible = current.query.isEmpty ? rows : results.visible(for: current.query, refreshing: searching)
        Section {
            ForEach(visible) { row in
                if let edit {
                    Button { edit(row.id) } label: {
                        HStack(spacing: 8) {
                            HakoTowerRuleSummary(row: row, palette: palette, ruleSetNames: ruleSetNames)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("configuration.rules.rule.row")
                    .deleteDisabled(row.isFinal)
                    .moveDisabled(row.isFinal || !current.query.isEmpty)
                } else {
                    HakoTowerRuleSummary(row: row, palette: palette, ruleSetNames: ruleSetNames)
                        .deleteDisabled(row.isFinal)
                        .moveDisabled(row.isFinal || !current.query.isEmpty)
                }
            }
            .onDelete { offsets in
                guard let remove else { return }
                for index in offsets where visible.indices.contains(index) && !visible[index].isFinal { remove(visible[index].id) }
            }
            .onMove { offsets, destination in
                 
                 
                guard let move, current.query.isEmpty else { return }
                move(offsets, destination)
            }
            if searching && results.query != current.query { ProgressView("Searching…") }
            else if !searching && visible.isEmpty { Text("No results").foregroundStyle(.secondary) }
            if let addRule, current.query.isEmpty {
                HakoAddRow(Text(hako: .copy("Add Rule"))) { addRule() }
                    .accessibilityIdentifier("configuration.rules.rule.add")
            }
        } header: {
            HStack {
                Text("Current Rules")
                Spacer()
                Text(hako: .format("%@ rules", [String(visible.count)]))
            }
        } footer: { Text("Matched from top to bottom") }
        .task(id: current) {
            guard !current.query.isEmpty else { results = .init(); completedRequest = current; return }
            let source = rows, text = current.query
            let worker = Task.detached(priority: .userInitiated) {
                var result: [ConfigurationRuleDraft.Row] = []
                for row in source {
                    if Task.isCancelled { return result }
                    if row.raw.localizedCaseInsensitiveContains(text) { result.append(row) }
                }
                return result
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                results = .init(query: current.query, rows: result); completedRequest = current
            }
        }
    }
}


 
public enum HakoConfigurationRuleLibrarySection: CaseIterable {
    case builtin, custom, subscription, file
    public var title: String {
        switch self {
        case .builtin: "Built-in Rules"
        case .custom: "My Rules"
        case .subscription: "From Profile URLs"
        case .file: "From Files"
        }
    }
    public func contains(_ source: ConfigurationSourceRecord) -> Bool {
        switch source.origin {
        case .subscription: return self == .subscription
        case .file: return self == .file
        case .customNodes: return self == .custom
        case .bundled: return false
        }
    }
    public func contains(_ scheme: ConfigurationRuleScheme, library: ConfigurationLibrarySnapshot) -> Bool {
        if scheme.baseSchemeID.map(ConfigurationBuiltins.isNative) == true { return self == .custom }
        let base = scheme.baseSchemeID.flatMap { id in
            ConfigurationBuiltins.schemes.first { $0.id == id } ?? library.rules.first { $0.id == id }
        } ?? scheme
        switch base.kind {
        case .builtin: return self == .builtin
         
         
        case .community: return false
        case .custom: return self == .custom
        case .supplied, .imported:
            return library.sources.first { $0.id == base.sourceID }.map { contains($0) } ?? (self == .file)
        }
    }
}

extension HakoRulePolicyBuiltIns {
     
     
     
     
     
    public static let ruleSet: [(name: String, caption: String)] =
        rule.filter { ConfigurationRuleTargetCandidates.builtinPolicies.contains($0.name) }
}
