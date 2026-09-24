import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
struct HakoTVProfileScriptScreen: View {
    @Binding var store: HakoTVSubscriptionStore
    let id: HakoTVSubscription.ID
     
     
    var onUpdateScript: (() -> Void)?
     
     
    var onDone: (HakoTVSubscription.ID?) -> Void = { _ in }

    @State private var scriptText: String
    @State private var refusal: String?

    init(
        store: Binding<HakoTVSubscriptionStore>,
        id: HakoTVSubscription.ID,
        onUpdateScript: (() -> Void)? = nil,
        onDone: @escaping (HakoTVSubscription.ID?) -> Void = { _ in }
    ) {
        _store = store
        self.id = id
        self.onUpdateScript = onUpdateScript
        self.onDone = onDone
        _scriptText = State(initialValue: Self.seedScript(for: id, in: store.wrappedValue))
    }

    private var hasScript: Bool {
        store.subscriptions.first { $0.id == id }?.scriptURL != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            form
            explanation
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Script URL")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            TextField("Script URL", text: $scriptText, prompt: Text("Optional"))
                .textInputAutocapitalization(.never)
                .onSubmit(save)
                .accessibilityIdentifier("tvos.subscription.script.address")
            Text("Type on your phone instead — the keyboard is already waiting there.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let refusal {
                Text(hako: .verbatim(refusal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tvos.subscription.script.refusal")
            }
            Button("Save", action: save)
                .padding(.top, 8)
                .accessibilityIdentifier("tvos.subscription.script.save")
            if hasScript {
                Button("Update Script") {
                    onUpdateScript?()
                }
                .accessibilityIdentifier("tvos.subscription.script.update")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happens")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Text("The script at this address runs on the profile every time it is fetched, after the rules are applied. Leave it empty to run the profile as it comes. Update Script fetches the same address again.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func save() {
        do {
            let changed = try Self.save(id: id, text: scriptText, in: &store)
            refusal = nil
            onDone(changed ? id : nil)
        } catch {
            refusal = error.localizedDescription
        }
    }

     

     
    static func seedScript(for id: HakoTVSubscription.ID, in store: HakoTVSubscriptionStore) -> String {
        store.subscriptions.first { $0.id == id }?.scriptURL?.absoluteString ?? ""
    }

     
     
     
    @discardableResult
    static func save(id: HakoTVSubscription.ID, text: String, in store: inout HakoTVSubscriptionStore) throws -> Bool {
        let script = try HakoTVSubscriptionStore.scriptURL(from: text)
        let changed = script != store.subscriptions.first { $0.id == id }?.scriptURL
        store.setScriptURL(id, script)
        return changed
    }

     
    static func rowValue(for subscription: HakoTVSubscription) -> String {
        subscription.scriptURL?.host ?? String(localized: "None")
    }
}
