import HakoClientKit
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct HakoTowerRulesOrderView: View {
    @Binding private var draft: ConfigurationRuleDraft
    private let palette: HakoProductPalette
    private let ruleSetNames: [String: String]
    private let markChanged: () -> Void
    private let close: () -> Void

    @State private var opening: ConfigurationRuleDraft
    @State private var query = ""
    @State private var results = HakoTowerRuleSearchSnapshot()
    @State private var completedRequest: SearchRequest?
    @State private var draggedID: String?
    @State private var dropTarget: HakoReorderDropTarget?

    private struct SearchRequest: Equatable {
        let count: Int
        let query: String
    }

    public init(
        draft: Binding<ConfigurationRuleDraft>,
        palette: HakoProductPalette,
        ruleSetNames: [String: String] = [:],
        markChanged: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        _draft = draft
        _opening = State(initialValue: draft.wrappedValue)
        self.palette = palette
        self.ruleSetNames = ruleSetNames
        self.markChanged = markChanged
        self.close = close
    }

    private var request: SearchRequest {
        .init(count: draft.rows.count, query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public var body: some View {
        let current = request
        let searching = !current.query.isEmpty
        let refreshing = searching && completedRequest != current
        let visible = searching ? results.visible(for: current.query, refreshing: refreshing) : draft.rows
        let lastMovable = visible.lastIndex(where: { !$0.isFinal }) ?? -1
        List {
            Section {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    HakoTowerRuleSummary(row: row, palette: palette, ruleSetNames: ruleSetNames)
                        .deleteDisabled(row.isFinal)
                        .moveDisabled(row.isFinal || searching)
                        .hakoDirectReorderRow(
                            id: row.id.uuidString,
                            label: row.raw,
                            enabled: !row.isFinal && !searching,
                            draggedID: $draggedID,
                            dropTarget: $dropTarget,
                            canMoveUp: index > 0,
                            canMoveDown: index < lastMovable,
                            onMove: { source, destination, edge in drop(source, at: destination, edge: edge, in: visible) },
                            onMoveUp: { step(row.id, -1) },
                            onMoveDown: { step(row.id, 1) }
                        )
                        .accessibilityIdentifier("configuration.rules.order.row")
                }
                .onDelete { offsets in
                    let ids = Set(offsets.compactMap { visible.indices.contains($0) && !visible[$0].isFinal ? visible[$0].id : nil })
                    guard !ids.isEmpty else { return }
                    draft.remove(ids)
                    markChanged()
                }
                .onMove { offsets, destination in
                    guard !searching else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { draft.moveRows(fromOffsets: offsets, toOffset: destination) }
                    markChanged()
                }
                if refreshing && results.query != current.query {
                    ProgressView("Searching…")
                } else if !refreshing && visible.isEmpty {
                    Text("No results").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Current Rules")
                    Spacer()
                    Text(hako: .format("%@ rules", [String(visible.count)])).monospacedDigit()
                }
            } footer: {
                Text("Drag to reorder. Rules match from top to bottom; the final rule stays last.")
            }
        }
        .accessibilityIdentifier("configuration.rules.order")
        .modifier(HakoTowerReorderMode())
        .hakoProductModalSearchable(text: $query, prompt: Text("Search Rules"))
        .hakoPageTitle("Reorder Rules")
        .hakoModalEditorToolbar(
            confirmTitle: "Done",
            confirmationIdentifier: "configuration.rules.order.done",
            onCancel: { draft = opening; close() },
            onConfirm: close
        )
        .task(id: current) {
            guard !current.query.isEmpty else { results = .init(); completedRequest = current; return }
            let source = draft.rows, text = current.query
            let worker = Task.detached(priority: .userInitiated) {
                var result: [ConfigurationRuleDraft.Row] = []
                for row in source {
                    if Task.isCancelled { return result }
                    if row.raw.localizedCaseInsensitiveContains(text) { result.append(row) }
                }
                return result
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { results = .init(query: current.query, rows: result); completedRequest = current }
        }
    }

     
    private func drop(_ sourceID: String, at destinationID: String, edge: HakoReorderDropEdge, in visible: [ConfigurationRuleDraft.Row]) {
        guard let source = UUID(uuidString: sourceID), let destination = UUID(uuidString: destinationID), source != destination else { return }
        let target: UUID?
        switch edge {
        case .before:
            target = destination
        case .after:
            let index = visible.firstIndex { $0.id == destination }
            target = index.flatMap { visible.indices.contains($0 + 1) ? visible[$0 + 1].id : nil }
        }
        withAnimation(.easeInOut(duration: 0.16)) { draft.moveRow(source, before: target) }
        markChanged()
    }

    private func step(_ id: UUID, _ offset: Int) {
        withAnimation(.easeInOut(duration: 0.16)) { draft.moveRow(id, offset: offset) }
        markChanged()
    }
}
