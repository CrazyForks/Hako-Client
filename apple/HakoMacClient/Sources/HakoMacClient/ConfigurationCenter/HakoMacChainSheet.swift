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

    public init(existing: ConfigurationSourceRecord?, actions: HakoMacChainSheetActions, close: @escaping () -> Void) {
        self.existing = existing; self.actions = actions; self.close = close
        _name = State(initialValue: existing?.label ?? "")
        _entry = State(initialValue: existing?.nodeChain?.entry)
        _exit = State(initialValue: existing?.nodeChain?.exit)
    }

    private var dirty: Bool {
        name != (existing?.label ?? "") || entry != existing?.nodeChain?.entry || exit != existing?.nodeChain?.exit
    }
    private var canCommit: Bool { entry != nil && exit != nil && entry != exit && !busy && choices != nil }

    public var body: some View {
        HakoMacSheetFrame(title: existing == nil ? .copy("Add Proxy Chain") : .copy("Edit Proxy Chain"), width: 560, height: 460) {
            HakoMacSheetForm {
                Section {
                    TextField(text: $name, prompt: Text(hako: .copy("Entry → Exit"))) { Text(hako: .copy("Name")) }
                        .accessibilityIdentifier("configuration-center.chain.name")
                }
                Section {
                     
                     
                     
                    Text(hako: .copy("This Device"))
                    hopPicker(.copy("Entry Node"), selection: $entry, identifier: "configuration-center.chain.entry")
                    hopPicker(.copy("Exit Node"), selection: $exit, identifier: "configuration-center.chain.exit")
                    Text(hako: .copy("Destination Website"))
                } header: {
                    Text(hako: .copy("Connection Order"))
                }
                if let choices, choices.isEmpty {
                    Section { Text(hako: .copy("Add nodes to Node Library first.")).foregroundStyle(.secondary) }
                }
            }
        } leading: {
            if let error {
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

    private func hopPicker(_ title: HakoDisplayText, selection: Binding<ConfigurationNodeChain.Hop?>, identifier: String) -> some View {
        Picker(selection: selection) {
             
            Text(hako: .copy("Choose Node")).tag(ConfigurationNodeChain.Hop?.none)
            ForEach(choices ?? []) { choice in
                Text(verbatim: choice.hop.nodeName + " · " + choice.sourceLabel).tag(ConfigurationNodeChain.Hop?.some(choice.hop))
            }
        } label: {
            HStack(spacing: HakoTheme.Spacing.compact) {
                 
                HakoSymbolImage(symbol: .arrowDown).foregroundStyle(.secondary)
                Text(hako: title)
            }
        }
        .pickerStyle(.menu)
        .disabled(choices == nil)
        .accessibilityIdentifier(identifier)
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
