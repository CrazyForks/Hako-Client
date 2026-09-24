import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
public struct HakoMacSourcePaneActions {
     
     
     
     
     
    public var save: @MainActor (_ label: String, _ settings: ConfigurationSourceSettingsDraft?) -> Void
    public var update: @MainActor () -> Void
    public var delete: @MainActor () -> Void
     
    public var editSource: (@MainActor () -> Void)?

    public init(
        save: @escaping @MainActor (String, ConfigurationSourceSettingsDraft?) -> Void,
        update: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void,
        editSource: (@MainActor () -> Void)? = nil
    ) {
        self.save = save; self.update = update; self.delete = delete
        self.editSource = editSource
    }

    public static var unavailable: Self { Self(save: { _, _ in }, update: {}, delete: {}) }
}

 
 
public struct HakoMacSchemePaneActions {
    public var edit: @MainActor () -> Void
    public var duplicate: @MainActor () -> Void
    public var update: @MainActor () -> Void
    public var delete: @MainActor () -> Void
     
    public var load: @MainActor () async throws -> HakoMacRuleEditorState

    public init(
        edit: @escaping @MainActor () -> Void,
        duplicate: @escaping @MainActor () -> Void,
        update: @escaping @MainActor () -> Void = {},
        delete: @escaping @MainActor () -> Void,
        load: @escaping @MainActor () async throws -> HakoMacRuleEditorState = { throw ConfigurationLibraryError.unreadable }
    ) {
        self.edit = edit; self.duplicate = duplicate; self.update = update; self.delete = delete; self.load = load
    }

    public static var unavailable: Self { Self(edit: {}, duplicate: {}, delete: {}) }
}

 
 
 
 
public struct HakoMacSchemePane: View {
    private let scheme: ConfigurationRuleScheme
    private let source: ConfigurationSourceRecord?
    private let usedBy: [HakoProfileSnapshot]
    private let actions: HakoMacSchemePaneActions
     
    public var updateError: String?

    public init(scheme: ConfigurationRuleScheme, source: ConfigurationSourceRecord?, usedBy: [HakoProfileSnapshot], actions: HakoMacSchemePaneActions) {
        self.scheme = scheme
        self.source = source
        self.usedBy = usedBy
        self.actions = actions
    }

    private var kind: HakoDisplayText {
        switch scheme.kind {
        case .builtin: .copy("Built-in")
        case .community: .copy("Community")
        case .custom: .copy("Custom")
        case .imported, .supplied: .copy("Imported")
        }
    }

    private var isEditable: Bool { scheme.kind == .custom && scheme.isRetainedSnapshot != true }
    private var comesFromLink: Bool {
        if case .subscription = source?.origin { return true }
        return false
    }

    public var body: some View {
        Form {
            headerCard
            Section {
                LabeledContent { Text(hako: kind) } label: { Text(hako: .copy("Kind")) }
                if let source {
                    HakoRoutedViewLink {
                        HakoMacRuleBrowsePage(kind: .groups, load: actions.load)
                            .navigationTitle(Text(hako: .copy("Policy Groups")))
                    } label: {
                        HakoMacPushRowLabel(.copy("Policy Groups"), value: .verbatim(String(source.groupCount)))
                    }
                    .accessibilityIdentifier("configuration-center.scheme.groups")
                    HakoRoutedViewLink {
                        HakoMacRuleBrowsePage(kind: .rules, load: actions.load)
                            .navigationTitle(Text(hako: .copy("Rules")))
                    } label: {
                        HakoMacPushRowLabel(.copy("Rules"), value: .verbatim(String(source.ruleCount)))
                    }
                    .accessibilityIdentifier("configuration-center.scheme.rules")
                }
            } footer: {
                if !isEditable { Text(hako: .copy("Copy this rule scheme to make changes.")) }
            }
            Section {
                if usedBy.isEmpty {
                    Text(hako: .copy("None")).foregroundStyle(.secondary)
                } else {
                     
                    ForEach(usedBy) { profile in
                        Text(verbatim: profile.label)
                            .accessibilityIdentifier("configuration-center.scheme.used-by.\(profile.id.rawValue)")
                    }
                }
            } header: {
                Text(hako: .copy("Used by Profiles"))
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("configuration-center.scheme")
    }

    private var headerCard: some View {
        Section {
            HStack(spacing: HakoTheme.Spacing.compact) {
                Text(hako: kind).lineLimit(1)
                Spacer()
                if isEditable {
                    Button { actions.edit() } label: { Text(hako: .copy("Edit")) }
                        .accessibilityIdentifier("configuration-center.scheme.edit")
                }
                Menu {
                    Button { actions.duplicate() } label: { Text(hako: .copy("Copy Rule Scheme")) }
                        .accessibilityIdentifier("configuration-center.scheme.duplicate")
                    if comesFromLink {
                        Button { actions.update() } label: { Text(hako: .copy("Update")) }
                    }
                    if scheme.canBeDeleted {
                        Divider()
                         
                         
                        Button(role: .destructive) { actions.delete() } label: {
                            Text(hako: .copy("Delete"))
                        }
                        .accessibilityIdentifier("configuration-center.scheme.delete")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderedButton).menuIndicator(.hidden).fixedSize()
                .accessibilityIdentifier("configuration-center.scheme.more")
            }
            .tint(.primary)
            .padding(.vertical, 4)
            if let updateError {
                Text(verbatim: updateError)
                    .font(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.scheme.update-error")
            }
        }
    }
}

 
 
 
struct HakoMacRuleBrowsePage: View {
    enum Kind { case groups, rules }

    let kind: Kind
    let load: @MainActor () async throws -> HakoMacRuleEditorState
    @State private var state: HakoMacRuleEditorState?
    @State private var error: String?
    @State private var filter = ""
     
    @State private var expanded: Set<UUID> = []

    private var needle: String { filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

     
     
    private static func members(of group: ConfigurationRuleDraft.Group) -> [String] {
        var names: [String] = []
        if case .array(let values) = group.document.topLevelValue("proxies") {
            names += values.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
        if case .array(let values) = group.document.topLevelValue("use") {
            names += values.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
        return names
    }

    var body: some View {
        List {
            if let error {
                Section { Text(verbatim: error).foregroundStyle(.red).accessibilityIdentifier("configuration-center.scheme.browse.error") }
            }
            if let state {
                switch kind {
                case .groups:
                    Section {
                        ForEach(groups(in: state)) { group in
                            let isOpen = expanded.contains(group.id)
                            HStack(spacing: HakoTheme.Spacing.compact) {
                                Text(verbatim: group.name)
                                Spacer()
                                Text(verbatim: group.type).foregroundStyle(.secondary)
                                HakoMacTrailingChevron(expanded: isOpen)
                            }
                            .hakoMacPressableRow {
                                if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) }
                            }
                            .accessibilityIdentifier("configuration-center.scheme.browse.group")
                            if isOpen {
                                ForEach(Self.members(of: group), id: \.self) { member in
                                    Text(verbatim: member).font(.subheadline).foregroundStyle(.secondary)
                                        .padding(.leading, HakoTheme.Spacing.row)
                                }
                            }
                        }
                    }
                case .rules:
                    Section {
                        ForEach(rules(in: state)) { row in
                            Text(verbatim: row.raw)
                                .font(.body.monospaced())
                                .foregroundStyle(state.draft.disabledRules.contains(row.raw) ? Color.secondary : Color.primary)
                        }
                    }
                }
            } else if error == nil {
                Section { ProgressView().controlSize(.small) }
            }
        }
        .listStyle(.inset)
        .hakoProductModalSearchable(text: $filter, prompt: Text(hako: .copy("Filter")))
        .task {
            do { state = try await load() } catch { self.error = error.localizedDescription }
        }
    }

    private func groups(in state: HakoMacRuleEditorState) -> [ConfigurationRuleDraft.Group] {
        let needle = needle
        return needle.isEmpty ? state.draft.groups : state.draft.groups.filter { $0.name.lowercased().contains(needle) || $0.type.lowercased().contains(needle) }
    }

    private func rules(in state: HakoMacRuleEditorState) -> [ConfigurationRuleDraft.Row] {
        let needle = needle
        return needle.isEmpty ? state.draft.rows : state.draft.rows.filter { $0.raw.lowercased().contains(needle) }
    }
}

 
 
public struct HakoMacCollectionPage: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: Int
        public let title: String
        public let subtitle: String?
        public init(id: Int, title: String, subtitle: String?) { self.id = id; self.title = title; self.subtitle = subtitle }
    }
    public var rows: [Row]
    public var count: Int?
    public var updatedAt: Date?
    public var nextOffset: Int?
    public var message: String?

    public init(rows: [Row] = [], count: Int? = nil, updatedAt: Date? = nil, nextOffset: Int? = nil, message: String? = nil) {
        self.rows = rows; self.count = count; self.updatedAt = updatedAt; self.nextOffset = nextOffset; self.message = message
    }
}

 
 
 
 
public struct HakoMacCollectionPageActions {
    public var load: @MainActor (String, Int) async throws -> HakoMacCollectionPage
    public var update: (@MainActor () async throws -> Void)?
    public var createScheme: (@MainActor () async throws -> Void)?
    public var editSource: (@MainActor () -> Void)?
    public var delete: (@MainActor () async throws -> Void)?

    public init(
        load: @escaping @MainActor (String, Int) async throws -> HakoMacCollectionPage,
        update: (@MainActor () async throws -> Void)? = nil,
        createScheme: (@MainActor () async throws -> Void)? = nil,
        editSource: (@MainActor () -> Void)? = nil,
        delete: (@MainActor () async throws -> Void)? = nil
    ) {
        self.load = load; self.update = update; self.createScheme = createScheme; self.editSource = editSource; self.delete = delete
    }

    public static var unavailable: HakoMacCollectionPageActions {
        HakoMacCollectionPageActions(load: { _, _ in HakoMacCollectionPage() })
    }
}

 
 
 
 
 
public struct HakoMacCollectionPane: View {
    private let collection: ConfigurationCollection
    private let sourceLabel: String?
    private let actions: HakoMacCollectionPageActions
    @State private var page: HakoMacCollectionPage?
    @State private var filter = ""
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmsDeletion = false
    @Environment(\.locale) private var locale

    public init(collection: ConfigurationCollection, sourceLabel: String? = nil, actions: HakoMacCollectionPageActions = .unavailable) {
        self.collection = collection
        self.sourceLabel = sourceLabel
        self.actions = actions
    }

    private static let dateFormatters = HakoMacDateFormatterCache(dateStyle: .medium, timeStyle: .short)

    private var status: String {
        var parts: [String] = []
        if let sourceLabel { parts.append(sourceLabel) }
        if let count = page?.count {
            let text: HakoDisplayText = collection.id.kind == .nodes
                ? .count(count, one: "%@ node", other: "%@ nodes") : .count(count, one: "%@ rule", other: "%@ rules")
            parts.append(HakoCopy.string(for: text, locale: locale))
        }
        if let date = page?.updatedAt { parts.append(Self.dateFormatters.formatter(for: locale).string(from: date)) }
        if let message = page?.message { parts.append(message) }
        return parts.joined(separator: " · ")
    }

    public var body: some View {
        HakoMacCardPage {
            headerCard
            detailsCard
            membersCard
        }
        .hakoProductModalSearchable(text: $filter, prompt: Text(hako: .copy("Filter")))
        .accessibilityIdentifier("configuration-center.collection")
        .task(id: filter) {
            if !filter.isEmpty { try? await Task.sleep(nanoseconds: 180_000_000) }
            guard !Task.isCancelled else { return }
            await load()
        }
        .alert(Text(hako: .copy("Delete Collection")), isPresented: $confirmsDeletion) {
            Button(role: .destructive) { perform { try await actions.delete?() } } label: { Text(hako: .copy("Delete Collection")) }
                .accessibilityIdentifier("configuration-center.collection.delete.confirm")
            Button(role: .cancel) {} label: { Text(hako: .copy("Cancel")) }
        } message: {
            Text(hako: .copy("Remove this collection from its source. Profiles that reference it must choose another collection first."))
        }
    }

    private var headerCard: some View {
        HakoMacCardSection {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: HakoTheme.Spacing.compact) {
                    Text(verbatim: status.isEmpty ? collection.name : status).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if loading || busy { ProgressView().controlSize(.small) }
                    if actions.update != nil {
                        Button { perform { try await actions.update?(); await load() } } label: { Text(hako: .copy("Update Source")) }
                            .disabled(busy || loading)
                            .accessibilityIdentifier("configuration-center.collection.update")
                    }
                    if actions.createScheme != nil || actions.editSource != nil || actions.delete != nil {
                        Menu {
                            if actions.createScheme != nil {
                                 
                                Button { perform { try await actions.createScheme?() } } label: { Text(hako: .copy("Add Rule Scheme")) }
                            }
                            if let editSource = actions.editSource {
                                Button { editSource() } label: { Text(hako: .copy("Edit Source")) }
                            }
                            if actions.delete != nil {
                                Divider()
                                Button(role: .destructive) { confirmsDeletion = true } label: { Text(hako: .copy("Delete Collection")) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderedButton).fixedSize()
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.collection.manage")
                    }
                }
                .tint(.primary)
                if let error {
                    Text(verbatim: error).font(.footnote).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("configuration-center.collection.error")
                }
            }
            .padding(.vertical, 4)
            .hakoMacCardRow(isLast: true)
        }
    }

    private var detailsCard: some View {
        let hasFormat = collection.id.kind == .rules
        let behavior = hasFormat ? collection.behavior : nil
        let location = collection.location
        return HakoMacCardSection {
            HakoMacValueRow(.copy("Type"), value: .verbatim(collection.type))
                .hakoMacCardRow(isLast: !hasFormat && location == nil)
            if hasFormat {
                HakoMacValueRow(.copy("Format"), value: .verbatim(collection.format))
                    .hakoMacCardRow(isLast: behavior == nil && location == nil)
            }
            if let behavior {
                HakoMacValueRow(.copy("Behavior"), value: .verbatim(behavior))
                    .hakoMacCardRow(isLast: location == nil)
            }
            if let location {
                Text(verbatim: location).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hakoMacCardRow(isLast: true)
            }
        }
    }

    @ViewBuilder
    private var membersCard: some View {
        let rows = page?.rows ?? []
        let more = page?.nextOffset
        HakoMacCardSection(.copy("Members")) {
            if rows.isEmpty {
                Text(hako: .copy("None")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hakoMacCardRow(isLast: true)
            }
             
             
             
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                        Text(verbatim: row.title)
                            .font(row.subtitle == nil ? .body.monospaced() : .body)
                            .lineLimit(1).truncationMode(.middle)
                        if let subtitle = row.subtitle, !subtitle.isEmpty {
                            Text(verbatim: subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hakoMacCardRow(isLast: more == nil && row.id == rows.last?.id)
                    .accessibilityIdentifier("configuration-center.collection.row")
                }
            }
            if let more {
                HakoMacShowAllRow(title: .copy("Load More"), identifier: "configuration-center.collection.more") {
                    Task { await load(offset: more) }
                }
                .hakoMacCardRow(isLast: true)
            }
        }
    }

    private func load(offset: Int = 0) async {
        loading = true
        defer { loading = false }
        do {
            let loaded = try await actions.load(filter, offset)
            if offset == 0 {
                page = loaded
            } else {
                var merged = loaded
                merged.rows = (page?.rows ?? []) + loaded.rows
                page = merged
            }
            if offset == 0 { error = nil }
        } catch {
             
            self.error = error.localizedDescription
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { self.error = error.localizedDescription }
        }
    }
}
