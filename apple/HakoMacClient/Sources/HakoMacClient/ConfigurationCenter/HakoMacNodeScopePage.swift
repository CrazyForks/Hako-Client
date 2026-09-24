import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
 
public struct HakoMacNodeScopeChoices: Sendable {
    public var collections: [ConfigurationCollection]
    public var nodes: [HakoConfigurationSelectableNode]

    public init(collections: [ConfigurationCollection], nodes: [HakoConfigurationSelectableNode]) {
        self.collections = collections
        self.nodes = nodes
    }
}

 
 
 
 
struct HakoMacNodeScopePage: View {
    let source: ConfigurationSourceRecord
    let load: @MainActor () async throws -> HakoMacNodeScopeChoices
    let initial: ConfigurationNodeScope?
    let save: (ConfigurationNodeScope?) -> Void
    let back: () -> Void
     
     
     
    var closeTitle: HakoDisplayText = .copy("Back")
    @State private var choices: HakoMacNodeScopeChoices?
    @State private var selectedNodes: Set<String> = []
    @State private var selectedCollections: Set<String> = []
    @State private var initialNodes: Set<String> = []
    @State private var initialCollections: Set<String> = []
    @State private var filter = ""
    @State private var showsAllNodes = false
    @State private var error: String?
    @Environment(\.locale) private var locale

     
    static func initialSelection(
        _ scope: ConfigurationNodeScope?, collections: [ConfigurationCollection], nodes: [HakoConfigurationSelectableNode]
    ) -> (nodes: Set<String>, collections: Set<String>) {
        let nodeNames = scope?.includesInlineNodes == false ? Set<String>() : Set(scope?.inlineNodeNames ?? nodes.map(\.name))
        let collectionNames = Set(scope?.providerKeys ?? collections.map(\.name))
        return (nodeNames, collectionNames)
    }

     
     
    static func selection(
        nodes selectedNodes: Set<String>, collections selectedCollections: Set<String>,
        allNodes: [HakoConfigurationSelectableNode], allCollections: [ConfigurationCollection]
    ) -> ConfigurationNodeScope? {
        let everyNode = selectedNodes == Set(allNodes.map(\.name))
        if everyNode && selectedCollections == Set(allCollections.map(\.name)) { return nil }
        return ConfigurationNodeScope(
            includesInlineNodes: !selectedNodes.isEmpty,
            providerKeys: selectedCollections.sorted(),
            inlineNodeNames: everyNode ? nil : selectedNodes.sorted()
        )
    }

    private var dirty: Bool { selectedNodes != initialNodes || selectedCollections != initialCollections }
    private var rowsShownAtOnce: Int { 30 }

    private var needle: String { filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var shownCollections: [ConfigurationCollection] {
        let all = choices?.collections ?? []
        return needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) }
    }
    private var matchingNodes: [HakoConfigurationSelectableNode] {
        let all = choices?.nodes ?? []
        return needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) || $0.type.lowercased().contains(needle) }
    }

    var body: some View {
         
        HakoMacSheetFrame(title: .verbatim(source.label), width: 600, height: 560) {
            HakoMacCardPage {
                TextField(text: $filter) { Text(hako: .copy("Search Nodes")) }
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("configuration-center.scope.filter")
                if let error {
                    Text(verbatim: error).foregroundStyle(.red).font(.subheadline)
                        .accessibilityIdentifier("configuration-center.scope.error")
                }
                if choices == nil, error == nil {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }
                if !shownCollections.isEmpty {
                    HakoMacCardSection(.copy("Node Collections")) {
                        ForEach(Array(shownCollections.enumerated()), id: \.element.id) { index, collection in
                            HakoMacCheckRow(
                                title: .verbatim(collection.name),
                                subtitle: .verbatim(collection.type),
                                isOn: selectedCollections.contains(collection.name),
                                identifier: "configuration-center.scope.collection.\(collection.name)",
                                toggle: { toggle(&selectedCollections, collection.name) }
                            )
                            .hakoMacCardRow(isLast: index == shownCollections.count - 1)
                        }
                    }
                }
                if let choices, !choices.nodes.isEmpty {
                    let expanded = showsAllNodes || matchingNodes.count <= rowsShownAtOnce
                    let shown = expanded ? matchingNodes : Array(matchingNodes.prefix(rowsShownAtOnce))
                    HakoMacCardSection(.copy("Nodes")) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, node in
                            HakoMacCheckRow(
                                title: .verbatim(node.name),
                                subtitle: .verbatim(node.type),
                                isOn: selectedNodes.contains(node.name),
                                identifier: "configuration-center.scope.node.\(node.name)",
                                toggle: { toggle(&selectedNodes, node.name) }
                            )
                            .hakoMacCardRow(isLast: expanded && index == shown.count - 1)
                        }
                        if !expanded {
                            HakoMacShowAllRow(title: .copy("All"), identifier: "configuration-center.scope.show-all") { showsAllNodes = true }
                                .hakoMacCardRow(isLast: true)
                        }
                    }
                }
            }
            .accessibilityIdentifier("configuration-center.scope")
        } trailing: {
            HakoMacSheetButtons(
                closeTitle: closeTitle,
                closeIdentifier: "configuration-center.scope.cancel",
                primaryTitle: .copy("Done"),
                primaryIdentifier: "configuration-center.scope.done",
                primaryDisabled: !dirty || choices == nil,
                onClose: back,
                onPrimary: {
                    guard let choices else { return }
                    save(Self.selection(nodes: selectedNodes, collections: selectedCollections, allNodes: choices.nodes, allCollections: choices.collections))
                }
            )
        }
        .task {
            do {
                let loaded = try await load()
                let seed = Self.initialSelection(initial, collections: loaded.collections, nodes: loaded.nodes)
                selectedNodes = seed.nodes; initialNodes = seed.nodes
                selectedCollections = seed.collections; initialCollections = seed.collections
                choices = loaded
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func toggle(_ set: inout Set<String>, _ name: String) {
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
    }
}
