import HakoClientKit
import HakoClientUI
import SwiftUI

 
public struct HakoMacSourcePaneActions {
    public var rename: @MainActor (String) -> Void
    public var update: @MainActor () -> Void
    public var delete: @MainActor () -> Void
    public var open: @MainActor (Profile.ID) -> Void

    public init(
        rename: @escaping @MainActor (String) -> Void, update: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void, open: @escaping @MainActor (Profile.ID) -> Void
    ) {
        self.rename = rename; self.update = update; self.delete = delete; self.open = open
    }

    public static var unavailable: Self { Self(rename: { _ in }, update: {}, delete: {}, open: { _ in }) }
}

 
 
public struct HakoMacSourcePane: View {
    private let source: ConfigurationSourceRecord
    private let usedBy: [HakoProfileSnapshot]
    private let isUpdating: Bool
    private let actions: HakoMacSourcePaneActions
    @State private var name: String
    @Environment(\.locale) private var locale

    public init(source: ConfigurationSourceRecord, usedBy: [HakoProfileSnapshot], isUpdating: Bool, actions: HakoMacSourcePaneActions) {
        self.source = source
        self.usedBy = usedBy
        self.isUpdating = isUpdating
        self.actions = actions
        _name = State(initialValue: source.label)
    }

    private var origin: HakoDisplayText {
        switch source.origin {
        case .subscription(let url): .verbatim(url)
        case .file(let name): .verbatim(name)
        case .customNodes: .copy("Custom Nodes")
        default: .copy("Source")
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: HakoTheme.Spacing.compact) {
                        Text(hako: .format("%@ nodes", [String(source.nodeCount)])).lineLimit(1)
                        Spacer()
                        if case .subscription = source.origin {
                            Button { actions.update() } label: { Text(hako: .copy("Update Source")) }
                                .disabled(isUpdating)
                                .accessibilityIdentifier("configuration-center.source.update")
                        }
                        Menu {
                            Button(role: .destructive) { actions.delete() } label: { Text(hako: .copy("Delete")) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderedButton).fixedSize()
                        .accessibilityIdentifier("configuration-center.source.more")
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    TextField(text: $name) { Text(hako: .copy("Name")) }
                        .onSubmit {
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty || trimmed == source.label { name = source.label } else { actions.rename(trimmed) }
                        }
                        .accessibilityIdentifier("configuration-center.source.name")
                    LabeledContent { Text(hako: origin).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing) } label: { Text(hako: .copy("Source")) }
                    if let usage = source.subscriptionUsage {
                        LabeledContent { Text(hako: HakoMacSubscriptionUsageCopy.traffic(usage)) } label: { Text(hako: .copy("Traffic")) }
                        if let expiry = HakoMacSubscriptionUsageCopy.expiry(usage, locale: locale) {
                            Text(hako: expiry).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent {
                        HStack(spacing: HakoTheme.Spacing.compact) {
                            if isUpdating { ProgressView().controlSize(.small) }
                            Text(verbatim: Self.dateFormatters.formatter(for: locale).string(from: source.updatedAt))
                        }
                    } label: {
                        Text(hako: .copy("Last Sync"))
                    }
                }
                Section {
                    if usedBy.isEmpty {
                        Text(hako: .copy("None")).foregroundStyle(.secondary)
                    } else {
                        ForEach(usedBy) { profile in
                            HakoMacDoorRow(.verbatim(profile.label), identifier: "configuration-center.source.used-by.\(profile.id.rawValue)") {
                                actions.open(profile.id)
                            }
                        }
                    }
                } header: {
                    Text(hako: .copy("Used by Profiles"))
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("configuration-center.source")
        }
    }

    private static let dateFormatters = HakoMacDateFormatterCache(dateStyle: .medium, timeStyle: .short)
}

 
public struct HakoMacSchemePaneActions {
    public var edit: @MainActor () -> Void
    public var duplicate: @MainActor () -> Void
    public var delete: @MainActor () -> Void
    public var open: @MainActor (Profile.ID) -> Void

    public init(
        edit: @escaping @MainActor () -> Void, duplicate: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void, open: @escaping @MainActor (Profile.ID) -> Void
    ) {
        self.edit = edit; self.duplicate = duplicate; self.delete = delete; self.open = open
    }

    public static var unavailable: Self { Self(edit: {}, duplicate: {}, delete: {}, open: { _ in }) }
}

 
 
 
public struct HakoMacSchemePane: View {
    private let scheme: ConfigurationRuleScheme
    private let source: ConfigurationSourceRecord?
    private let usedBy: [HakoProfileSnapshot]
    private let actions: HakoMacSchemePaneActions

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

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: HakoTheme.Spacing.compact) {
                        Text(hako: kind).lineLimit(1)
                        Spacer()
                        if scheme.kind == .custom {
                            Button { actions.edit() } label: { Text(hako: .copy("Edit")) }
                                .accessibilityIdentifier("configuration-center.scheme.edit")
                        }
                        Menu {
                            Button { actions.duplicate() } label: { Text(hako: .copy("Duplicate")) }
                            if scheme.kind == .custom {
                                Divider()
                                Button(role: .destructive) { actions.delete() } label: { Text(hako: .copy("Delete")) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderedButton).fixedSize()
                        .accessibilityIdentifier("configuration-center.scheme.more")
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    LabeledContent { Text(hako: kind) } label: { Text(hako: .copy("Kind")) }
                    if let source {
                        LabeledContent { Text(hako: .format("%@ rules", [String(source.ruleCount)])) } label: { Text(hako: .copy("Rules")) }
                    }
                }
                Section {
                    if usedBy.isEmpty {
                        Text(hako: .copy("None")).foregroundStyle(.secondary)
                    } else {
                        ForEach(usedBy) { profile in
                            HakoMacDoorRow(.verbatim(profile.label), identifier: "configuration-center.scheme.used-by.\(profile.id.rawValue)") {
                                actions.open(profile.id)
                            }
                        }
                    }
                } header: {
                    Text(hako: .copy("Used by Profiles"))
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("configuration-center.scheme")
        }
    }
}
