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
    private enum Route: Hashable { case addSource }

    @ObservedObject private var model: HakoMacConfigurationLibraryModel
    private let actions: HakoMacConfigurationWizardActions
    private let created: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var draft = ConfigurationCreationDraft()
    @State private var creationID = UUID().uuidString.lowercased()
    @State private var path: [Route] = []
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

    public var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                List {
                    switch draft.step {
                    case .sources: sourcesStep
                    case .rules: rulesStep
                    case .finish: finishStep
                    }
                    if let error {
                        Section {
                            Text(verbatim: error).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.wizard.error")
                        }
                    }
                }
                .listStyle(.inset)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .addSource:
                        HakoMacSourceImportPage(
                            purpose: .nodes,
                            actions: actions.sourceImport,
                            accept: { payload in
                                draft.add(payload, rule: nil)
                                path.removeAll()
                            },
                            close: { path.removeAll() }
                        )
                    }
                }
            }
            bar
        }
        .frame(width: 600, height: 560)
        .task { if model.phase == .idle { await model.reload() } }
        .accessibilityIdentifier("configuration-center.wizard")
    }

     

    private var sourcesStep: some View {
        Group {
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
            ForEach(HakoMacConfigurationLibraryModel.nodeShelves(model.snapshot)) { shelf in
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
                NavigationLink(value: Route.addSource) {
                    Label {
                        Text(hako: .copy("Add Source"))
                    } icon: {
                        HakoSymbolImage(symbol: .plusCircle)
                    }
                }
                .accessibilityIdentifier("configuration-center.wizard.add-source")
            } footer: {
                Text(hako: .copy("Subscription links and install links both work."))
            }
        }
    }

    private var rulesStep: some View {
        let selected = HakoMacConfigurationWizardRules.defaultRuleID(draft)
        return Group {
            ForEach(HakoMacConfigurationLibraryModel.ruleShelves(model.snapshot)) { shelf in
                Section {
                    ForEach(shelf.schemes) { scheme in
                        HakoMacChoiceRow(
                            title: .verbatim(scheme.displayLabel),
                            subtitle: .format("Used by %@ configurations", [String(model.configurations(usingScheme: scheme.id).count)]),
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
    }

    private var finishStep: some View {
        Section {
            HakoMacFieldRow(.copy("Name"), prompt: HakoCopy.string("Name", locale: locale), text: $draft.label,
                            identifier: "configuration-center.wizard.name")
                .disabled(busy)
            HakoMacNavigationRowLabel(
                .copy("Node Sources"),
                value: .verbatim((draft.newSources.map(\.record.label)
                    + HakoMacConfigurationWizardRules.chosenSources(draft, in: model.snapshot)
                        .filter { record in !draft.newSources.contains { $0.record.id == record.id } }
                        .map(\.label))
                    .joined(separator: ", "))
            )
            HakoMacNavigationRowLabel(
                .copy("Rule Scheme"),
                value: .verbatim(model.snapshot.effectiveRuleScheme(HakoMacConfigurationWizardRules.defaultRuleID(draft))?.displayLabel ?? "")
            )
        } header: {
            Text(hako: .copy("Configuration"))
        }
    }

     

    private var bar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text(hako: .copy("Cancel"))
            }
            .keyboardShortcut(.cancelAction)
            .disabled(busy)
            .accessibilityIdentifier("configuration-center.wizard.cancel")
            Spacer()
            Text(hako: stepTitle)
                .font(.headline)
                .accessibilityIdentifier("configuration-center.wizard.step")
            Spacer()
            if draft.step != .sources {
                Button(action: back) { Text(hako: .copy("Back")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.wizard.back")
            }
            Button(action: advance) {
                HakoActionProgressLabel(draft.step == .finish ? .copy("Save") : .copy("Next"), isBusy: busy)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdvance)
            .accessibilityIdentifier("configuration-center.wizard.next")
        }
        .padding(HakoTheme.Spacing.row)
        .background(.bar)
    }

    private var stepTitle: HakoDisplayText {
        switch draft.step {
        case .sources: .copy("Select Nodes")
        case .rules: .copy("Select Rules")
        case .finish: .copy("Add Configuration")
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
        Button(action: toggle) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
