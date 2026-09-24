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
    public var openNetwork: @MainActor () -> Void
    public var openTrust: @MainActor () -> Void
    public var setAutoUpdate: @MainActor (Bool) -> Void
    public var setInterval: @MainActor (Int) -> Void
    public var updateSource: @MainActor () -> Void
    public var stripCredentials: @MainActor () -> Void
    public var adoptHeldBack: @MainActor (String) -> Void
    public var dismissHeldBack: @MainActor () -> Void

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
        openNetwork: @escaping @MainActor () -> Void,
        openTrust: @escaping @MainActor () -> Void,
        setAutoUpdate: @escaping @MainActor (Bool) -> Void,
        setInterval: @escaping @MainActor (Int) -> Void,
        updateSource: @escaping @MainActor () -> Void,
        stripCredentials: @escaping @MainActor () -> Void,
        adoptHeldBack: @escaping @MainActor (String) -> Void,
        dismissHeldBack: @escaping @MainActor () -> Void
    ) {
        self.rename = rename; self.setSources = setSources; self.setScheme = setScheme; self.editScheme = editScheme
        self.addSource = addSource; self.activate = activate; self.duplicate = duplicate; self.export = export
        self.editSource = editSource; self.delete = delete; self.openNetwork = openNetwork; self.openTrust = openTrust
        self.setAutoUpdate = setAutoUpdate; self.setInterval = setInterval; self.updateSource = updateSource
        self.stripCredentials = stripCredentials; self.adoptHeldBack = adoptHeldBack; self.dismissHeldBack = dismissHeldBack
    }

    public static var unavailable: Self {
        Self(
            rename: { _ in }, setSources: { _ in }, setScheme: { _ in }, editScheme: { _ in }, addSource: {},
            activate: {}, duplicate: {}, export: {}, editSource: {}, delete: {},
            openNetwork: {}, openTrust: {}, setAutoUpdate: { _ in }, setInterval: { _ in }, updateSource: {},
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
    @State private var name: String
    @State private var chosenSources: Set<String>
    @State private var chosenScheme: String
     
    @State private var scripts = HakoMacScriptsState.empty
    @State private var showsAllHeldBack = false
    @Environment(\.locale) private var locale

    public init(
        profile: HakoProfileSnapshot,
        sources: [ConfigurationSourceRecord],
        schemes: [ConfigurationRuleScheme],
        recipe: ConfigurationRecipe?,
        scriptsActions: HakoMacScriptsActions,
        profileURL: String? = nil,
        actions: HakoMacConfigurationInspectorActions
    ) {
        self.profile = profile
        self.sources = sources
        self.schemes = schemes
        self.recipe = recipe
        self.scriptsActions = scriptsActions
        self.profileURL = profileURL
        self.actions = actions
        _name = State(initialValue: profile.label)
        _chosenSources = State(initialValue: Set(recipe?.sources.map(\.id) ?? []))
        _chosenScheme = State(initialValue: recipe?.ruleSchemeID ?? "")
    }

    private var isComposed: Bool { recipe != nil }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                headerCard
                identity
                if isComposed {
                    composition
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
            .padding(.vertical, 4)
        }
    }

    private var identity: some View {
        Section {
            TextField(text: $name) { Text(hako: .copy("Name")) }
                .onSubmit { commitName() }
                .accessibilityIdentifier("configuration-center.configuration.name")
            LabeledContent { Text(hako: profile.sourceSummary) } label: { Text(hako: .copy("Source")) }
        }
    }

    private var composition: some View {
        Section {
            ForEach(sources) { source in
                Toggle(isOn: Binding(
                    get: { chosenSources.contains(source.id) },
                    set: { on in
                        if on { chosenSources.insert(source.id) } else { chosenSources.remove(source.id) }
                        actions.setSources(sources.map(\.id).filter { chosenSources.contains($0) })
                    }
                )) {
                    HStack(spacing: HakoTheme.Spacing.compact) {
                        Text(verbatim: source.label)
                        Spacer()
                        Text(hako: .format("%@ nodes", [String(source.nodeCount)]))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("configuration-center.configuration.source.\(source.id)")
            }
            Button { actions.addSource() } label: {
                Label { Text(hako: .copy("Add Source")) } icon: { Image(systemName: "plus") }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("configuration-center.configuration.add-source")
        } header: {
            Text(hako: .copy("Node Sources"))
        }
    }

    private var rules: some View {
        Section {
            LabeledContent {
                HStack(spacing: HakoTheme.Spacing.compact) {
                    Picker(selection: Binding(
                        get: { chosenScheme },
                        set: { chosenScheme = $0; actions.setScheme($0) }
                    )) {
                        ForEach(schemes) { scheme in
                            Text(verbatim: scheme.label).tag(scheme.id)
                        }
                    } label: { EmptyView() }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("configuration-center.configuration.scheme")
                    Button { actions.editScheme(chosenScheme) } label: { Text(hako: .copy("Edit")) }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("configuration-center.configuration.edit-scheme")
                }
            } label: {
                Text(hako: .copy("Rule Scheme"))
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
                    HakoMacTrailingChevron()
                }
            }
            .accessibilityIdentifier("configuration-center.configuration.scripts")
        }
    }

    private var network: some View {
        Section {
            HakoMacDoorRow(.copy("Sniffer & NTP"), identifier: "configuration-center.configuration.network") {
                actions.openNetwork()
            }
            HakoMacDoorRow(.copy("Compatibility & Trust"), identifier: "configuration-center.configuration.trust") {
                actions.openTrust()
            }
        } header: {
            Text(hako: .copy("Network"))
        }
    }

    private var profileURLSection: some View {
        Section {
            if let profileURL {
                LabeledContent {
                    Text(verbatim: profileURL).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing)
                } label: {
                    Text(hako: .copy("Profile URL"))
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
            .disabled(!profile.autoUpdate)
            .accessibilityIdentifier("configuration-center.config-url.interval")
            if let usage = profile.subscription {
                LabeledContent {
                    Text(hako: HakoMacSubscriptionUsageCopy.traffic(ConfigurationSubscriptionUsage(
                        upload: usage.uploadBytes, download: usage.downloadBytes, total: usage.totalBytes,
                        expire: usage.expiration.map { Int64($0.timeIntervalSince1970) } ?? 0
                    )))
                } label: {
                    Text(hako: .copy("Traffic"))
                }
            }
            LabeledContent {
                HStack(spacing: HakoTheme.Spacing.compact) {
                    Text(hako: profile.lastUpdatedAt.map { .verbatim(Self.dateFormatters.formatter(for: locale).string(from: $0)) } ?? .copy("Never"))
                    Button { actions.updateSource() } label: { Text(hako: .copy("Update Source")) }
                        .buttonStyle(.borderless)
                        .disabled(profile.isBusy)
                        .accessibilityIdentifier("configuration-center.config-url.update")
                }
            } label: {
                Text(hako: .copy("Updated"))
            }
            HStack {
                Button { actions.stripCredentials() } label: { Text(hako: .copy("Remove Stored URL Credentials")) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("configuration-center.config-url.strip")
                Spacer()
            }
        } header: {
            Text(hako: .copy("Profile URL"))
        }
    }

    private var heldBack: some View {
        Section {
            if profile.heldBackUpdates.count > HakoMacConfigurationDetailSheet.heldBackRowsShownAtOnce {
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
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.keyPath)
                    if let value = item.newValue { Text(verbatim: value).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
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
