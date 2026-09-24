import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
public struct HakoMacConfigurationInspectorActions {
    public var rename: @MainActor (String) -> Void
    public var setSources: @MainActor ([String]) -> Void
    public var setScheme: @MainActor (String) -> Void
    public var activate: @MainActor () -> Void
    public var duplicate: @MainActor () -> Void
    public var export: @MainActor () -> Void
    public var editSource: @MainActor () -> Void
    public var delete: @MainActor () -> Void
     
    public var setSourceUpdates: @MainActor (Bool) -> Void
    public var openRuntimePreview: @MainActor () -> Void
    public var restoreLastKnownGood: @MainActor () -> Void
    public var setAutoUpdate: @MainActor (Bool) -> Void
    public var setInterval: @MainActor (Int) -> Void
    public var updateSource: @MainActor () -> Void
    public var stripCredentials: @MainActor () -> Void
    public var adoptHeldBack: @MainActor (String) -> Void
    public var dismissHeldBack: @MainActor () -> Void
     
     
     
    public var setScope: @MainActor (String, ConfigurationNodeScope?) -> Void = { _, _ in }
     
    public var copyProfileURL: @MainActor () -> Void = {}
     
     
     
    public var setOriginalUse: @MainActor (Bool) -> Void = { _ in }
    public var loadScopeChoices: @MainActor (ConfigurationSourceRecord) async throws -> HakoMacNodeScopeChoices = { _ in
        throw ConfigurationLibraryError.unreadable
    }

    public init(
        rename: @escaping @MainActor (String) -> Void,
        setSources: @escaping @MainActor ([String]) -> Void,
        setScheme: @escaping @MainActor (String) -> Void,
        activate: @escaping @MainActor () -> Void,
        duplicate: @escaping @MainActor () -> Void,
        export: @escaping @MainActor () -> Void,
        editSource: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void,
        setSourceUpdates: @escaping @MainActor (Bool) -> Void,
        openRuntimePreview: @escaping @MainActor () -> Void,
        restoreLastKnownGood: @escaping @MainActor () -> Void,
        setAutoUpdate: @escaping @MainActor (Bool) -> Void,
        setInterval: @escaping @MainActor (Int) -> Void,
        updateSource: @escaping @MainActor () -> Void,
        stripCredentials: @escaping @MainActor () -> Void,
        adoptHeldBack: @escaping @MainActor (String) -> Void,
        dismissHeldBack: @escaping @MainActor () -> Void
    ) {
        self.rename = rename; self.setSources = setSources; self.setScheme = setScheme
        self.activate = activate; self.duplicate = duplicate; self.export = export
        self.editSource = editSource; self.delete = delete
        self.setSourceUpdates = setSourceUpdates; self.openRuntimePreview = openRuntimePreview
        self.restoreLastKnownGood = restoreLastKnownGood
        self.setAutoUpdate = setAutoUpdate; self.setInterval = setInterval; self.updateSource = updateSource
        self.stripCredentials = stripCredentials; self.adoptHeldBack = adoptHeldBack; self.dismissHeldBack = dismissHeldBack
    }

    public static var unavailable: Self {
        Self(
            rename: { _ in }, setSources: { _ in }, setScheme: { _ in },
            activate: {}, duplicate: {}, export: {}, editSource: {}, delete: {},
            setSourceUpdates: { _ in }, openRuntimePreview: {}, restoreLastKnownGood: {},
            setAutoUpdate: { _ in }, setInterval: { _ in }, updateSource: {},
            stripCredentials: {}, adoptHeldBack: { _ in }, dismissHeldBack: {}
        )
    }
}

 
 
 
 
public struct HakoMacConfigurationInspector: View {
    private let profile: HakoProfileSnapshot
    private let sources: [ConfigurationSourceRecord]
     
    private let ruleShelves: [HakoMacRuleLibraryShelf]
    private let schemes: [ConfigurationRuleScheme]
    private let recipe: ConfigurationRecipe?
    private let scriptsActions: HakoMacScriptsActions
    private let profileURL: String?
    private let actions: HakoMacConfigurationInspectorActions
     
     
    private let door: (HakoMacConfigurationDoor) -> AnyView
    @State private var name: String
    @State private var chosenSources: Set<String>
    @State private var chosenScheme: String
     
    @State private var scripts = HakoMacScriptsState.empty
    @State private var showsAllHeldBack = false
    @State private var confirmsCredentialRemoval = false
    @Environment(\.locale) private var locale

    public init(
        profile: HakoProfileSnapshot,
        sources: [ConfigurationSourceRecord],
        ruleShelves: [HakoMacRuleLibraryShelf],
        recipe: ConfigurationRecipe?,
        scriptsActions: HakoMacScriptsActions,
        profileURL: String? = nil,
        actions: HakoMacConfigurationInspectorActions,
        door: @escaping (HakoMacConfigurationDoor) -> AnyView = { _ in AnyView(EmptyView()) }
    ) {
        self.profile = profile
        self.sources = sources
        let schemes = ruleShelves.flatMap(\.schemes)
        self.ruleShelves = ruleShelves
        self.schemes = schemes
        self.recipe = recipe
        self.scriptsActions = scriptsActions
        self.profileURL = profileURL
        self.actions = actions
        self.door = door
        _name = State(initialValue: profile.label)
        let seeds = Self.seeds(profile: profile, recipe: recipe, sources: sources, schemes: schemes)
        _chosenSources = State(initialValue: seeds.sources)
        _chosenScheme = State(initialValue: seeds.scheme)
    }

    private var isComposed: Bool { recipe != nil }
     
    private static let heldBackRowsShownAtOnce = 8

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                headerCard
                identity
                if isComposed || profile.canEditSource {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    composition
                }
                if !profile.heldBackUpdates.isEmpty { heldBack }
                overrides
                network
                if profile.source == .remote { profileURLSection }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("configuration-center.configuration")
         
         
         
         
         
         
         
         
         
         
         
        .onChange(of: recipe?.sources.map(\.id)) { ids in
            let next = ids.map(Set.init) ?? Self.seeds(profile: profile, recipe: nil, sources: sources, schemes: schemes).sources
            HakoMacDebugLog.note("page.resync sources recipe=\(ids ?? []) chosen \(chosenSources.sorted()) → \(next.sorted())")
            chosenSources = next
        }
        .onChange(of: recipe?.ruleSchemeID) { scheme in
            let next = scheme ?? Self.seeds(profile: profile, recipe: nil, sources: sources, schemes: schemes).scheme
            HakoMacDebugLog.note("page.resync scheme recipe=\(scheme ?? "nil") chosen \(chosenScheme) → \(next)")
            chosenScheme = next
        }
        }
        .task(id: profile.id) { scripts = await scriptsActions.load() }
        .onAppear { HakoMacDebugLog.note("page.appear \(profile.id.rawValue) composed=\(isComposed) follows=\(String(describing: profile.followsConfigurationSourceUpdates)) canEditSource=\(profile.canEditSource)") }
        .onChange(of: profile.followsConfigurationSourceUpdates) { follows in
            HakoMacDebugLog.note("page.profile \(profile.id.rawValue) follows=\(String(describing: follows)) composed=\(isComposed)")
        }
    }

     

     
     
    private var headerCard: some View {
        Section {
            HStack(spacing: HakoTheme.Spacing.compact) {
                 
                 
                HStack(spacing: 6) {
                    Circle().fill(profile.isCurrent ? Color.green : Color.secondary).frame(width: 8, height: 8)
                    Text(hako: profile.isCurrent ? .copy("In Use") : profile.sourceSummary).lineLimit(1)
                }
                Spacer()
                if !profile.isCurrent {
                    Button { actions.activate() } label: { Text(hako: .copy("Use This Profile")) }
                        .disabled(profile.isBusy)
                        .accessibilityIdentifier("configuration-center.configuration.activate")
                }
                Menu {
                    Button { actions.duplicate() } label: { Text(hako: .copy("Duplicate")) }
                    Button { actions.export() } label: { Text(hako: .copy("Export")) }
                    if profile.canEditSource {
                        Button { actions.editSource() } label: { Text(hako: .copy("Edit Source")) }
                    }
                    if profile.canOpenRuntimePreview || profile.canRestoreLastKnownGood { Divider() }
                    if profile.canOpenRuntimePreview {
                        Button { actions.openRuntimePreview() } label: { Text(hako: .copy("View Runtime Configuration")) }
                    }
                    if profile.canRestoreLastKnownGood {
                        Button { actions.restoreLastKnownGood() } label: { Text(hako: .copy("Restore Last Known Good")) }
                    }
                    Divider()
                    Button(role: .destructive) { actions.delete() } label: { Text(hako: .copy("Delete")) }
                        .disabled(!profile.canDelete)
                        .accessibilityIdentifier("configuration-center.configuration.delete")
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderedButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("configuration-center.configuration.more")
            }
            .tint(.primary)
            .padding(.vertical, 4)
        }
    }

    private var identity: some View {
        Section {
            TextField(text: $name) { Text(hako: .copy("Name")) }
                .onSubmit { commitName() }
                .accessibilityIdentifier("configuration-center.configuration.name")
            HakoMacValueRow(.copy("Source"), value: profile.sourceSummary)
        }
    }

     
     
     
     
     
     
    static func sourcesValue(_ sources: [ConfigurationSourceRecord], chosen: Set<String>) -> HakoDisplayText {
        let names = sources.filter { chosen.contains($0.id) }.map(\.label)
        switch names.count {
        case 0: return .copy("Choose node sources")
        case 1, 2: return .verbatim(names.joined(separator: " · "))
        default: return .count(names.count, one: "%@ source", other: "%@ sources")
        }
    }

     
     
     
     
    static func seeds(
        profile: HakoProfileSnapshot, recipe: ConfigurationRecipe?,
        sources: [ConfigurationSourceRecord], schemes: [ConfigurationRuleScheme]
    ) -> (sources: Set<String>, scheme: String) {
        if let recipe { return (Set(recipe.sources.map(\.id)), recipe.ruleSchemeID) }
        let own = "legacy-" + profile.id.rawValue
        let ownRules = "rules-" + own
        return (
            Set(sources.map(\.id).filter { $0 == own }),
            schemes.contains { $0.id == ownRules } ? ownRules : ""
        )
    }

    private func toggleSource(_ id: String) {
        let was = chosenSources.contains(id)
        if was { chosenSources.remove(id) } else { chosenSources.insert(id) }
        let ids = sources.map(\.id).filter { chosenSources.contains($0) }
        HakoMacDebugLog.note("page.toggle \(id) \(was ? "off" : "on") → setSources \(ids)")
        actions.setSources(ids)
    }

     
     
     
     
     
     
     
     
     
     
     
    private var offersOriginal: Bool { recipe.map { $0.sources.count == 1 } ?? profile.canEditSource }
     
     
    private var usesOriginal: Bool { recipe.map { $0.preservesOriginal == true } ?? true }

    private var composition: some View {
        Section {
             
             
             
             
             
            if offersOriginal {
                Toggle(isOn: Binding(get: { usesOriginal }, set: { actions.setOriginalUse($0) })) {
                    Text(hako: .copy("Use Original Configuration"))
                }
                .disabled(profile.isBusy)
                .accessibilityIdentifier("configuration-center.configuration.original")
            }
            if !(offersOriginal && usesOriginal) {
            HakoRoutedViewLink {
                HakoMacConfigurationSourcesPage(
                    sources: sources, chosen: $chosenSources, recipe: recipe, actions: actions,
                    toggle: toggleSource
                )
                .navigationTitle(Text(hako: .copy("Node Sources")))
            } label: {
                HakoMacPushRowLabel(.copy("Node Sources"), value: Self.sourcesValue(sources, chosen: chosenSources))
            }
            .accessibilityValue(Text(hako: Self.sourcesValue(sources, chosen: chosenSources)))
            .accessibilityIdentifier("configuration-center.configuration.sources.all")
            HakoRoutedViewLink {
                HakoMacConfigurationSchemesPage(
                    shelves: ruleShelves, chosen: $chosenScheme,
                    choose: chooseScheme, page: { door(.scheme($0)) }
                )
                .navigationTitle(Text(hako: .copy("Rule Scheme")))
            } label: {
                HakoMacPushRowLabel(.copy("Rule Scheme"), value: schemeValue)
            }
            .accessibilityValue(Text(hako: schemeValue))
            .accessibilityIdentifier("configuration-center.configuration.schemes.all")
            }
             
             
             
             
             
             
            if let follows = recipe?.followsUpdates ?? profile.followsConfigurationSourceUpdates {
                Toggle(isOn: Binding(get: { follows }, set: { actions.setSourceUpdates($0) })) {
                    Text(hako: .copy("Automatically Update Sources"))
                }
                .disabled(profile.isBusy)
                .accessibilityIdentifier("configuration-center.configuration.source-updates")
            }
        } footer: {
            if offersOriginal {
                Text(hako: usesOriginal
                    ? .copy("Runs the configuration as received, with its own proxy groups, rules and DNS.")
                    : .copy("Nodes come from the chosen node sources; routing follows the rule scheme."))
            }
        }
    }

     
    private var schemeValue: HakoDisplayText {
        schemes.first { $0.id == chosenScheme }.map { .verbatim($0.displayLabel) } ?? .copy("Choose a rule scheme")
    }

    private func chooseScheme(_ id: String) {
        guard id != chosenScheme else { return }
        chosenScheme = id
        HakoMacDebugLog.note("page.choose scheme \(id)")
        actions.setScheme(id)
    }

    private var overrides: some View {
        Section {
             
             
             
            HakoRoutedViewLink(onReturn: { Task { @MainActor in scripts = await scriptsActions.load() } }) {
                HakoMacScriptsPage(actions: scriptsActions, initial: scripts)
                    .navigationTitle(Text(hako: .copy("Overrides and Scripts")))
            } label: {
                HStack(spacing: HakoTheme.Spacing.compact) {
                    Text(hako: .copy("Overrides and Scripts"))
                    Spacer()
                    Text(hako: scripts.selectedID.flatMap { id in scripts.scripts.first { $0.id == id } }
                        .map { .verbatim($0.label) } ?? .copy("None"))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("configuration-center.configuration.scripts")
        }
    }

    private var network: some View {
        Section {
            HakoRoutedViewLink { door(.network) } label: { HakoMacPushRowLabel(.copy("Sniffer & NTP")) }
                .accessibilityIdentifier("configuration-center.configuration.network")
            HakoRoutedViewLink { door(.trust) } label: { HakoMacPushRowLabel(.copy("Compatibility & Trust")) }
                .accessibilityIdentifier("configuration-center.configuration.trust")
        } header: {
            Text(hako: .copy("Network"))
        }
    }

    private var profileURLSection: some View {
        Section {
            if let profileURL {
                HStack(spacing: HakoTheme.Spacing.compact) {
                    Text(hako: .copy("Profile URL"))
                    Spacer()
                    Text(verbatim: profileURL).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing)
                }
            }
            Toggle(isOn: Binding(get: { profile.autoUpdate }, set: { actions.setAutoUpdate($0) })) {
                Text(hako: .copy("Automatic Updates"))
            }
            .accessibilityIdentifier("configuration-center.config-url.auto-update")
            Picker(selection: Binding(get: { profile.updateIntervalHours }, set: { actions.setInterval($0) })) {
                ForEach([1, 3, 6, 12, 24, 48, 72], id: \.self) { hours in
                    Text(hako: .format("Every %@ hours", [String(hours)])).tag(hours)
                }
            } label: {
                Text(hako: .copy("Interval"))
            }
            .pickerStyle(.menu)
            .disabled(!profile.autoUpdate)
            .accessibilityIdentifier("configuration-center.config-url.interval")
            if let usage = profile.subscription {
                HakoMacValueRow(.copy("Traffic"), value: HakoMacSubscriptionUsageCopy.traffic(ConfigurationSubscriptionUsage(
                    upload: usage.uploadBytes, download: usage.downloadBytes, total: usage.totalBytes,
                    expire: usage.expiration.map { Int64($0.timeIntervalSince1970) } ?? 0
                )))
            }
            HStack(spacing: HakoTheme.Spacing.compact) {
                Text(hako: .copy("Updated"))
                Spacer()
                Text(hako: profile.lastUpdatedAt.map { .verbatim(Self.dateFormatters.formatter(for: locale).string(from: $0)) } ?? .copy("Never"))
                    .foregroundStyle(.secondary)
                Button { actions.updateSource() } label: { Text(hako: .copy("Update Source")) }
                    .buttonStyle(.borderless)
                    .disabled(profile.isBusy)
                    .accessibilityIdentifier("configuration-center.config-url.update")
            }
            HStack(spacing: HakoTheme.Spacing.row) {
                Button { actions.copyProfileURL() } label: { Text(hako: .copy("Copy Profile URL")) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("configuration-center.config-url.copy")
                Button { confirmsCredentialRemoval = true } label: { Text(hako: .copy("Remove Stored URL Credentials")) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("configuration-center.config-url.strip")
                Spacer()
            }
            .alert(Text(hako: .copy("Remove Stored URL Credentials")), isPresented: $confirmsCredentialRemoval) {
                Button(role: .destructive) { actions.stripCredentials() } label: { Text(hako: .copy("Remove Stored URL Credentials")) }
                    .accessibilityIdentifier("configuration-center.config-url.strip.confirm")
                Button(role: .cancel) {} label: { Text(hako: .copy("Cancel")) }
            } message: {
                Text(hako: .copy("The saved profile URL carries sign-in details or query values. Removing them keeps the scheme, host and path only, and may require re-importing if the provider needs them."))
            }
        } header: {
            Text(hako: .copy("Profile URL"))
        }
    }

    private var heldBack: some View {
        Section {
            if profile.heldBackUpdates.count > Self.heldBackRowsShownAtOnce {
                Button {
                    showsAllHeldBack.toggle()
                } label: {
                    HStack {
                        Text(hako: .copy("Details"))
                        Spacer()
                        HakoMacTrailingChevron(expanded: showsAllHeldBack)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configuration-center.configuration.held-back.disclosure")
                if showsAllHeldBack { heldBackRows }
            } else {
                heldBackRows
            }
            Button { actions.dismissHeldBack() } label: { Text(hako: .copy("Keep My Settings")) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("configuration-center.configuration.held-back.dismiss")
        } footer: {
            Text(hako: .format(
                "The last update changed %@ setting(s) that your app-wide settings override. Each is shown with the new value; adopt it or keep yours.",
                [String(profile.heldBackUpdates.count)]
            ))
        }
    }

    private var heldBackRows: some View {
        ForEach(profile.heldBackUpdates) { item in
            LabeledContent {
                Button { actions.adoptHeldBack(item.keyPath) } label: {
                    Text(hako: item.change == .removed ? .copy("Follow Removal") : .copy("Use New Value"))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("configuration-center.configuration.held-back.adopt.\(item.keyPath)")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.keyPath).font(.subheadline.monospaced())
                     
                    Text(hako: Self.heldBackLine(item)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("configuration-center.configuration.held-back.item.\(item.keyPath)")
        }
    }

    private static func heldBackLine(_ item: HakoProfileHeldBackUpdate) -> HakoDisplayText {
        switch item.change {
        case .removed: .format("Removed by the profile URL · yours: %@", [item.appValue])
        case .added, .changed: .format("Profile URL now: %@ · yours: %@", [item.newValue ?? "", item.appValue])
        }
    }

    private static let dateFormatters = HakoMacDateFormatterCache(dateStyle: .medium, timeStyle: .short)

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.label else { name = profile.label; return }
        actions.rename(trimmed)
    }
}

 
 
struct HakoMacTrailingChevron: View {
    var expanded: Bool = false

    var body: some View {
        HakoSymbolImage(symbol: .chevronForward)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
    }
}

 
 
 
struct HakoMacPushRowLabel: View {
    let title: HakoDisplayText
    var value: HakoDisplayText? = nil
    init(_ title: HakoDisplayText, value: HakoDisplayText? = nil) { self.title = title; self.value = value }

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            Text(hako: title)
            Spacer()
            if let value { Text(hako: value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail) }
        }
        .contentShape(Rectangle())
    }
}

 
 
 
struct HakoMacValueRow: View {
    let title: HakoDisplayText
    let value: HakoDisplayText
    init(_ title: HakoDisplayText, value: HakoDisplayText) { self.title = title; self.value = value }

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            Text(hako: title)
            Spacer()
            Text(hako: value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

 
struct HakoMacScopeRequest: Identifiable {
    let source: ConfigurationSourceRecord
     
     
     
    var chosen = true
    var id: String { source.id }
}


 

 
 
 
struct HakoMacConfigurationSourceRow: View {
    let source: ConfigurationSourceRecord
    let chosen: Bool
    let toggle: () -> Void
    let inspect: () -> Void

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
             
             
             
             
             
             
             
             
            Toggle(isOn: Binding(get: { chosen }, set: { _ in toggle() })) {
                VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                    Text(verbatim: source.label)
                    Text(hako: .count(source.nodeCount, one: "%@ node", other: "%@ nodes"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(HakoMacCheckboxStyle())
            .accessibilityIdentifier("configuration-center.configuration.source.\(source.id)")
             
             
             
             
             
             
             
             
            HakoMacInfoGlyph(identifier: "configuration-center.configuration.scope.\(source.id)", action: inspect)
                .accessibilityLabel(Text(hako: .copy("Node Collections")))
        }
    }
}

 
 
 
 
 
struct HakoMacConfigurationSchemeRow: View {
    let scheme: ConfigurationRuleScheme
    let chosen: Bool
    let choose: () -> Void
     
    let page: () -> AnyView

    static func line(_ scheme: ConfigurationRuleScheme) -> HakoDisplayText {
        switch scheme.kind {
        case .builtin: .copy("Built-in")
        case .custom: .copy("Custom")
        case .supplied, .imported, .community: .copy("Imported")
        }
    }

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            HakoMacChoiceRow(
                title: .verbatim(scheme.displayLabel),
                subtitle: Self.line(scheme),
                style: .single,
                isSelected: chosen,
                identifier: "configuration-center.configuration.scheme.\(scheme.id)",
                toggle: choose
            )
            HakoMacRoutedInfoButton(identifier: "configuration-center.configuration.scheme-info.\(scheme.id)", page: page)
                .accessibilityLabel(Text(hako: .copy("Rule Scheme")))
        }
    }
}

 
 
 
struct HakoMacConfigurationSourcesPage: View {
    let sources: [ConfigurationSourceRecord]
    @Binding var chosen: Set<String>
    let recipe: ConfigurationRecipe?
    let actions: HakoMacConfigurationInspectorActions
    let toggle: (String) -> Void
    @State private var filter = ""
    @State private var scopeSource: HakoMacScopeRequest?
     
     
     
     
    @State private var writtenScopes: [String: ConfigurationNodeScope?] = [:]

    private func scope(of id: String) -> ConfigurationNodeScope? {
        if let written = writtenScopes[id] { return written }
        return recipe?.nodeScopes?[id]
    }

    private var shown: [ConfigurationSourceRecord] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return sources }
        return sources.filter { $0.label.localizedCaseInsensitiveContains(needle) }
    }

     
     
     
    static func shelves(_ sources: [ConfigurationSourceRecord]) -> [HakoMacNodeLibraryShelf] {
        HakoMacNodeLibraryGroup.allCases.compactMap { group in
            let members = sources.filter { group.contains($0) }
            return members.isEmpty ? nil : HakoMacNodeLibraryShelf(group: group, sources: members)
        }
    }

    var body: some View {
        List {
            ForEach(Self.shelves(shown)) { shelf in
                Section {
                    ForEach(shelf.sources) { source in
                        HakoMacConfigurationSourceRow(
                            source: source, chosen: chosen.contains(source.id),
                            toggle: { toggle(source.id) },
                            inspect: { scopeSource = HakoMacScopeRequest(source: source, chosen: chosen.contains(source.id)) }
                        )
                    }
                } header: {
                    Text(hako: .copy(shelf.group.title))
                }
            }
        }
        .listStyle(.inset)
        .hakoProductModalSearchable(text: $filter, prompt: Text(hako: .copy("Filter")))
        .sheet(item: $scopeSource) { request in
            HakoMacScopeSheet(request: request, initial: scope(of: request.source.id), actions: actions, done: { scope in
                writtenScopes[request.source.id] = .some(scope)
                if scope?.isEmpty == true { chosen.remove(request.source.id) } else { chosen.insert(request.source.id) }
                scopeSource = nil
            }, back: { scopeSource = nil })
        }
    }
}

 
 
struct HakoMacConfigurationSchemesPage: View {
     
     
     
    let shelves: [HakoMacRuleLibraryShelf]
    @Binding var chosen: String
    let choose: (String) -> Void
    let page: (String) -> AnyView
    @State private var filter = ""

    private var shown: [HakoMacRuleLibraryShelf] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return shelves }
        return shelves.compactMap { shelf in
            let members = shelf.schemes.filter { $0.displayLabel.localizedCaseInsensitiveContains(needle) }
            return members.isEmpty ? nil : HakoMacRuleLibraryShelf(section: shelf.section, schemes: members)
        }
    }

    var body: some View {
        List {
            ForEach(shown) { shelf in
                Section {
                    ForEach(shelf.schemes) { scheme in
                        HakoMacConfigurationSchemeRow(
                            scheme: scheme, chosen: scheme.id == chosen,
                            choose: { choose(scheme.id) }, page: { page(scheme.id) }
                        )
                    }
                } header: {
                    Text(hako: .copy(shelf.section.title))
                }
            }
        }
        .listStyle(.inset)
        .hakoProductModalSearchable(text: $filter, prompt: Text(hako: .copy("Filter")))
    }
}

 
 
 
 
 
struct HakoMacScopeSheet: View {
    let request: HakoMacScopeRequest
     
     
    let initial: ConfigurationNodeScope?
    let actions: HakoMacConfigurationInspectorActions
    let done: (ConfigurationNodeScope?) -> Void
    let back: () -> Void

    var body: some View {
        HakoMacNodeScopePage(
            source: request.source,
            load: { [actions] in try await actions.loadScopeChoices(request.source) },
            initial: initial,
            save: { scope in
                actions.setScope(request.source.id, scope)
                done(scope)
            },
            back: back,
            closeTitle: .copy("Cancel"),
            savesUnchanged: !request.chosen
        )
    }
}


 
 
 
 
 
 
struct HakoMacCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                .frame(width: HakoTheme.Control.pointerRowTarget)
            configuration.label
             
             
             
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hakoMacPressableRow { configuration.isOn.toggle() }
    }
}
