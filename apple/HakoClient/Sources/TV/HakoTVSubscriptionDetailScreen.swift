import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct HakoTVSubscriptionDetailScreen: View {
     
     
     
     
    enum Verb: Hashable, CaseIterable {
        case update
        case updateScript
        case rules
        case autoUpdate
        case edit
        case use
        case remove

        var title: String {
            switch self {
            case .update: String(localized: "Update now")
            case .updateScript: String(localized: "Update Script")
            case .rules: String(localized: "Rules")
            case .autoUpdate: String(localized: "Auto update")
            case .edit: String(localized: "Edit")
            case .use: String(localized: "Use this profile")
            case .remove: String(localized: "Remove")
            }
        }

        var identifier: String {
            switch self {
            case .update: "update"
            case .updateScript: "update-script"
            case .rules: "rules"
            case .autoUpdate: "auto-update"
            case .edit: "edit"
            case .use: "use"
            case .remove: "remove"
            }
        }
    }

    @Binding var store: HakoTVSubscriptionStore
    let id: HakoTVSubscription.ID
     
     
    var refresh: HakoTVProductState.Refresh?
     
    var onDone: () -> Void = {}
     
     
     
    var onUpdate: (() -> Void)?
     
     
    var onUpdateScript: (() -> Void)?
     
    var onEdit: () -> Void = {}
     
    var onRules: () -> Void = {}
    var onAutoUpdate: () -> Void = {}

    @State private var asksToRemove = false

    private var subscription: HakoTVSubscription? {
        store.subscriptions.first { $0.id == id }
    }

    private var isCurrent: Bool { store.current?.id == id }

    private var isUpdating: Bool {
        if case .updating(let which, _) = refresh, which == id { return true }
        return false
    }

    private var updateFailure: String? {
        if case .failed(let which, let reason) = refresh, which == id { return reason }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            actions
            explanation
        }
        .alert(Self.removeQuestion, isPresented: $asksToRemove) {
            Button(Verb.remove.title, role: .destructive) {
                store.remove(id)
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.removeMessage(title: subscription?.title ?? ""))
        }
         
    }

    private var actions: some View {
        List {
            Section {
                ForEach(Self.verbs(isCurrent: isCurrent, isFetchable: subscription?.hasFetchableAddress ?? false, hasScript: subscription?.scriptURL != nil), id: \.self) { verb in
                    Button(role: verb == .remove ? .destructive : nil) {
                        perform(verb)
                    } label: {
                        if verb == .update {
                            HStack(spacing: 16) {
                                if isUpdating { ProgressView() }
                                Text(Self.updateRowTitle(updating: isUpdating))
                            }
                        } else if verb == .rules {
                             
                             
                            HStack {
                                Text(verb.title)
                                Spacer()
                                Text(subscription?.effectiveRules.title ?? "")
                                    .foregroundStyle(.secondary)
                            }
                        } else if verb == .autoUpdate {
                            HStack {
                                Text(verb.title)
                                Spacer()
                                Text(HakoTVAutoUpdateScreen.title(forHours: subscription?.updateIntervalHours ?? 0))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(verb.title)
                        }
                    }
                    .disabled(verb == .update && isUpdating)
                    .accessibilityIdentifier("tvos.subscription.\(verb.identifier)")
                }
            }
        }
        .listStyle(.grouped)
        .safeAreaPadding(.horizontal, 44)
        .frame(maxWidth: .infinity)
    }

    private func perform(_ verb: Verb) {
        switch verb {
        case .update:
            if let onUpdate {
                onUpdate()
            } else {
                store.markUpdated(id, at: Date())
            }
        case .updateScript:
            onUpdateScript?()
        case .rules:
            onRules()
        case .autoUpdate:
            onAutoUpdate()
        case .edit:
            onEdit()
        case .use:
            store.use(id)
            onDone()
        case .remove:
            asksToRemove = true
        }
    }

     
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            if let subscription {
                Text(subscription.title)
                    .font(.title2)
                 
                 
                Text(subscription.displayURL.absoluteString)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                Text(Self.status(isCurrent: isCurrent))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(HakoTVSubscriptionUpdatedWords.text(updatedAt: subscription.updatedAt))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tvos.subscription.updated")
                 
                 
                Text(Self.scriptLine(for: subscription))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tvos.subscription.script")
                if let updateFailure {
                     
                     
                     
                    Text(Self.updateFailure(updateFailure))
                        .font(.body)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("tvos.subscription.updateFailure")
                }
            } else {
                Text("This profile is no longer on this Apple TV.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

     

     
     
     
     
     
     
    static func scriptLine(for subscription: HakoTVSubscription) -> String {
        let value = subscription.scriptURL?.host ?? String(localized: "None")
        return "\(String(localized: "Override script")) · \(value)"
    }

    static func verbs(isCurrent: Bool, isFetchable: Bool = true, hasScript: Bool = false) -> [Verb] {
        var verbs: [Verb] = isCurrent ? [.update, .updateScript, .rules, .autoUpdate, .edit, .remove] : [.updateScript, .rules, .autoUpdate, .edit, .use, .remove]
        if !isFetchable { verbs.removeAll { $0 == .rules || $0 == .autoUpdate } }
        if !hasScript { verbs.removeAll { $0 == .updateScript } }
        return verbs
    }

    static func updateRowTitle(updating: Bool) -> String {
        updating ? String(localized: "Updating…") : Verb.update.title
    }

     
    static func updateFailure(_ reason: String) -> String {
        String(localized: "Could not update: \(reason)")
    }

    static var removeQuestion: String { String(localized: "Remove this profile?") }

     
     
     
    static func removeMessage(title: String) -> String {
        String(localized: "Remove “\(title)”? This Apple TV forgets the address. To bring it back, type it again.")
    }

     
    static func status(isCurrent: Bool) -> String {
        isCurrent
            ? String(localized: "In use. The tunnel fetches its configuration from this address.")
            : String(localized: "Not in use. The address stays remembered.")
    }
}
