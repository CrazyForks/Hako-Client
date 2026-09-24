import HakoClientKit
import HakoClientUI
import SwiftUI

 
public enum HakoMacConfigurationCenterItem: Hashable, Sendable {
    case configuration(Profile.ID)
    case source(String)
    case scheme(String)
     
    case collection(ConfigurationCollection.ID)
}

 
public struct HakoMacConfigurationCenterListActions {
     
     
     
    public var addConfiguration: @MainActor () -> Void
    public var addSource: @MainActor (HakoMacSourceImportSheet.Tab) -> Void
    public var addScheme: @MainActor (HakoMacSourceImportSheet.Tab) -> Void
     
    public var addChain: @MainActor () -> Void = {}
     
    public var backupPage: (@MainActor () -> AnyView)? = nil
    public var activate: @MainActor (Profile.ID) -> Void
    public var delete: @MainActor (HakoMacConfigurationCenterItem) -> Void
     
    public var reorder: (@MainActor ([Profile.ID]) -> Void)? = nil
     
    public var hasLegacyProfileURLs: Bool = false
     
    public var statusMessage: HakoDisplayText? = nil
     
    public var failure: (message: HakoDisplayText, canRetry: Bool)? = nil
    public var retryFailure: @MainActor () -> Void = {}

    public init(
        addConfiguration: @escaping @MainActor () -> Void,
        addSource: @escaping @MainActor (HakoMacSourceImportSheet.Tab) -> Void,
        addScheme: @escaping @MainActor (HakoMacSourceImportSheet.Tab) -> Void,
        activate: @escaping @MainActor (Profile.ID) -> Void,
        delete: @escaping @MainActor (HakoMacConfigurationCenterItem) -> Void
    ) {
        self.addConfiguration = addConfiguration
        self.addSource = addSource
        self.addScheme = addScheme
        self.activate = activate
        self.delete = delete
    }

    public static var unavailable: Self {
        Self(addConfiguration: {}, addSource: { _ in }, addScheme: { _ in }, activate: { _ in }, delete: { _ in })
    }
}

 
 
 
 
 
 
 
public struct HakoMacConfigurationCenterListPage<Detail: View>: View {
    private let segment: HakoMacConfigurationCenterSegment
    @ObservedObject private var model: HakoMacConfigurationLibraryModel
    private let profiles: [HakoProfileSnapshot]
    @Binding private var pendingDelete: HakoMacConfigurationCenterItem?
    private let actions: HakoMacConfigurationCenterListActions
    private let detail: (HakoMacConfigurationCenterItem) -> Detail

    public init(
        segment: HakoMacConfigurationCenterSegment,
        model: HakoMacConfigurationLibraryModel,
        profiles: [HakoProfileSnapshot],
        pendingDelete: Binding<HakoMacConfigurationCenterItem?> = .constant(nil),
        actions: HakoMacConfigurationCenterListActions,
        @ViewBuilder detail: @escaping (HakoMacConfigurationCenterItem) -> Detail
    ) {
        self.segment = segment
        self.model = model
        self.profiles = profiles
        _pendingDelete = pendingDelete
        self.actions = actions
        self.detail = detail
    }

     
    private var rowsShownAtOnce: Int { 24 }
    @State private var expandedShelves: Set<String> = []
    @State private var expandedNodeSets: Set<String> = []
    @State private var expandedRuleSets: Set<String> = []
    @Environment(\.locale) private var locale

    public var body: some View {
        HakoMacCardPage {
            switch segment {
            case .configurations: configurationRows
            case .nodes: sourceRows
            case .rules: schemeRows
            }
            updateStatusLines
        }
        .alert(
            Text(hako: .copy("Update Conflict")),
            isPresented: Binding(get: { model.ruleConflictSourceID != nil }, set: { if !$0 { model.dismissRuleConflict() } })
        ) {
             
             
            Button(role: .destructive) {
                if let id = model.ruleConflictSourceID {
                    model.dismissRuleConflict()
                    Task { _ = await model.updateSource(id, replacingRules: true) }
                }
            } label: {
                Text(hako: .copy("Use Profile URL Rules"))
            }
            .accessibilityIdentifier("configuration-center.update-conflict.replace")
            Button(role: .cancel) { model.dismissRuleConflict() } label: { Text(hako: .copy("Cancel")) }
                .accessibilityIdentifier("configuration-center.update-conflict.cancel")
        } message: {
            Text(hako: .copy("Your rule edits conflict with this update. Use the profile URL rules to replace your edits, or cancel to keep the current profile. You can copy your rule scheme before updating."))
        }
        .alert(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(role: .destructive) {
                if let pendingDelete { actions.delete(pendingDelete) }
                pendingDelete = nil
            } label: {
                Text(hako: .copy("Delete"))
            }
            .accessibilityIdentifier("configuration-center.delete.confirm")
            Button(role: .cancel) {} label: { Text(hako: .copy("Cancel")) }
        } message: {
            Text(hako: deleteMessage)
        }
        .modifier(HakoMacCenterListIdentifier(segment: segment))
    }

     
     
     
     
    private var updateIssuesLine: String? {
        let issues = model.snapshot.updateIssues ?? []
        guard !issues.isEmpty else { return nil }
        let names = issues.map { issue in
            model.snapshot.recipes.first { $0.id == issue.itemID }?.label
                ?? model.snapshot.sources.first { $0.id == issue.itemID }?.label ?? issue.itemID
        }
        return HakoCopy.string("Some references are unavailable. Previous versions were kept:", locale: locale) + " " + names.joined(separator: ", ")
    }

    @ViewBuilder
    private var listStatusLines: some View {
        if let failure = actions.failure {
            HStack(spacing: HakoTheme.Spacing.compact) {
                Text(hako: failure.message).font(.subheadline).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if failure.canRetry {
                    Button { actions.retryFailure() } label: { Text(hako: .copy("Try Again")) }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("configuration-center.configurations.retry")
                }
                Spacer()
            }
            .accessibilityIdentifier("configuration-center.configurations.failure")
        } else if let status = actions.statusMessage, !HakoCopy.string(for: status, locale: locale).isEmpty {
            Text(hako: status).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("configuration-center.configurations.status")
        }
    }

    @ViewBuilder
    private var updateStatusLines: some View {
         
         
         
         
         
        if segment == .configurations,
           actions.failure != nil || (model.updateProgress == nil && model.updateStatus == nil && model.updateError == nil) {
            listStatusLines
        }
        if segment != .configurations, let issues = updateIssuesLine {
            let line = Text(verbatim: issues).font(.subheadline).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch segment {
            case .configurations: line.accessibilityIdentifier("configuration-center.configurations.update-issues")
            case .nodes: line.accessibilityIdentifier("configuration-center.nodes.update-issues")
            case .rules: line.accessibilityIdentifier("configuration-center.rules.update-issues")
            }
        }
        if model.updateProgress != nil || model.updateStatus != nil || model.updateError != nil {
            switch segment {
            case .configurations: updateStatusBody.accessibilityIdentifier("configuration-center.configurations.update-status")
            case .nodes: updateStatusBody.accessibilityIdentifier("configuration-center.nodes.update-status")
            case .rules: updateStatusBody.accessibilityIdentifier("configuration-center.rules.update-status")
            }
        }
    }

    private var updateStatusBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress = model.updateProgress {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: progress).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                if let status = model.updateStatus {
                    Text(verbatim: status).font(.subheadline).foregroundStyle(.secondary)
                }
                if let error = model.updateError {
                    Text(verbatim: error).font(.subheadline).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

     

     
     
     
    @ViewBuilder
    private var configurationRows: some View {
        HakoMacCardSection {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                HStack(spacing: HakoTheme.Spacing.compact) {
                     
                     
                    Button {
                        actions.activate(profile.id)
                    } label: {
                        HakoSymbolImage(symbol: profile.isCurrent ? .checkmarkCircleFill : .circle)
                            .foregroundStyle(profile.isCurrent ? Color.accentColor : Color.secondary)
                            .frame(width: HakoTheme.Control.pointerRowTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(profile.isCurrent || profile.isBusy)
                    .accessibilityLabel(Text(hako: .copy("Activate")))
                    .accessibilityIdentifier("configuration-center.configurations.select.\(profile.id.rawValue)")
                    HakoMacRoutedRow {
                        detail(.configuration(profile.id))
                    } label: {
                         
                         
                         
                         
                         
                         
                        HakoMacSettingsRow(
                            title: .verbatim(profile.label),
                            status: nil,
                            statusTint: nil,
                            trailing: nil,
                            busy: profile.isBusy
                        )
                    }
                    .accessibilityIdentifier("configuration-center.configurations.row.\(profile.id.rawValue)")
                }
                .contextMenu {
                    if !profile.isCurrent {
                        Button { actions.activate(profile.id) } label: { Text(hako: .copy("Activate")) }
                    }
                    if let reorder = actions.reorder, profiles.count > 1 {
                        Divider()
                        Button { reorder(Self.order(profiles, moving: profile.id, by: -1)) } label: { Text(hako: .copy("Move Up")) }
                            .disabled(index == 0)
                        Button { reorder(Self.order(profiles, moving: profile.id, by: 1)) } label: { Text(hako: .copy("Move Down")) }
                            .disabled(index == profiles.count - 1)
                    }
                    Divider()
                    Button(role: .destructive) { pendingDelete = .configuration(profile.id) } label: { Text(hako: .copy("Delete")) }
                }
                 
                 
                .accessibilityElement(children: .contain)
                .hakoMacCardRow(isLast: index == profiles.count - 1)
            }
            if profiles.isEmpty {
                Text(hako: .copy("None")).foregroundStyle(.secondary).hakoMacCardRow(isLast: true)
            }
        }
        HakoMacCardButtons {
             
             
            if model.hasLinkedContent(legacyProfiles: actions.hasLegacyProfileURLs) {
                Button { Task { await model.updateEverything() } } label: { Text(hako: .copy("Update All")) }
                    .disabled(model.isBusy || !model.updatingSourceIDs.isEmpty || model.isUpdatingAll)
                    .accessibilityIdentifier("configuration-center.configurations.update-all")
            }
        } trailing: {
             
            Button { actions.addConfiguration() } label: { Text(hako: .opens("Add Profile", locale: locale)) }
                .accessibilityIdentifier("configuration-center.configurations.add")
        }
        if let backupPage = actions.backupPage {
            HakoMacCardSection(.copy("Data")) {
                HakoMacRoutedRow {
                    backupPage()
                } label: {
                    HakoMacSettingsRow(title: .copy("iCloud Backup & Restore"), status: nil, statusTint: nil, trailing: nil, busy: false)
                }
                .accessibilityIdentifier("configuration-center.configurations.backup")
                .hakoMacCardRow(isLast: true)
            }
        }
    }

     
     
     
    private func nodeRows(_ shelf: HakoMacNodeLibraryShelf) -> [HakoMacNodeLibraryRowItem] {
        shelf.sources.flatMap { source -> [HakoMacNodeLibraryRowItem] in
            let children = model.collections(for: source.id)
            guard !children.isEmpty else { return [.source(source)] }
             
             
            var rows: [HakoMacNodeLibraryRowItem] = [.source(source), .nodeSets(source, children.count)]
            if expandedNodeSets.contains(source.id) { rows += children.map { .collection($0) } }
            return rows
        }
    }

    @ViewBuilder
    private var sourceRows: some View {
        ForEach(model.nodeShelves) { shelf in
            let rows = nodeRows(shelf)
            let expanded = expandedShelves.contains(shelf.id) || rows.count <= rowsShownAtOnce
            let shown = expanded ? rows : Array(rows.prefix(rowsShownAtOnce))
            HakoMacCardSection(.copy(shelf.group.title)) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    HakoMacNodeLibraryRow(
                        item: item, isUpdating: model.updatingSourceIDs.contains(item.sourceID),
                        isExpanded: expandedNodeSets.contains(item.sourceID), detail: detail
                    ) {
                        Task { _ = await model.updateSource(item.sourceID) }
                    } delete: {
                        pendingDelete = .source(item.sourceID)
                    } toggleNodeSets: {
                        if expandedNodeSets.contains(item.sourceID) { expandedNodeSets.remove(item.sourceID) } else { expandedNodeSets.insert(item.sourceID) }
                    }
                    .hakoMacCardRow(isLast: expanded && index == shown.count - 1)
                }
                if !expanded {
                    HakoMacShowAllRow(title: .copy("All Sources"), identifier: "configuration-center.nodes.show-all") {
                        expandedShelves.insert(shelf.id)
                    }
                    .hakoMacCardRow(isLast: true)
                }
            }
        }
        if model.nodeShelves.isEmpty {
            HakoMacCardSection { Text(hako: .copy("None")).foregroundStyle(.secondary).hakoMacCardRow(isLast: true) }
        }
        HakoMacCardButtons {
             
            Button { Task { await model.updateAllSources() } } label: { Text(hako: .copy("Update All Sources")) }
                .disabled(model.isBusy || !model.updatingSourceIDs.isEmpty || model.isUpdatingAll)
                .accessibilityIdentifier("configuration-center.nodes.update-all")
        } trailing: {
            Menu {
                Button { actions.addSource(.link) } label: { Text(hako: .copy("Profile URL")) }
                Button { actions.addSource(.file) } label: { Text(hako: .copy("File")) }
                Button { actions.addSource(.nodes) } label: { Text(hako: .copy("Nodes")) }
                Button { actions.addChain() } label: { Text(hako: .copy("Proxy Chain")) }
            } label: {
                Text(hako: .opens("Add Source", locale: locale))
            }
            .fixedSize()
            .accessibilityIdentifier("configuration-center.nodes.add")
        }
    }

     
     
     
    private func ruleRows(_ shelf: HakoMacRuleLibraryShelf) -> [HakoMacRuleLibraryRowItem] {
        shelf.schemes.flatMap { scheme -> [HakoMacRuleLibraryRowItem] in
            let sets = model.collections(for: scheme.sourceID, kind: .rules)
            guard !sets.isEmpty else { return [.scheme(scheme)] }
            var rows: [HakoMacRuleLibraryRowItem] = [.scheme(scheme), .ruleSets(scheme, sets.count)]
            if expandedRuleSets.contains(scheme.id) { rows += sets.map { .collection(scheme, $0) } }
            return rows
        }
    }

     
    private struct RuleRowWords {
        let builtIn: String
        let usedBy: (one: String, other: String)
        let rules: (one: String, other: String)
    }

    @ViewBuilder
    private var schemeRows: some View {
         
         
         
        let linked = linkedSourceIDs
        let ruleCounts = Dictionary(model.snapshot.sources.map { ($0.id, $0.ruleCount) }, uniquingKeysWith: { first, _ in first })
        let words = RuleRowWords(
            builtIn: HakoCopy.string("Built-in", locale: locale),
            usedBy: (one: HakoCopy.string("Used by %@ profile", locale: locale), other: HakoCopy.string("Used by %@ profiles", locale: locale)),
            rules: (one: HakoCopy.string("%@ rule", locale: locale), other: HakoCopy.string("%@ rules", locale: locale))
        )
        ForEach(model.ruleShelves) { shelf in
            let rows = ruleRows(shelf)
            HakoMacCardSection(.copy(shelf.section.title)) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    ruleRow(item, linked: linked, ruleCounts: ruleCounts, words: words)
                        .hakoMacCardRow(isLast: index == rows.count - 1)
                }
            }
        }
        HakoMacCardButtons {
            Button { Task { await model.updateAllRuleSets() } } label: { Text(hako: .copy("Update All Rule Sets")) }
                .disabled(model.isBusy || !model.updatingSourceIDs.isEmpty || model.isUpdatingAll)
                .accessibilityIdentifier("configuration-center.rules.update-all")
        } trailing: {
            Menu {
                Button { actions.addScheme(.link) } label: { Text(hako: .copy("Profile URL")) }
                Button { actions.addScheme(.file) } label: { Text(hako: .copy("File")) }
                Button { actions.addScheme(.manual) } label: { Text(hako: .copy("Manual")) }
            } label: {
                Text(hako: .opens("Add Rule Scheme", locale: locale))
            }
            .fixedSize()
            .accessibilityIdentifier("configuration-center.rules.add")
        }
    }

     
     
     
    private func schemeStatus(
        _ scheme: ConfigurationRuleScheme, ruleCounts: [String: Int], words: RuleRowWords
    ) -> HakoDisplayText {
        var parts: [String] = []
        if scheme.kind == .builtin {
            parts.append(words.builtIn)
        } else {
            let usage = model.usageCount(ofScheme: scheme.id)
            parts.append((usage == 1 ? words.usedBy.one : words.usedBy.other).replacingOccurrences(of: "%@", with: String(usage)))
        }
        if let ruleCount = ruleCounts[scheme.sourceID], ruleCount > 0 {
            parts.append((ruleCount == 1 ? words.rules.one : words.rules.other).replacingOccurrences(of: "%@", with: String(ruleCount)))
        }
        return .verbatim(parts.joined(separator: " · "))
    }

     
    private var linkedSourceIDs: Set<String> {
        Set(model.snapshot.sources.compactMap { source in
            if case .subscription = source.origin { return source.id }
            return nil
        })
    }

    @ViewBuilder
    private func ruleRow(
        _ item: HakoMacRuleLibraryRowItem, linked: Set<String>, ruleCounts: [String: Int],
        words: RuleRowWords
    ) -> some View {
        switch item {
        case .scheme(let scheme):
            HakoMacRoutedRow {
                detail(.scheme(scheme.id))
            } label: {
                HakoMacSettingsRow(
                    title: .verbatim(scheme.displayLabel),
                    status: schemeStatus(scheme, ruleCounts: ruleCounts, words: words),
                    statusTint: nil,
                    trailing: nil,
                    busy: model.updatingSourceIDs.contains(scheme.sourceID)
                )
            }
            .contextMenu {
                 
                 
                 
                if linked.contains(scheme.sourceID) {
                    Button { Task { _ = await model.updateSource(scheme.sourceID) } } label: { Text(hako: .copy("Refresh Rules")) }
                }
                if scheme.canBeDeleted {
                    Divider()
                    Button(role: .destructive) { pendingDelete = .scheme(scheme.id) } label: { Text(hako: .copy("Delete")) }
                }
            }
            .accessibilityIdentifier("configuration-center.rules.row.\(scheme.id)")
        case .ruleSets(let scheme, let count):
            HStack(spacing: HakoTheme.Spacing.compact) {
                Text(hako: .format("Rule Sets (%@)", [String(count)])).font(.subheadline)
                Spacer()
                HakoMacTrailingChevron(expanded: expandedRuleSets.contains(scheme.id))
            }
            .padding(.leading, HakoTheme.Control.pointerRowTarget)
            .hakoMacPressableRow {
                if expandedRuleSets.contains(scheme.id) { expandedRuleSets.remove(scheme.id) } else { expandedRuleSets.insert(scheme.id) }
            }
            .accessibilityIdentifier("configuration-center.rules.rule-sets.\(scheme.id)")
        case .collection(_, let entry):
            HakoMacRoutedRow {
                detail(.collection(entry.id))
            } label: {
                HakoMacSettingsRow(
                    title: .verbatim(entry.collection.name),
                    status: entry.memberCount.map { .count($0, one: "%@ rule", other: "%@ rules") } ?? .verbatim(entry.collection.type),
                    statusTint: nil, trailing: nil, busy: false
                )
                .padding(.leading, HakoTheme.Control.pointerRowTarget)
            }
            .accessibilityIdentifier("configuration-center.rules.collection.\(entry.source.id).\(entry.collection.name)")
        }
    }


     

     
    static func order(_ profiles: [HakoProfileSnapshot], moving id: Profile.ID, by offset: Int) -> [Profile.ID] {
        var ids = profiles.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return ids }
        ids.swapAt(index, index + offset)
        return ids
    }

    private func isChain(_ sourceID: String) -> Bool {
        model.snapshot.sources.first { $0.id == sourceID }?.nodeChain != nil
    }

    private var deleteTitle: Text {
        switch pendingDelete {
        case .source(let id): isChain(id) ? Text(hako: .copy("Delete Proxy Chain")) : Text(hako: .copy("Delete Source"))
        case .scheme: Text(hako: .copy("Delete Rule Scheme"))
        case .configuration, .collection, nil: Text(hako: .copy("Delete Profile"))
        }
    }

    private var deleteMessage: HakoDisplayText {
        switch pendingDelete {
         
        case .source(let id): isChain(id)
            ? .copy("Saved profiles keep this chain. Its original nodes remain in the library.")
            : .copy("Saved profiles keep their current content and stop following this source.")
        case .scheme: .copy("Saved profiles keep their current rules and stop following this scheme.")
        case .configuration: .copy("This profile will be deleted. Sources and rule schemes in the library will remain.")
        case .collection, nil: .verbatim("")
        }
    }
}

 
 
 
struct HakoMacSettingsRow: View {
    let title: HakoDisplayText
    let status: HakoDisplayText?
    let statusTint: Color?
    let trailing: HakoDisplayText?
    let busy: Bool
     
     
    var usage: ConfigurationSubscriptionUsage? = nil

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hako: title).lineLimit(1)
                if let status {
                    HStack(spacing: 5) {
                        if let statusTint { Circle().fill(statusTint).frame(width: 7, height: 7) }
                        Text(hako: status).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let usage { HakoMacUsageLines(usage: usage) }
            }
            Spacer(minLength: HakoTheme.Spacing.row)
            if busy {
                ProgressView().controlSize(.small)
            } else if let trailing {
                Text(hako: trailing).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
             
            HakoSymbolImage(symbol: .chevronForward)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

 
 
 
 
 
 
public struct HakoMacObservedLibraryPage<Content: View>: View {
    @ObservedObject private var model: HakoMacConfigurationLibraryModel
    private let content: (HakoMacConfigurationLibraryModel) -> Content

    public init(model: HakoMacConfigurationLibraryModel, @ViewBuilder content: @escaping (HakoMacConfigurationLibraryModel) -> Content) {
        self.model = model
        self.content = content
    }

    public var body: some View { content(model) }
}

 
 
 
struct HakoMacPopsWhenGone: ViewModifier {
    let gone: Bool
    @State private var dismiss = HakoDismissHandle()

    func body(content: Content) -> some View {
        content
            .hakoCapturesDismiss(dismiss)
            .onChange(of: gone) { value in if value { dismiss() } }
    }
}

public extension View {
    func hakoMacPopsWhenGone(_ gone: Bool) -> some View {
        modifier(HakoMacPopsWhenGone(gone: gone))
    }
}

 
 
private struct HakoMacCenterListIdentifier: ViewModifier {
    let segment: HakoMacConfigurationCenterSegment

    @ViewBuilder
    func body(content: Content) -> some View {
        switch segment {
        case .configurations: content.accessibilityIdentifier("configuration-center.configurations")
        case .nodes: content.accessibilityIdentifier("configuration-center.nodes")
        case .rules: content.accessibilityIdentifier("configuration-center.rules")
        }
    }
}

 
enum HakoMacNodeLibraryRowItem: Identifiable {
    case source(ConfigurationSourceRecord)
     
    case nodeSets(ConfigurationSourceRecord, Int)
    case collection(ConfigurationCollectionEntry)

    var id: String {
        switch self {
        case .source(let source): "source." + source.id
        case .nodeSets(let source, _): "node-sets." + source.id
        case .collection(let entry): "collection." + entry.source.id + "." + entry.collection.name
        }
    }

    var sourceID: String {
        switch self {
        case .source(let source): source.id
        case .nodeSets(let source, _): source.id
        case .collection(let entry): entry.source.id
        }
    }
}

 
 
struct HakoMacNodeLibraryRow<Detail: View>: View {
    let item: HakoMacNodeLibraryRowItem
    let isUpdating: Bool
    let isExpanded: Bool
    let detail: (HakoMacConfigurationCenterItem) -> Detail
    let update: () -> Void
    let delete: () -> Void
    let toggleNodeSets: () -> Void

    var body: some View {
        switch item {
        case .nodeSets(let source, let count):
            HStack(spacing: HakoTheme.Spacing.compact) {
                Text(hako: .format("Node Sets (%@)", [String(count)])).font(.subheadline)
                Spacer()
                HakoMacTrailingChevron(expanded: isExpanded)
            }
            .padding(.leading, HakoTheme.Control.pointerRowTarget)
            .hakoMacPressableRow(toggleNodeSets)
            .accessibilityIdentifier("configuration-center.nodes.node-sets.\(source.id)")
        case .source(let source):
            HakoMacRoutedRow {
                detail(.source(source.id))
            } label: {
                HakoMacSettingsRow(
                    title: .verbatim(source.label),
                     
                    status: source.isRetainedSnapshot == true ? .copy("Saved Copy") : .count(source.nodeCount, one: "%@ node", other: "%@ nodes"),
                    statusTint: nil,
                    trailing: nil,
                    busy: isUpdating,
                    usage: source.subscriptionUsage
                )
            }
            .contextMenu {
                Button(action: update) { Text(hako: .copy("Update Source")) }
                Divider()
                Button(role: .destructive, action: delete) { Text(hako: .copy("Delete")) }
            }
            .accessibilityIdentifier("configuration-center.nodes.row.\(source.id)")
        case .collection(let entry):
             
            HakoMacRoutedRow {
                detail(.collection(entry.id))
            } label: {
                HakoMacSettingsRow(
                    title: .verbatim(entry.collection.name),
                    status: entry.memberCount.map { .count($0, one: "%@ node", other: "%@ nodes") } ?? .verbatim(entry.collection.type),
                    statusTint: nil,
                    trailing: nil,
                    busy: false
                )
                .padding(.leading, HakoTheme.Control.pointerRowTarget)
            }
            .accessibilityIdentifier("configuration-center.nodes.collection.\(entry.source.id).\(entry.collection.name)")
        }
    }
}

 
private let hakoMacListDateFormatters = HakoMacDateFormatterCache(dateStyle: .medium, timeStyle: .short)

 
 
 
struct HakoMacUsageLines: View {
    let usage: ConfigurationSubscriptionUsage
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
            Text(hako: HakoMacSubscriptionUsageCopy.traffic(usage))
            if let fraction = usage.fraction {
                 
                 
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25)).frame(width: 240, height: 4)
                    Capsule().fill(Color.accentColor).frame(width: max(2, 240 * min(1, max(0, fraction))), height: 4)
                }
                .accessibilityLabel(Text(hako: .copy("Used")))
            }
            if let expiry = HakoMacSubscriptionUsageCopy.expiry(usage, locale: locale) {
                Text(hako: expiry)
                    .foregroundStyle(usage.expire < Int64(Date().timeIntervalSince1970) ? Color.red : Color.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.top, 2)
    }
}

 
enum HakoMacRuleLibraryRowItem: Identifiable {
    case scheme(ConfigurationRuleScheme)
    case ruleSets(ConfigurationRuleScheme, Int)
    case collection(ConfigurationRuleScheme, ConfigurationCollectionEntry)

    var id: String {
        switch self {
        case .scheme(let scheme): "scheme." + scheme.id
        case .ruleSets(let scheme, _): "rule-sets." + scheme.id
        case .collection(let scheme, let entry): "collection." + scheme.id + "." + entry.collection.name
        }
    }
}
