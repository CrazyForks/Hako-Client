import HakoClientKit
import HakoClientUI
import SwiftUI

 
public enum HakoMacConfigurationCenterItem: Hashable, Sendable {
    case configuration(Profile.ID)
    case source(String)
    case scheme(String)
}

 
public enum HakoMacConfigurationAddKind: Sendable {
    case profileURL, file, blank
}

 
public struct HakoMacConfigurationCenterListActions {
    public var addConfiguration: @MainActor (HakoMacConfigurationAddKind) -> Void
    public var addSource: @MainActor () -> Void
    public var addScheme: @MainActor () -> Void
    public var activate: @MainActor (Profile.ID) -> Void
    public var rename: @MainActor (Profile.ID, String) -> Void
    public var delete: @MainActor (HakoMacConfigurationCenterItem) -> Void

    public init(
        addConfiguration: @escaping @MainActor (HakoMacConfigurationAddKind) -> Void,
        addSource: @escaping @MainActor () -> Void,
        addScheme: @escaping @MainActor () -> Void,
        activate: @escaping @MainActor (Profile.ID) -> Void,
        rename: @escaping @MainActor (Profile.ID, String) -> Void = { _, _ in },
        delete: @escaping @MainActor (HakoMacConfigurationCenterItem) -> Void
    ) {
        self.addConfiguration = addConfiguration
        self.addSource = addSource
        self.addScheme = addScheme
        self.activate = activate
        self.rename = rename
        self.delete = delete
    }

    public static var unavailable: Self {
        Self(addConfiguration: { _ in }, addSource: {}, addScheme: {}, activate: { _ in }, delete: { _ in })
    }
}

 
 
 
 
 
 
 
public struct HakoMacConfigurationCenterListPage<Detail: View>: View {
    private let segment: HakoMacConfigurationCenterSegment
    @ObservedObject private var model: HakoMacConfigurationLibraryModel
    private let profiles: [HakoProfileSnapshot]
    @Binding private var pendingDelete: HakoMacConfigurationCenterItem?
     
     
     
    @Binding private var renaming: Profile.ID?
    private let actions: HakoMacConfigurationCenterListActions
    private let detail: (HakoMacConfigurationCenterItem) -> Detail
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    public init(
        segment: HakoMacConfigurationCenterSegment,
        model: HakoMacConfigurationLibraryModel,
        profiles: [HakoProfileSnapshot],
        pendingDelete: Binding<HakoMacConfigurationCenterItem?> = .constant(nil),
        renaming: Binding<Profile.ID?> = .constant(nil),
        actions: HakoMacConfigurationCenterListActions,
        @ViewBuilder detail: @escaping (HakoMacConfigurationCenterItem) -> Detail
    ) {
        self.segment = segment
        self.model = model
        self.profiles = profiles
        _pendingDelete = pendingDelete
        _renaming = renaming
        self.actions = actions
        self.detail = detail
    }

    public var body: some View {
        List {
            switch segment {
            case .configurations: configurationRows
            case .nodes: sourceRows
            case .rules: schemeRows
            }
        }
        .listStyle(.inset)
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

     

    @ViewBuilder
    private var configurationRows: some View {
        Section {
            ForEach(profiles) { profile in
                if renaming == profile.id {
                    HStack(spacing: HakoTheme.Spacing.compact) {
                        TextField(text: $draftName) { Text(hako: .copy("Name")) }
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFieldFocused)
                            .onSubmit { commitRename(profile) }
                            .onExitCommand { renaming = nil }
                            .onAppear { draftName = profile.label; nameFieldFocused = true }
                            .accessibilityIdentifier("configuration-center.configurations.rename")
                    }
                } else {
                    HakoRoutedViewLink {
                        detail(.configuration(profile.id))
                    } label: {
                        HakoMacSettingsRow(
                            title: .verbatim(profile.label),
                            status: profile.isCurrent ? .copy("Active") : profile.sourceSummary,
                            statusTint: profile.isCurrent ? .green : nil,
                            trailing: nil,
                            busy: profile.isBusy
                        )
                    }
                    .contextMenu {
                        if !profile.isCurrent {
                            Button { actions.activate(profile.id) } label: { Text(hako: .copy("Activate")) }
                        }
                        Button { renaming = profile.id } label: { Text(hako: .copy("Name")) }
                        Divider()
                        Button(role: .destructive) { pendingDelete = .configuration(profile.id) } label: { Text(hako: .copy("Delete")) }
                    }
                    .accessibilityIdentifier("configuration-center.configurations.row.\(profile.id.rawValue)")
                }
            }
        }
         
        HakoMacSettingsListFooter {
            Menu {
                Button { actions.addConfiguration(.blank) } label: { Text(hako: .copy("Add Profile")) }
                Button { actions.addConfiguration(.profileURL) } label: { Text(hako: .copy("Profile URL")) }
                Button { actions.addConfiguration(.file) } label: { Text(hako: .copy("File")) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityIdentifier("configuration-center.configurations.add")
        }
    }

    private func commitRename(_ profile: HakoProfileSnapshot) {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != profile.label { actions.rename(profile.id, trimmed) }
        renaming = nil
    }

    @ViewBuilder
    private var sourceRows: some View {
        ForEach(model.nodeShelves) { shelf in
            Section {
                ForEach(shelf.sources) { source in
                    HakoRoutedViewLink {
                        detail(.source(source.id))
                    } label: {
                        HakoMacSettingsRow(
                            title: .verbatim(source.label),
                            status: .format("%@ nodes", [String(source.nodeCount)]),
                            statusTint: nil,
                            trailing: nil,
                            busy: model.updatingSourceIDs.contains(source.id)
                        )
                    }
                    .contextMenu {
                        Button { Task { _ = await model.updateSource(source.id) } } label: { Text(hako: .copy("Update Source")) }
                        Divider()
                        Button(role: .destructive) { pendingDelete = .source(source.id) } label: { Text(hako: .copy("Delete")) }
                    }
                    .accessibilityIdentifier("configuration-center.nodes.row.\(source.id)")
                }
            } header: {
                Text(hako: .copy(shelf.group.title))
            }
        }
        HakoMacSettingsListFooter {
            Menu {
                Button { actions.addSource() } label: { Text(hako: .copy("Add Source")) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityIdentifier("configuration-center.nodes.add")
        }
    }

    @ViewBuilder
    private var schemeRows: some View {
        ForEach(model.ruleShelves) { shelf in
            Section {
                ForEach(shelf.schemes) { scheme in
                    HakoRoutedViewLink {
                        detail(.scheme(scheme.id))
                    } label: {
                        HakoMacSettingsRow(
                            title: .verbatim(scheme.label),
                            status: scheme.kind == .builtin
                                ? .copy("Built-in")
                                : .format("Used by %@ profiles", [String(model.usageCount(ofScheme: scheme.id))]),
                            statusTint: nil,
                            trailing: nil,
                            busy: false
                        )
                    }
                    .contextMenu {
                        if scheme.kind == .custom {
                            Button(role: .destructive) { pendingDelete = .scheme(scheme.id) } label: { Text(hako: .copy("Delete")) }
                        }
                    }
                    .accessibilityIdentifier("configuration-center.rules.row.\(scheme.id)")
                }
            } header: {
                Text(hako: .copy(shelf.section.title))
            }
        }
        HakoMacSettingsListFooter {
            Menu {
                Button { actions.addScheme() } label: { Text(hako: .copy("Add Rule Scheme")) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityIdentifier("configuration-center.rules.add")
        }
    }

     

    private var deleteTitle: Text {
        switch pendingDelete {
        case .source: Text(hako: .copy("Delete Source"))
        case .scheme: Text(hako: .copy("Delete Rule Scheme"))
        case .configuration, nil: Text(hako: .copy("Delete Profile"))
        }
    }

    private var deleteMessage: HakoDisplayText {
        switch pendingDelete {
        case .source: .copy("Saved profiles keep their current content and stop following this source.")
        case .scheme: .copy("Saved profiles keep their current rules and stop following this scheme.")
        case .configuration(let id): profiles.first { $0.id == id }?.deleteSubtitle ?? .verbatim("")
        case nil: .verbatim("")
        }
    }
}

 
 
 
struct HakoMacSettingsRow: View {
    let title: HakoDisplayText
    let status: HakoDisplayText?
    let statusTint: Color?
    let trailing: HakoDisplayText?
    let busy: Bool

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

 
struct HakoMacSettingsListFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            HStack {
                Spacer()
                content()
                    .menuStyle(.borderedButton)
                    .fixedSize()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
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
