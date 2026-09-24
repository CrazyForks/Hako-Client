import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
public struct HakoMacConfigurationInspectorActions {
    public var rename: @MainActor (String) -> Void
    public var setSources: @MainActor ([String]) -> Void
    public var setScheme: @MainActor (String) -> Void
    public var editScheme: @MainActor (String) -> Void
    public var addSource: @MainActor () -> Void
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
    public var loadScopeChoices: @MainActor (ConfigurationSourceRecord) async throws -> HakoMacNodeScopeChoices = { _ in
        throw ConfigurationLibraryError.unreadable
    }

    public init(
        rename: @escaping @MainActor (String) -> Void,
        setSources: @escaping @MainActor ([String]) -> Void,
        setScheme: @escaping @MainActor (String) -> Void,
        editScheme: @escaping @MainActor (String) -> Void,
        addSource: @escaping @MainActor () -> Void,
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
        self.rename = rename; self.setSources = setSources; self.setScheme = setScheme; self.editScheme = editScheme
        self.addSource = addSource; self.activate = activate; self.duplicate = duplicate; self.export = export
        self.editSource = editSource; self.delete = delete
        self.setSourceUpdates = setSourceUpdates; self.openRuntimePreview = openRuntimePreview
        self.restoreLastKnownGood = restoreLastKnownGood
        self.setAutoUpdate = setAutoUpdate; self.setInterval = setInterval; self.updateSource = updateSource
        self.stripCredentials = stripCredentials; self.adoptHeldBack = adoptHeldBack; self.dismissHeldBack = dismissHeldBack
    }

    public static var unavailable: Self {
        Self(
            rename: { _ in }, setSources: { _ in }, setScheme: { _ in }, editScheme: { _ in }, addSource: {},
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
    @State private var showsAllSources = false
    @State private var confirmsCredentialRemoval = false
    @State private var scopeSource: HakoMacScopeRequest?
    @Environment(\.locale) private var locale

    public init(
        profile: HakoProfileSnapshot,
        sources: [ConfigurationSourceRecord],
        schemes: [ConfigurationRuleScheme],
        recipe: ConfigurationRecipe?,
        scriptsActions: HakoMacScriptsActions,
        profileURL: String? = nil,
        actions: HakoMacConfigurationInspectorActions,
        door: @escaping (HakoMacConfigurationDoor) -> AnyView = { _ in AnyView(EmptyView()) }
    ) {
        self.profile = profile
        self.sources = sources
        self.schemes = schemes
        self.recipe = recipe
        self.scriptsActions = scriptsActions
        self.profileURL = profileURL
        self.actions = actions
        self.door = door
        _name = State(initialValue: profile.label)
        _chosenSources = State(initialValue: Set(recipe?.sources.map(\.id) ?? []))
        _chosenScheme = State(initialValue: recipe?.ruleSchemeID ?? "")
    }

    private var isComposed: Bool { recipe != nil }
     
    private static let heldBackRowsShownAtOnce = 8

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                headerCard
                identity
                if isComposed {
                    composition
                    rules
                } else if profile.canEditSource {
                     
                     
                     
                    rules
                }
                if !profile.heldBackUpdates.isEmpty { heldBack }
                overrides
                network
                if profile.source == .remote { profileURLSection }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("configuration-center.configuration")
        }
        .task(id: profile.id) { scripts = await scriptsActions.load() }
    }

     

     
     
    private var headerCard: some View {
        Section {
            HStack(spacing: HakoTheme.Spacing.compact) {
                 
                 
                HStack(spacing: 6) {
                    Circle().fill(profile.isCurrent ? Color.green : Color.secondary).frame(width: 8, height: 8)
                    Text(hako: profile.isCurrent ? .copy("Active") : profile.sourceSummary).lineLimit(1)
                }
                Spacer()
                if !profile.isCurrent {
                    Button { actions.activate() } label: { Text(hako: .copy("Activate")) }
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
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderedButton)
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

     
     
     
     
     
    private var orderedSources: [ConfigurationSourceRecord] {
        sources.filter { chosenSources.contains($0.id) } + sources.filter { !chosenSources.contains($0.id) }
    }

    private static let sourcesShownAtOnce = 6

    private func toggleSource(_ id: String) {
        if chosenSources.contains(id) { chosenSources.remove(id) } else { chosenSources.insert(id) }
        actions.setSources(sources.map(\.id).filter { chosenSources.contains($0) })
    }

    private func sourceRow(_ source: ConfigurationSourceRecord) -> some View {
         
        let chosen = chosenSources.contains(source.id)
        return HStack(spacing: HakoTheme.Spacing.compact) {
            HakoMacChoiceRow(
                title: .verbatim(source.label),
                subtitle: .format("%@ nodes", [String(source.nodeCount)]),
                style: .multiple,
                isSelected: chosen,
                identifier: "configuration-center.configuration.source.\(source.id)",
                toggle: { toggleSource(source.id) }
            )
            if chosen {
                 
                Button { scopeSource = HakoMacScopeRequest(source: source) } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(hako: .copy("Node Collections")))
                    .accessibilityIdentifier("configuration-center.configuration.scope.\(source.id)")
            }
        }
    }

    private var composition: some View {
        Section {
            let ordered = orderedSources
            if ordered.count > Self.sourcesShownAtOnce {
                ForEach(showsAllSources ? ordered : Array(ordered.prefix(Self.sourcesShownAtOnce))) { sourceRow($0) }
                Button {
                    showsAllSources.toggle()
                } label: {
                    HStack {
                        Text(hako: .copy("All Sources"))
                        Spacer()
                        HakoMacTrailingChevron(expanded: showsAllSources)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configuration-center.configuration.sources.disclosure")
            } else {
                ForEach(ordered) { sourceRow($0) }
            }
            Button { actions.addSource() } label: { Text(hako: .copy("Add Source")) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("configuration-center.configuration.add-source")
            if let follows = profile.followsConfigurationSourceUpdates {
                Toggle(isOn: Binding(get: { follows }, set: { actions.setSourceUpdates($0) })) {
                    Text(hako: .copy("Automatically Update Sources"))
                }
                .disabled(profile.isBusy)
                .accessibilityIdentifier("configuration-center.configuration.source-updates")
            }
        } header: {
            Text(hako: .copy("Node Sources"))
        }
    }

    private var rules: some View {
        Section {
            HStack(spacing: HakoTheme.Spacing.compact) {
                Text(hako: .copy("Rule Scheme"))
                Spacer()
                HStack(spacing: HakoTheme.Spacing.compact) {
                    Picker(selection: Binding(
                        get: { chosenScheme },
                        set: { chosenScheme = $0; actions.setScheme($0) }
                    )) {
                        if chosenScheme.isEmpty {
                            Text(hako: .copy("Choose a rule scheme")).tag("")
                        }
                        ForEach(schemes) { scheme in
                            Text(verbatim: scheme.displayLabel).tag(scheme.id)
                        }
                    } label: { EmptyView() }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("configuration-center.configuration.scheme")
                    if !chosenScheme.isEmpty {
                        Button { actions.editScheme(chosenScheme) } label: { Text(hako: .copy("Edit")) }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("configuration-center.configuration.edit-scheme")
                    }
                }
            }
        }
    }

    private var overrides: some View {
        Section {
            HakoRoutedViewLink {
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
            .sheet(item: $scopeSource) { request in
                HakoMacNodeScopePage(
                    source: request.source,
                    load: { [actions] in try await actions.loadScopeChoices(request.source) },
                    initial: recipe?.nodeScopes?[request.source.id],
                    save: { scope in
                        actions.setScope(request.source.id, scope)
                        if scope?.isEmpty == true { chosenSources.remove(request.source.id) }
                        scopeSource = nil
                    },
                    back: { scopeSource = nil }
                )
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
            if let value { Text(hako: value).foregroundStyle(.secondary) }
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
    var id: String { source.id }
}
