import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
public struct HakoMacConfigurationWizardActions {
    public var create: @MainActor (ConfigurationCreationDraft, UInt64, String) async throws -> Void
    public var sourceImport: HakoMacSourceImportActions
     
     
     
    public var loadScopeChoices: @MainActor (ConfigurationSourceRecord, ConfigurationSourcePayload?) async throws -> HakoMacNodeScopeChoices = { _, _ in
        throw ConfigurationLibraryError.unreadable
    }
     
     
     
    public var preview: (@MainActor (ConfigurationCreationDraft) async throws -> HakoMacWizardPreview)?

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
     
     
     
     
    @State private var dismiss = HakoDismissHandle()
    @Environment(\.locale) private var locale
    @State private var draft = ConfigurationCreationDraft()
    @State private var creationID = UUID().uuidString.lowercased()
    @State private var addingSource = false
     
    @State private var scopeSourceID: String?
    @State private var confirmsDiscard = false
    @State private var preview: HakoMacWizardPreview?
    @State private var expandedShelves: Set<String> = []
    @State private var busy = false
    @State private var error: String?

    public init(
        model: HakoMacConfigurationLibraryModel,
        actions: HakoMacConfigurationWizardActions,
        initialDraft: ConfigurationCreationDraft? = nil,
        created: @escaping () -> Void
    ) {
        self.model = model
        self.actions = actions
        if let initialDraft { _draft = State(initialValue: initialDraft) }
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
        case .rules: .copy("Rule Library")
        case .finish: .copy("Configuration")
        }
    }

    public var body: some View {
         
         
         
         
        if addingSource {
            HakoMacSourceImportSheet(
                purpose: .nodes,
                actions: actions.sourceImport,
                closeTitle: .copy("Back"),
                accept: { payload in
                    draft.add(payload, rule: nil)
                    addingSource = false
                },
                close: { addingSource = false }
            )
        } else if let scopeSourceID, let source = scopeSource(scopeSourceID) {
             
            HakoMacNodeScopePage(
                source: source,
                load: { [actions] in
                    try await actions.loadScopeChoices(source, draft.newSources.first { $0.record.id == scopeSourceID })
                },
                initial: draft.nodeScopes?[scopeSourceID],
                save: { scope in
                     
                     
                    var scopes = draft.nodeScopes ?? [:]
                    scopes[scopeSourceID] = scope?.isEmpty == true ? nil : scope
                    draft.nodeScopes = scopes.isEmpty ? nil : scopes
                    if scope?.isEmpty == true {
                        draft.selectedSourceIDs.removeAll { $0 == scopeSourceID }
                    } else if !draft.selectedSourceIDs.contains(scopeSourceID) {
                        draft.selectedSourceIDs.append(scopeSourceID)
                    }
                    self.scopeSourceID = nil
                },
                back: { self.scopeSourceID = nil }
            )
        } else {
            wizard
        }
    }

    private func scopeSource(_ id: String) -> ConfigurationSourceRecord? {
        draft.newSources.first { $0.record.id == id }?.record ?? model.snapshot.sources.first { $0.id == id }
    }

     
    private func scopeButton(_ id: String) -> some View {
        Button { scopeSourceID = id } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(hako: .copy("Node Collections")))
            .accessibilityIdentifier("configuration-center.wizard.scope.\(id)")
    }

    private var wizard: some View {
        wizardFrame
             
            .alert(Text(hako: .copy("Discard Changes?")), isPresented: $confirmsDiscard) {
                Button(role: .destructive) { dismiss() } label: { Text(hako: .copy("Discard Changes")) }
                    .accessibilityIdentifier("configuration-center.wizard.discard.confirm")
                Button(role: .cancel) {} label: { Text(hako: .copy("Keep Editing")) }
            } message: {
                Text(hako: .copy("This profile has changes that have not been saved."))
            }
    }

    private var wizardFrame: some View {
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
            if draft.step == .sources {
                 
                 
                Button { addingSource = true } label: { Text(hako: .opens("Add Source", locale: locale)) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.wizard.add-source")
            } else {
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
                onClose: { if draft != ConfigurationCreationDraft() && !busy { confirmsDiscard = true } else { dismiss() } },
                onPrimary: advance
            )
        }
        .task { if model.phase == .idle { await model.reload() } }
        .hakoCapturesDismiss(dismiss)
    }

     

     
    private var rowsShownAtOnce: Int { 30 }

    private var sourcesStep: some View {
        HakoMacCardPage {
            if !draft.newSources.isEmpty {
                 
                 
                HakoMacCardSection(.copy("Add Source")) {
                    ForEach(Array(draft.newSources.enumerated()), id: \.offset) { index, payload in
                         
                        let chosen = draft.selectedSourceIDs.contains(payload.record.id)
                        HStack(spacing: HakoTheme.Spacing.compact) {
                            HakoMacCheckRow(
                                title: .verbatim(payload.record.label),
                                subtitle: .verbatim(HakoConfigurationSourceCopy.summary(payload.record, locale: locale)),
                                isOn: chosen,
                                identifier: "configuration-center.wizard.new-source.\(payload.record.id)",
                                toggle: { draft.toggleSource(payload.record.id) }
                            )
                            if chosen { scopeButton(payload.record.id) }
                        }
                        .hakoMacCardRow(isLast: index == draft.newSources.count - 1)
                    }
                }
            }
            ForEach(model.nodeShelves) { shelf in
                let expanded = expandedShelves.contains(shelf.id) || shelf.sources.count <= rowsShownAtOnce
                let shown = expanded ? shelf.sources : Array(shelf.sources.prefix(rowsShownAtOnce))
                HakoMacCardSection(.copy(shelf.group.title)) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, source in
                        let chosen = draft.selectedSourceIDs.contains(source.id)
                        HStack(spacing: HakoTheme.Spacing.compact) {
                            HakoMacCheckRow(
                                title: .verbatim(source.label),
                                subtitle: .verbatim(HakoConfigurationSourceCopy.summary(source, locale: locale)),
                                isOn: chosen,
                                identifier: "configuration-center.wizard.source.\(source.id)",
                                toggle: { draft.toggleSource(source.id) }
                            )
                            if chosen { scopeButton(source.id) }
                        }
                        .hakoMacCardRow(isLast: expanded && index == shown.count - 1)
                    }
                    if !expanded {
                        HakoMacShowAllRow(title: .copy("All Sources"), identifier: "configuration-center.wizard.show-all") {
                            expandedShelves.insert(shelf.id)
                        }
                        .hakoMacCardRow(isLast: true)
                    }
                }
            }
            if model.nodeShelves.isEmpty && draft.newSources.isEmpty {
                HakoMacCardSection { Text(hako: .copy("None")).foregroundStyle(.secondary).hakoMacCardRow(isLast: true) }
            }
             
             
             
             
            if let candidate = originalCandidate {
                HakoMacCardSection(.copy("Original Configuration")) {
                    VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                        Text(hako: .copy("Use Original Configuration")).foregroundStyle(Color.accentColor)
                         
                        Text(verbatim: candidate.label).font(.subheadline)
                        Text(hako: .copy("Runs the configuration as received, with its own proxy groups, rules and DNS."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hakoMacPressableRow { useOriginal(candidate) }
                    .accessibilityIdentifier("configuration-center.wizard.original")
                    .hakoMacCardRow(isLast: true)
                }
            }
        }
    }

     
     
    private var originalCandidate: (id: String, label: String)? {
        guard draft.selectedSourceIDs.count == 1, let id = draft.selectedSourceIDs.first else { return nil }
        if let staged = draft.newSources.first(where: { $0.record.id == id }) {
            return staged.record.nodeChain == nil ? (id, staged.record.label) : nil
        }
        guard let record = model.snapshot.sources.first(where: { $0.id == id }), record.nodeChain == nil else { return nil }
        return (id, record.label)
    }

     
     
     
    private func useOriginal(_ candidate: (id: String, label: String)) {
        error = nil
        if let staged = draft.newSources.first(where: { $0.record.id == candidate.id }) {
            draft.useOriginal(staged)
        } else {
            var original = ConfigurationCreationDraft()
            original.originalSourceID = candidate.id
            original.selectedSourceIDs = [candidate.id]
            original.label = candidate.label
            original.dnsMode = .source
            original.step = .finish
            draft = original
        }
    }

     
     
    private func schemeSubtitle(_ scheme: ConfigurationRuleScheme) -> HakoDisplayText {
        let base = scheme.baseSchemeID ?? scheme.id
        if base == ConfigurationBuiltins.basicRuleID {
            return .copy("China and local traffic use Direct; other traffic uses your selected nodes.")
        }
        if base == ConfigurationBuiltins.lazyRuleID {
            return .copy("Ready-made routing for AI, streaming, social and gaming services.")
        }
        return .count(model.usageCount(ofScheme: scheme.id), one: "Used by %@ profile", other: "Used by %@ profiles")
    }

    private var rulesStep: some View {
        let selected = HakoMacConfigurationWizardRules.defaultRuleID(draft)
        return HakoMacCardPage {
            ForEach(model.ruleShelves) { shelf in
                HakoMacCardSection(.copy(shelf.section.title)) {
                    ForEach(Array(shelf.schemes.enumerated()), id: \.element.id) { index, scheme in
                        HakoMacTickRow(
                            title: .verbatim(scheme.displayLabel),
                            subtitle: schemeSubtitle(scheme),
                            isOn: scheme.id == selected,
                            identifier: "configuration-center.wizard.rule.\(scheme.id)",
                            select: { draft.selectedRuleID = scheme.id }
                        )
                        .hakoMacCardRow(isLast: index == shelf.schemes.count - 1)
                    }
                }
            }
        }
    }

    private var finishStep: some View {
        HakoMacSheetForm {
            Section {
                TextField(text: $draft.label, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.wizard.name")
                if let originalID = draft.originalSourceID {
                     
                     
                    LabeledContent {
                        Text(verbatim: draft.newSources.first { $0.record.id == originalID }?.record.label
                            ?? model.snapshot.sources.first { $0.id == originalID }?.label ?? "")
                    } label: {
                        Text(hako: .copy("Original Configuration"))
                    }
                    .accessibilityIdentifier("configuration-center.wizard.original-source")
                    Text(hako: .copy("Keep the document's nodes, rules and settings."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
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
             
            if actions.preview != nil {
                Section {
                    LabeledContent {
                        if let preview { Text(verbatim: String(preview.nodes)) } else { ProgressView().controlSize(.small) }
                    } label: {
                        Text(hako: .copy("Nodes"))
                    }
                    .accessibilityIdentifier("configuration-center.wizard.preview.nodes")
                    LabeledContent {
                        if let preview { Text(verbatim: String(preview.rules)) } else { ProgressView().controlSize(.small) }
                    } label: {
                        Text(hako: .copy("Rules"))
                    }
                    .accessibilityIdentifier("configuration-center.wizard.preview.rules")
                }
            }
        }
        .task(id: draft.step) {
            guard draft.step == .finish, let load = actions.preview else { return }
            preview = nil
            preview = try? await load(draft)
        }
    }

     

    private func back() {
        error = nil
        switch draft.step {
        case .sources: break
        case .rules: draft.step = .sources
        case .finish:
            if draft.originalSourceID != nil {
                 
                draft.originalSourceID = nil
                draft.dnsMode = ConfigurationCreationDraft().dnsMode
                draft.step = .sources
            } else {
                draft.step = .rules
            }
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

 
 
public struct HakoMacWizardPreview: Equatable, Sendable {
    public var nodes: Int
    public var rules: Int
    public init(nodes: Int, rules: Int) { self.nodes = nodes; self.rules = rules }
}
