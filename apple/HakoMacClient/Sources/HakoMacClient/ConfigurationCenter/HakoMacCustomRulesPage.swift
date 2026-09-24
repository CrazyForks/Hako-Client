import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
 
public struct HakoMacCustomRule: Identifiable, Equatable, Sendable {
    public var text: String
    public var isEnabled: Bool
    public var comment: String?
    public var id: String { text }

    public init(text: String, isEnabled: Bool = true, comment: String? = nil) {
        self.text = text; self.isEnabled = isEnabled; self.comment = comment
    }
}

public struct HakoMacCustomRulesState: Equatable, Sendable {
    public var rules: [HakoMacCustomRule]
     
     
    public var prepends: Bool

    public init(rules: [HakoMacCustomRule], prepends: Bool) { self.rules = rules; self.prepends = prepends }
    public static let empty = HakoMacCustomRulesState(rules: [], prepends: true)
}

 
 
 
public struct HakoMacCustomRulesActions {
    public var load: @MainActor () async -> HakoMacCustomRulesState
     
    public var save: @MainActor ([HakoMacCustomRule]) async throws -> HakoMacCustomRulesState
    public var setPrepends: @MainActor (Bool) async throws -> HakoMacCustomRulesState
     
     
    public var targets: @MainActor () async throws -> [String]

    public init(
        load: @escaping @MainActor () async -> HakoMacCustomRulesState,
        save: @escaping @MainActor ([HakoMacCustomRule]) async throws -> HakoMacCustomRulesState,
        setPrepends: @escaping @MainActor (Bool) async throws -> HakoMacCustomRulesState,
        targets: @escaping @MainActor () async throws -> [String]
    ) {
        self.load = load; self.save = save; self.setPrepends = setPrepends; self.targets = targets
    }
}

 
 
 
 
 
public struct HakoMacCustomRulesPage: View {
    let actions: HakoMacCustomRulesActions
    @State private var state: HakoMacCustomRulesState
    @State private var adding = false
    @State private var busy = false
    @State private var error: String?

    public init(actions: HakoMacCustomRulesActions, initial: HakoMacCustomRulesState = .empty) {
        self.actions = actions
        _state = State(initialValue: initial)
    }

    public var body: some View {
        List {
            Section {
                ForEach(state.rules) { rule in
                    Toggle(isOn: Binding(get: { rule.isEnabled }, set: { on in setEnabled(rule, on) })) {
                        VStack(alignment: .leading, spacing: HakoTheme.Spacing.tight) {
                            Text(verbatim: rule.text).font(.body.monospaced())
                            if let comment = rule.comment, !comment.isEmpty {
                                Text(verbatim: comment).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(HakoMacCheckboxStyle())
                    .disabled(busy)
                    .contextMenu {
                        Button(role: .destructive) { remove(rule) } label: { Text(hako: .copy("Delete")) }
                            .accessibilityIdentifier("configuration-center.custom-rules.delete")
                    }
                    .accessibilityIdentifier("configuration-center.custom-rules.rule.\(rule.text)")
                }
                .onMove { offsets, destination in
                    var rules = state.rules
                    rules.move(fromOffsets: offsets, toOffset: destination)
                    perform { try await actions.save(rules) }
                }
                HakoMacListAddRow(.copy("Add Rule")) { adding = true }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.custom-rules.add")
            } footer: {
                Text(hako: state.prepends
                    ? .copy("These rules are added in front of the configuration's own rules when it is used.")
                    : .copy("These rules are added after the configuration's own rules when it is used."))
            }
            Section {
                Toggle(isOn: Binding(get: { state.prepends }, set: { on in perform { try await actions.setPrepends(on) } })) {
                    Text(hako: .copy("Insert before profile URL rules"))
                }
                .toggleStyle(.switch)
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.custom-rules.prepend")
            }
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.custom-rules.error")
                }
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("configuration-center.custom-rules")
        .task { state = await actions.load() }
        .sheet(isPresented: $adding) {
            HakoMacAddRuleSheet(
                targets: actions.targets,
                add: { rule in
                    let next = try await actions.save(state.rules + [rule])
                    state = next
                },
                close: { adding = false }
            )
            .hakoModalPresentation(.fitted)
        }
    }

    private func setEnabled(_ rule: HakoMacCustomRule, _ on: Bool) {
        var rules = state.rules
        guard let index = rules.firstIndex(of: rule) else { return }
        rules[index].isEnabled = on
        perform { try await actions.save(rules) }
    }

    private func remove(_ rule: HakoMacCustomRule) {
        perform { try await actions.save(state.rules.filter { $0 != rule }) }
    }

    private func perform(_ operation: @escaping () async throws -> HakoMacCustomRulesState) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { state = try await operation() } catch { self.error = error.localizedDescription }
        }
    }
}

 
 
 
struct HakoMacAddRuleSheet: View {
    let targets: @MainActor () async throws -> [String]
    let add: @MainActor (HakoMacCustomRule) async throws -> Void
    let close: () -> Void
    @State private var action: HakoStructuredRule.Action = .domainSuffix
    @State private var content = ""
    @State private var target = "DIRECT"
    @State private var candidates: [String] = ["DIRECT", "REJECT"]
    @State private var enabled = true
    @State private var comment = ""
    @State private var busy = false
    @State private var error: String?

    private var assembled: String {
        var parts = [action.rawValue]
        if action.needsContent { parts.append(content.trimmingCharacters(in: .whitespacesAndNewlines)) }
        parts.append(target)
        return parts.joined(separator: ",")
    }

    private var canAdd: Bool {
        (!action.needsContent || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !busy
    }

    var body: some View {
        HakoMacSheetFrame(title: .copy("Add Rule"), width: 520, height: 440) {
            HakoMacSheetForm {
                Section {
                    Picker(selection: $action) {
                        ForEach(HakoStructuredRule.Action.allCases, id: \.self) { item in Text(verbatim: item.rawValue).tag(item) }
                    } label: {
                        Text(hako: .copy("Rule Type"))
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.custom-rules.form.action")
                    if action.needsContent {
                        LabeledContent {
                            TextField(text: $content, prompt: Text(verbatim: action.contentPlaceholder)) { Text(verbatim: action.contentLabel) }
                                .labelsHidden()
                                .font(.body.monospaced())
                                .multilineTextAlignment(.trailing)
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.custom-rules.form.content")
                        } label: {
                            Text(verbatim: action.contentLabel)
                        }
                    }
                    Picker(selection: $target) {
                        ForEach(candidates, id: \.self) { name in Text(verbatim: name).tag(name) }
                    } label: {
                        Text(hako: .copy("Policy Groups"))
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.custom-rules.form.target")
                    Toggle(isOn: $enabled) { Text(hako: .copy("Enabled")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.custom-rules.form.enabled")
                    TextField(text: $comment) { Text(hako: .copy("Comment")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.custom-rules.form.comment")
                    LabeledContent { Text(verbatim: assembled).font(.body.monospaced()) } label: { Text(hako: .copy("Rule")) }
                }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration-center.custom-rules.form.error")
                    }
                }
            }
            .task {
                if let loaded = try? await targets(), !loaded.isEmpty {
                    candidates = loaded
                    if !loaded.contains(target) { target = loaded[0] }
                }
            }
        } leading: {
            EmptyView()
        } trailing: {
            HakoMacSheetButtons(
                closeTitle: .copy("Cancel"),
                closeIdentifier: "configuration-center.custom-rules.form.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.custom-rules.form.add",
                primaryDisabled: !canAdd,
                isBusy: busy,
                onClose: close,
                onPrimary: submit
            )
        }
    }

    private func submit() {
        guard canAdd else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                try await add(HakoMacCustomRule(text: assembled, isEnabled: enabled, comment: trimmed.isEmpty ? nil : trimmed))
                close()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
