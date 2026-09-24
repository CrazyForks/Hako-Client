import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
public struct HakoMacSourceNode: Identifiable, Sendable, Equatable {
    public let index: Int
    public let name: String
    public let type: String
    public let server: String?
    public let json: String
    public var id: Int { index }

    public init(index: Int, name: String, type: String, server: String?, json: String) {
        self.index = index; self.name = name; self.type = type; self.server = server; self.json = json
    }
}

 
 
public struct HakoMacSourceContentActions {
    public var loadNodes: @MainActor () async throws -> [HakoMacSourceNode]
    public var openNode: @MainActor (HakoMacSourceNode) -> Void
     
    public var deleteNode: (@MainActor (HakoMacSourceNode) -> Void)?
    public var addNode: (@MainActor () -> Void)?
    public var update: @MainActor () -> Void
    public var delete: @MainActor () -> Void
    public var editSource: (@MainActor () -> Void)?
    public var editChain: (@MainActor () -> Void)?
     
    public var details: HakoMacSourcePaneActions

    public init(
        loadNodes: @escaping @MainActor () async throws -> [HakoMacSourceNode],
        openNode: @escaping @MainActor (HakoMacSourceNode) -> Void,
        deleteNode: (@MainActor (HakoMacSourceNode) -> Void)? = nil,
        addNode: (@MainActor () -> Void)? = nil,
        update: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void,
        editSource: (@MainActor () -> Void)? = nil,
        editChain: (@MainActor () -> Void)? = nil,
        details: HakoMacSourcePaneActions
    ) {
        self.loadNodes = loadNodes; self.openNode = openNode; self.deleteNode = deleteNode; self.addNode = addNode
        self.update = update; self.delete = delete; self.editSource = editSource; self.editChain = editChain
        self.details = details
    }

    public static var unavailable: Self {
        Self(loadNodes: { [] }, openNode: { _ in }, update: {}, delete: {}, details: .unavailable)
    }
}

 
 
 
 
 
 
public struct HakoMacSourceContentPage: View {
    private let source: ConfigurationSourceRecord
    private let usedBy: [HakoProfileSnapshot]
    private let isUpdating: Bool
    private let collections: [ConfigurationCollectionEntry]
    private let collectionPage: (ConfigurationCollectionEntry) -> AnyView
    private let actions: HakoMacSourceContentActions
     
     
    public var updateError: String?
     
     
     
    public var updateIssue: String?
    @State private var nodes: [HakoMacSourceNode]?
    @State private var loadError: String?
    @State private var filter = ""
    @State private var showsDetails = false
    @State private var deletingNode: HakoMacSourceNode?
    @Environment(\.locale) private var locale

    public init(
        source: ConfigurationSourceRecord, usedBy: [HakoProfileSnapshot], isUpdating: Bool,
        collections: [ConfigurationCollectionEntry] = [],
        collectionPage: @escaping (ConfigurationCollectionEntry) -> AnyView = { _ in AnyView(EmptyView()) },
        actions: HakoMacSourceContentActions
    ) {
        self.source = source; self.usedBy = usedBy; self.isUpdating = isUpdating
        self.collections = collections; self.collectionPage = collectionPage; self.actions = actions
    }

    private var isRetained: Bool { source.isRetainedSnapshot == true }
    private var isSubscription: Bool {
        if isRetained { return false }
        if case .subscription = source.origin { return true }
        return false
    }
    private var isChain: Bool { source.nodeChain != nil }
     
    private var isBundled: Bool {
        if case .bundled = source.origin { return true }
        return false
    }

    private var shownNodes: [HakoMacSourceNode] {
        guard let nodes else { return [] }
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nodes }
        return nodes.filter {
            $0.name.lowercased().contains(needle) || $0.type.lowercased().contains(needle) || ($0.server?.lowercased().contains(needle) ?? false)
        }
    }

    public var body: some View {
        HakoMacCardPage {
            headerCard
            if let chain = source.nodeChain {
                 
                 
                HakoMacCardSection(.copy("Connection Order")) {
                    HakoMacValueRow(.copy("This Device"), value: .verbatim("")).hakoMacCardRow(isLast: false)
                    chainHopRow(.copy("Entry Node"), node: chain.entry.nodeName).hakoMacCardRow(isLast: false)
                    chainHopRow(.copy("Exit Node"), node: chain.exit.nodeName).hakoMacCardRow(isLast: false)
                    HakoMacValueRow(.copy("Destination Website"), value: .verbatim("")).hakoMacCardRow(isLast: true)
                }
            } else {
                nodesCard
                if let addNode = actions.addNode {
                    HakoMacCardButtons { EmptyView() } trailing: {
                        Button { addNode() } label: { Text(hako: .opens("Add Custom Node", locale: locale)) }
                            .accessibilityIdentifier("configuration-center.source.add-node")
                    }
                }
                if !collections.isEmpty {
                    HakoMacCardSection(.format("Node Sets (%@)", [String(collections.count)])) {
                        ForEach(Array(collections.enumerated()), id: \.element.id) { index, entry in
                            HakoMacRoutedRow {
                                collectionPage(entry)
                            } label: {
                                HakoMacSettingsRow(
                                    title: .verbatim(entry.collection.name),
                                    status: entry.memberCount.map { .format("%@ nodes", [String($0)]) } ?? .verbatim(entry.collection.type),
                                    statusTint: nil, trailing: nil, busy: false
                                )
                            }
                            .accessibilityIdentifier("configuration-center.source.collection.\(entry.collection.name)")
                            .hakoMacCardRow(isLast: index == collections.count - 1)
                        }
                    }
                }
            }
            readers
        }
        .accessibilityIdentifier("configuration-center.source")
         
         
         
        .hakoProductModalSearchable(text: $filter, prompt: Text(hako: .copy("Search Nodes")))
        .task(id: source.version) { await load() }
        .sheet(isPresented: $showsDetails) {
            HakoMacSourceDetailsSheet(source: source, usedBy: usedBy, actions: actions.details, close: { showsDetails = false })
                .hakoModalPresentation(.fitted)
        }
        .alert(Text(hako: .copy("Delete Node")), isPresented: Binding(get: { deletingNode != nil }, set: { if !$0 { deletingNode = nil } })) {
            Button(role: .destructive) {
                if let deletingNode { actions.deleteNode?(deletingNode) }
                deletingNode = nil
            } label: {
                Text(hako: .copy("Delete Node"))
            }
            .accessibilityIdentifier("configuration-center.source.delete-node.confirm")
            Button(role: .cancel) {} label: { Text(hako: .copy("Cancel")) }
        } message: {
            Text(hako: .copy("This node will be removed from the source and profiles that follow its updates."))
        }
    }

    private func chainHopRow(_ title: HakoDisplayText, node: String) -> some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            HakoSymbolImage(symbol: .arrowDown).foregroundStyle(.secondary)
            Text(hako: title)
            Spacer()
            Text(verbatim: node).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }

    private var headerCard: some View {
        HakoMacCardSection {
            VStack(alignment: .leading, spacing: 6) {
                headerRow
                if isRetained {
                     
                    Text(hako: .copy("This saved copy no longer receives source updates."))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("configuration-center.source.retained")
                }
                if let updateError {
                    Text(verbatim: updateError)
                        .font(.footnote).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("configuration-center.source.update-error")
                }
                if let updateIssue {
                    Text(verbatim: updateIssue)
                        .font(.footnote).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("configuration-center.source.update-issue")
                }
            }
            .padding(.vertical, 4)
            .hakoMacCardRow(isLast: true)
        }
    }

    private var headerRow: some View {
            HStack(spacing: HakoTheme.Spacing.compact) {
                 
                Text(hako: isChain ? .copy("Proxy Chain") : isRetained ? .copy("Saved Copy") : .count(source.nodeCount, one: "%@ node", other: "%@ nodes")).lineLimit(1)
                Text(verbatim: "·").foregroundStyle(.secondary)
                Text(verbatim: Self.dateFormatters.formatter(for: locale).string(from: source.updatedAt)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if isUpdating { ProgressView().controlSize(.small) }
                if isSubscription {
                    Button { actions.update() } label: { Text(hako: .copy("Update Source")) }
                        .disabled(isUpdating)
                        .accessibilityIdentifier("configuration-center.source.update")
                }
                if let editChain = actions.editChain {
                    Button { editChain() } label: { Text(hako: .copy("Edit")) }
                        .accessibilityIdentifier("configuration-center.source.edit-chain")
                }
                Menu {
                    Button { showsDetails = true } label: { Text(hako: .copy("Source Details")) }
                    if let editSource = actions.editSource, !isRetained, !isChain {
                        Button { editSource() } label: { Text(hako: .copy("Edit Nodes Source")) }
                    }
                    if !isRetained && !isBundled {
                        Divider()
                         
                         
                         
                         
                        Button(role: .destructive) { actions.delete() } label: {
                            Text(hako: isChain ? .copy("Delete Proxy Chain") : .copy("Delete"))
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderedButton).fixedSize()
                .accessibilityIdentifier("configuration-center.source.more")
            }
            .tint(.primary)
    }

    @ViewBuilder
    private var nodesCard: some View {
        let shown = shownNodes
        HakoMacCardSection(.copy("Nodes")) {
            if let loadError {
                Text(verbatim: loadError).foregroundStyle(.red).hakoMacCardRow(isLast: true)
                    .accessibilityIdentifier("configuration-center.source.error")
            } else if nodes == nil {
                ProgressView().controlSize(.small).hakoMacCardRow(isLast: true)
            } else if shown.isEmpty {
                Text(hako: .copy("None")).foregroundStyle(.secondary).hakoMacCardRow(isLast: true)
            } else {
                 
                 
                 
                LazyVStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, node in
                        HakoMacSettingsRow(
                            title: .verbatim(node.name),
                            status: .verbatim([node.type, node.server].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")),
                            statusTint: nil, trailing: nil, busy: false
                        )
                        .hakoMacPressableRow { actions.openNode(node) }
                        .contextMenu {
                            if actions.deleteNode != nil {
                                Button(role: .destructive) { deletingNode = node } label: { Text(hako: .copy("Delete Node")) }
                            }
                        }
                        .accessibilityIdentifier("configuration-center.source.node.\(node.index)")
                        .hakoMacCardRow(isLast: index == shown.count - 1)
                    }
                }
            }
        }
    }

    private var readers: some View {
        HakoMacCardSection(.copy("Used by Profiles")) {
            if usedBy.isEmpty {
                Text(hako: .copy("None")).foregroundStyle(.secondary).hakoMacCardRow(isLast: true)
            } else {
                 
                ForEach(Array(usedBy.enumerated()), id: \.element.id) { index, profile in
                    Text(verbatim: profile.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("configuration-center.source.used-by.\(profile.id.rawValue)")
                        .hakoMacCardRow(isLast: index == usedBy.count - 1)
                }
            }
        }
    }

    private func load() async {
        loadError = nil
        do { nodes = try await actions.loadNodes() } catch { loadError = error.localizedDescription }
    }

    private static let dateFormatters = HakoMacDateFormatterCache(dateStyle: .medium, timeStyle: .short)
}

 
 
 
 
public struct HakoMacSourceDetailsSheet: View {
    private static let intervals = [1, 3, 6, 12, 24, 48, 72, 168]

    private let source: ConfigurationSourceRecord
    private let usedBy: [HakoProfileSnapshot]
    private let actions: HakoMacSourcePaneActions
    private let close: () -> Void
    @State private var name: String
    @State private var url: String
    @State private var interval: Int
    @State private var error: String?
    @Environment(\.locale) private var locale

    public init(source: ConfigurationSourceRecord, usedBy: [HakoProfileSnapshot], actions: HakoMacSourcePaneActions, close: @escaping () -> Void) {
        self.source = source; self.usedBy = usedBy; self.actions = actions; self.close = close
        _name = State(initialValue: source.label)
        let draft = ConfigurationSourceSettingsDraft(source: source)
        _url = State(initialValue: draft.url)
        _interval = State(initialValue: draft.intervalHours)
    }

    private var isRetained: Bool { source.isRetainedSnapshot == true }
    private var isSubscription: Bool {
        if isRetained { return false }
        if case .subscription = source.origin { return true }
        return false
    }
    private var dirty: Bool {
        let draft = ConfigurationSourceSettingsDraft(source: source)
        return name.trimmingCharacters(in: .whitespacesAndNewlines) != source.label
            || (isSubscription && (url.trimmingCharacters(in: .whitespacesAndNewlines) != draft.url || interval != draft.intervalHours))
    }
    private var urlIsValid: Bool {
        guard isSubscription else { return true }
        let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
        return components?.scheme != nil && !(components?.host?.isEmpty ?? true) && components?.url != nil
    }

    public var body: some View {
        HakoMacSheetFrame(title: .copy("Source Details"), subtitle: .verbatim(source.label), width: 560, height: 520) {
            HakoMacSheetForm {
                Section {
                    TextField(text: $name) { Text(hako: .copy("Name")) }
                        .disabled(isRetained)
                        .accessibilityIdentifier("configuration-center.source.name")
                    switch source.origin {
                    case .file(let fileName), .bundled(let fileName):
                        if fileName != source.label { HakoMacValueRow(.copy("Source"), value: .verbatim(fileName)) }
                    case .customNodes:
                        HakoMacValueRow(.copy("Source"), value: .copy("Custom Nodes"))
                    default:
                        EmptyView()
                    }
                }
                if let usage = source.subscriptionUsage {
                    Section {
                        HakoMacValueRow(.copy("Traffic"), value: HakoMacSubscriptionUsageCopy.traffic(usage))
                        if let expiry = HakoMacSubscriptionUsageCopy.expiry(usage, locale: locale) {
                            Text(hako: expiry).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(hako: .copy("Data Usage"))
                    }
                }
                if isSubscription {
                    Section {
                        TextField(text: $url) { Text(hako: .copy("Profile URL")) }
                            .accessibilityIdentifier("configuration-center.source.url")
                        Picker(selection: $interval) {
                            Text(hako: .copy("Manually")).tag(0)
                            ForEach(Self.intervals, id: \.self) { hours in
                                Text(hako: .format("Every %@ hours", [String(hours)])).tag(hours)
                            }
                            if interval != 0, !Self.intervals.contains(interval) {
                                Text(hako: .format("Every %@ hours", [String(interval)])).tag(interval)
                            }
                        } label: {
                            Text(hako: .copy("Update Interval"))
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("configuration-center.source.interval")
                    } header: {
                        Text(hako: .copy("Profile URL"))
                    }
                }
                if isRetained {
                    Section { Text(hako: .copy("This saved copy no longer receives source updates.")).foregroundStyle(.secondary) }
                }
                Section {
                    if usedBy.isEmpty {
                        Text(hako: .copy("None")).foregroundStyle(.secondary)
                    } else {
                        ForEach(usedBy) { profile in Text(verbatim: profile.label) }
                    }
                } header: {
                    Text(hako: .copy("Used by Profiles"))
                }
            }
        } leading: {
            if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.source.error")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.source.close",
                primaryTitle: .copy("OK"),
                primaryIdentifier: "configuration-center.source.save",
                primaryDisabled: !dirty || !urlIsValid || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onClose: close,
                onPrimary: commit
            )
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings: ConfigurationSourceSettingsDraft?
        if isSubscription {
            var draft = ConfigurationSourceSettingsDraft(source: source)
            let nextURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if nextURL != draft.url || interval != draft.intervalHours {
                draft.url = nextURL; draft.intervalHours = interval
                settings = draft
            }
        }
         
        if trimmed != source.label || settings != nil { actions.save(trimmed, settings) }
        close()
    }
}
