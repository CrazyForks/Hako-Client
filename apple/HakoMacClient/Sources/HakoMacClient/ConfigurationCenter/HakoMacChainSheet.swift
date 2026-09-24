import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
public struct HakoMacChainChoice: Identifiable, Sendable, Equatable {
    public let hop: ConfigurationNodeChain.Hop
    public let sourceLabel: String
    public var id: String { hop.source.id + "/" + hop.nodeName }
    public init(hop: ConfigurationNodeChain.Hop, sourceLabel: String) { self.hop = hop; self.sourceLabel = sourceLabel }
}

public struct HakoMacChainSheetActions {
     
    public var loadChoices: @MainActor () async throws -> [HakoMacChainChoice]
     
    public var commit: @MainActor (String, ConfigurationNodeChain.Hop, ConfigurationNodeChain.Hop) async throws -> Void

    public init(
        loadChoices: @escaping @MainActor () async throws -> [HakoMacChainChoice],
        commit: @escaping @MainActor (String, ConfigurationNodeChain.Hop, ConfigurationNodeChain.Hop) async throws -> Void
    ) {
        self.loadChoices = loadChoices; self.commit = commit
    }

    public static var unavailable: Self { Self(loadChoices: { [] }, commit: { _, _, _ in throw ConfigurationLibraryError.unreadable }) }
}

 
 
 
 
 
 
 
public struct HakoMacChainSheet: View {
    private enum Slot { case entry, exit }
    private let existing: ConfigurationSourceRecord?
    private let actions: HakoMacChainSheetActions
    private let close: () -> Void
    @State private var name: String
    @State private var entry: ConfigurationNodeChain.Hop?
    @State private var exit: ConfigurationNodeChain.Hop?
    @State private var choices: [HakoMacChainChoice]?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmsDiscard = false
     
    @State private var picking: Slot?
    @State private var query = ""

    public init(existing: ConfigurationSourceRecord?, actions: HakoMacChainSheetActions, close: @escaping () -> Void) {
        self.existing = existing; self.actions = actions; self.close = close
        _name = State(initialValue: existing?.label ?? "")
        _entry = State(initialValue: existing?.nodeChain?.entry)
        _exit = State(initialValue: existing?.nodeChain?.exit)
    }

    private var dirty: Bool {
        name != (existing?.label ?? "") || entry != existing?.nodeChain?.entry || exit != existing?.nodeChain?.exit
    }
    private var canCommit: Bool { entry != nil && exit != nil && entry != exit && !busy && choices != nil && picking == nil }

    private var title: HakoDisplayText {
        switch picking {
        case .entry: .copy("Entry Node")
        case .exit: .copy("Exit Node")
        case nil: existing == nil ? .copy("Add Proxy Chain") : .copy("Edit Proxy Chain")
        }
    }

    public var body: some View {
        HakoMacSheetFrame(title: title, width: 560, height: 460) {
            if let picking {
                nodePicker(picking)
            } else {
                form
            }
        } leading: {
            if picking != nil {
                Button { picking = nil } label: { Text(hako: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.chain.back")
            } else if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.chain.error")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.chain.cancel",
                primaryTitle: existing == nil ? .copy("Add") : .copy("Done"),
                primaryIdentifier: "configuration-center.chain.done",
                primaryDisabled: !canCommit,
                isBusy: busy,
                onClose: { if dirty { confirmsDiscard = true } else { close() } },
                onPrimary: commit
            )
        }
        .task { if choices == nil { await load() } }
        .alert(Text(hako: .copy("Discard Changes")), isPresented: $confirmsDiscard) {
            Button(role: .destructive) { close() } label: { Text(hako: .copy("Discard Changes")) }
            Button(role: .cancel) {} label: { Text(hako: .copy("Cancel")) }
        } message: {
            Text(hako: .copy("This proxy chain has unsaved changes."))
        }
    }

     
    static func sourceGroups(_ choices: [HakoMacChainChoice]) -> [(label: String, choices: [HakoMacChainChoice])] {
        var order: [String] = []
        var grouped: [String: [HakoMacChainChoice]] = [:]
        for choice in choices {
            if grouped[choice.sourceLabel] == nil { order.append(choice.sourceLabel) }
            grouped[choice.sourceLabel, default: []].append(choice)
        }
        return order.map { (label: $0, choices: grouped[$0] ?? []) }
    }

    private var form: some View {
        HakoMacSheetForm {
            Section {
                TextField(text: $name, prompt: Text(hako: .copy("Entry → Exit"))) { Text(hako: .copy("Name")) }
                    .accessibilityIdentifier("configuration-center.chain.name")
            }
            Section {
                 
                 
                 
                Text(hako: .copy("This Device"))
                hopRow(.copy("Entry Node"), hop: entry, slot: .entry, identifier: "configuration-center.chain.entry")
                hopRow(.copy("Exit Node"), hop: exit, slot: .exit, identifier: "configuration-center.chain.exit")
                Text(hako: .copy("Destination Website"))
            } header: {
                Text(hako: .copy("Connection Order"))
            }
            if let choices, choices.isEmpty {
                Section { Text(hako: .copy("Add nodes to Node Library first.")).foregroundStyle(.secondary) }
            }
        }
    }

     
     
     
    private func hopRow(_ title: HakoDisplayText, hop: ConfigurationNodeChain.Hop?, slot: Slot, identifier: String) -> some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
             
            HakoSymbolImage(symbol: .arrowDown).foregroundStyle(.secondary)
            Text(hako: title)
            Spacer()
            if let hop {
                Text(verbatim: hop.nodeName).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                 
                Text(hako: .copy("Choose Node")).foregroundStyle(.tertiary)
            }
            HakoSymbolImage(symbol: .chevronForward)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .hakoMacPressableRow { query = ""; picking = slot }
        .disabled(choices == nil || busy)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(Text(verbatim: hop?.nodeName ?? ""))
    }

     
     
    private func nodePicker(_ slot: Slot) -> some View {
        let current = slot == .entry ? entry : exit
        let needle = query.trimmingCharacters(in: .whitespaces)
        let groups = Self.sourceGroups((choices ?? []).filter { choice in
            needle.isEmpty
                || choice.hop.nodeName.localizedCaseInsensitiveContains(needle)
                || choice.sourceLabel.localizedCaseInsensitiveContains(needle)
        })
        return VStack(spacing: 0) {
            TextField(text: $query, prompt: Text(hako: .copy("Search nodes"))) { Text(hako: .copy("Search nodes")) }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityIdentifier("configuration-center.chain.search")
            Divider()
            if groups.isEmpty {
                HakoMacSheetPlaceholder(title: .copy("No results"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("configuration-center.chain.no-results")
            } else {
                List {
                    ForEach(groups, id: \.label) { group in
                        Section {
                            ForEach(group.choices) { choice in
                                HStack(spacing: HakoTheme.Spacing.compact) {
                                    Text(verbatim: choice.hop.nodeName).lineLimit(1)
                                    Spacer()
                                    if choice.hop == current {
                                        HakoSymbolImage(symbol: .checkmark).foregroundStyle(.tint)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .hakoMacPressableRow {
                                    if slot == .entry { entry = choice.hop } else { exit = choice.hop }
                                    picking = nil
                                }
                                .accessibilityLabel(Text(verbatim: choice.hop.nodeName))
                                .accessibilityIdentifier("configuration-center.chain.pick.\(choice.id)")
                            }
                        } header: {
                            Text(verbatim: group.label)
                        }
                    }
                }
                .hakoMacSettingsList(minRowHeight: HakoMacSettingsMetrics.listRowMinHeight)
            }
        }
    }

    private func load() async {
        do { choices = try await actions.loadChoices() } catch { self.error = error.localizedDescription; choices = [] }
    }

    private func commit() {
        guard let entry, let exit else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await actions.commit(name.trimmingCharacters(in: .whitespacesAndNewlines), entry, exit)
                close()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
