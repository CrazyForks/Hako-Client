import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
public struct HakoMacConfigurationWizardActions {
    public var create: @MainActor (ConfigurationCreationDraft, UInt64, String) async throws -> Void
    public var sourceImport: HakoMacSourceImportActions

    public init(
        create: @escaping @MainActor (ConfigurationCreationDraft, UInt64, String) async throws -> Void,
        sourceImport: HakoMacSourceImportActions
    ) {
        self.create = create
        self.sourceImport = sourceImport
    }

    public static var unavailable: HakoMacConfigurationWizardActions {
        HakoMacConfigurationWizardActions(
            create: { _, _, _ in throw ConfigurationLibraryError.unreadable },
            sourceImport: .unavailable
        )
    }
}

 
 
public enum HakoMacConfigurationWizardRules {
     
     
    public static func canAdvance(_ draft: ConfigurationCreationDraft) -> Bool {
        switch draft.step {
        case .sources: !draft.selectedSourceIDs.isEmpty || !draft.newSources.isEmpty
        case .rules: draft.selectedRuleID != nil
        case .finish: !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

     
     
    public static func suggestedLabel(
        _ draft: ConfigurationCreationDraft,
        in snapshot: ConfigurationLibrarySnapshot
    ) -> String {
        let typed = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if let first = draft.newSources.first { return first.record.label }
        return chosenSources(draft, in: snapshot).first?.label ?? ""
    }

     
     
     
    public static func chosenSources(
        _ draft: ConfigurationCreationDraft,
        in snapshot: ConfigurationLibrarySnapshot
    ) -> [ConfigurationSourceRecord] {
        draft.selectedSourceIDs.compactMap { id in snapshot.availableSources.first { $0.id == id } }
    }

     
     
    public static func defaultRuleID(_ draft: ConfigurationCreationDraft) -> String {
        draft.selectedRuleID ?? ConfigurationBuiltins.basicRuleID
    }
}

 
 
 
 
 
 
 
 
public struct HakoMacConfigurationWizardSheet: View {
    @ObservedObject private var model: HakoMacConfigurationLibraryModel
    private let actions: HakoMacConfigurationWizardActions
    private let created: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var draft = ConfigurationCreationDraft()
    @State private var creationID = UUID().uuidString.lowercased()
    @State private var addingSource = false
    @State private var busy = false
    @State private var error: String?

    public init(
        model: HakoMacConfigurationLibraryModel,
        actions: HakoMacConfigurationWizardActions,
        created: @escaping () -> Void
    ) {
        self.model = model
        self.actions = actions
        self.created = created
    }

    private var canAdvance: Bool { HakoMacConfigurationWizardRules.canAdvance(draft) && !busy }

    private var stepTitle: HakoDisplayText {
        switch draft.step {
        case .sources: .copy("Select Nodes")
        case .rules: .copy("Select Rules")
        case .finish: .copy("Add Profile")
        }
    }

    private var stepSubtitle: HakoDisplayText {
        switch draft.step {
        case .sources: .copy("Node Library")
        case .rules: .copy("Keep the document's nodes, rules and settings.")
        case .finish: .copy("Configuration")
        }
    }

    public var body: some View {
        HakoMacSheetFrame(title: stepTitle, subtitle: draft.step == .finish ? nil : stepSubtitle, width: 600, height: 560) {
            Group {
                switch draft.step {
                case .sources: sourcesStep
                case .rules: rulesStep
                case .finish: finishStep
                }
            }
            .accessibilityIdentifier("configuration-center.wizard")
        } leading: {
            if draft.step != .sources {
                Button(action: back) { Text(hako: .copy("Back")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.wizard.back")
            }
            if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.wizard.error")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.wizard.cancel",
                primaryTitle: draft.step == .finish ? .copy("Save") : .copy("Next"),
                primaryIdentifier: "configuration-center.wizard.next",
                primaryDisabled: !canAdvance,
                isBusy: busy,
                onClose: { dismiss() },
                onPrimary: advance
            )
        }
        .task { if model.phase == .idle { await model.reload() } }
        .sheet(isPresented: $addingSource) {
            HakoMacSourceImportSheet(
                purpose: .nodes,
                actions: actions.sourceImport,
                accept: { payload in
                    draft.add(payload, rule: nil)
                    addingSource = false
                },
                close: { addingSource = false }
            )
        }
    }

     

    private var sourcesStep: some View {
        List {
            if !draft.newSources.isEmpty {
                Section {
                    ForEach(Array(draft.newSources.enumerated()), id: \.offset) { _, payload in
                        HakoMacChoiceRow(
                            title: .verbatim(payload.record.label),
                            subtitle: .verbatim(HakoConfigurationSourceCopy.summary(payload.record, locale: locale)),
                            style: .multiple,
                            isSelected: true,
                            identifier: "configuration-center.wizard.new-source.\(payload.record.id)",
                            toggle: {}
                        )
                    }
                } header: {
                    Text(hako: .copy("Add Source"))
                }
            }
            ForEach(model.nodeShelves) { shelf in
                Section {
                    ForEach(shelf.sources) { source in
                        HakoMacChoiceRow(
                            title: .verbatim(source.label),
                            subtitle: .verbatim(HakoConfigurationSourceCopy.summary(source, locale: locale)),
                            style: .multiple,
                            isSelected: draft.selectedSourceIDs.contains(source.id),
                            identifier: "configuration-center.wizard.source.\(source.id)",
                            toggle: { draft.toggleSource(source.id) }
                        )
                    }
                } header: {
                    Text(hako: .copy(shelf.group.title))
                }
            }
            Section {
                HakoMacListAddRow(.copy("Add Source")) { addingSource = true }
                    .accessibilityIdentifier("configuration-center.wizard.add-source")
            }
        }
        .listStyle(.inset)
    }

    private var rulesStep: some View {
        let selected = HakoMacConfigurationWizardRules.defaultRuleID(draft)
        return List {
            ForEach(model.ruleShelves) { shelf in
                Section {
                    ForEach(shelf.schemes) { scheme in
                        HakoMacChoiceRow(
                            title: .verbatim(scheme.displayLabel),
                            subtitle: .format("Used by %@ profiles", [String(model.usageCount(ofScheme: scheme.id))]),
                            style: .single,
                            isSelected: scheme.id == selected,
                            identifier: "configuration-center.wizard.rule.\(scheme.id)",
                            toggle: { draft.selectedRuleID = scheme.id }
                        )
                    }
                } header: {
                    Text(hako: .copy(shelf.section.title))
                }
            }
        }
        .listStyle(.inset)
    }

    private var finishStep: some View {
        HakoMacSheetForm {
            Section {
                TextField(text: $draft.label, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.wizard.name")
                LabeledContent {
                    Text(verbatim: (draft.newSources.map(\.record.label)
                        + HakoMacConfigurationWizardRules.chosenSources(draft, in: model.snapshot)
                            .filter { record in !draft.newSources.contains { $0.record.id == record.id } }
                            .map(\.label))
                        .joined(separator: ", "))
                } label: {
                    Text(hako: .copy("Node Sources"))
                }
                LabeledContent {
                    Text(verbatim: model.snapshot.effectiveRuleScheme(HakoMacConfigurationWizardRules.defaultRuleID(draft))?.displayLabel ?? "")
                } label: {
                    Text(hako: .copy("Rule Scheme"))
                }
            }
        }
    }

     

    private func back() {
        error = nil
        switch draft.step {
        case .sources: break
        case .rules: draft.step = .sources
        case .finish: draft.step = .rules
        }
    }

    private func advance() {
        guard canAdvance else { return }
        error = nil
        switch draft.step {
        case .sources:
            if draft.selectedRuleID == nil { draft.selectedRuleID = ConfigurationBuiltins.basicRuleID }
            draft.step = .rules
        case .rules:
            draft.label = HakoMacConfigurationWizardRules.suggestedLabel(draft, in: model.snapshot)
            draft.step = .finish
        case .finish:
            save()
        }
    }

    private func save() {
        busy = true
        var candidate = draft
        candidate.label = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.connectAfterCreation = false
        Task { @MainActor in
            defer { busy = false }
            do {
                try await actions.create(candidate, model.snapshot.generation, creationID)
                await model.reload()
                created()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

 
 
 
struct HakoMacChoiceRow: View {
    enum Style { case single, multiple }

    let title: HakoDisplayText
    let subtitle: HakoDisplayText
    let style: Style
    let isSelected: Bool
    let identifier: String
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            Group {
                switch style {
                case .single:
                    if isSelected {
                        HakoSymbolImage(symbol: .checkmark)
                    } else {
                        Color.clear
                    }
                case .multiple:
                    HakoSymbolImage(symbol: isSelected ? .checkmarkCircleFill : .circle)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: HakoTheme.Control.pointerRowTarget)
            VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                Text(hako: title)
                    .fontWeight(style == .single && isSelected ? .semibold : .regular)
                Text(hako: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: HakoTheme.Spacing.row)
        }
        .frame(maxHeight: .infinity)
        .hakoMacPressableRow(toggle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
