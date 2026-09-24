import HakoClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
struct HakoMacPressableRow: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}

extension View {
    func hakoMacPressableRow(_ action: @escaping () -> Void) -> some View {
        modifier(HakoMacPressableRow(action: action))
    }
}

 
 
 
 
 
 
 
 
 
struct HakoMacRoutedRow<Label: View>: View {
    @Environment(\.hakoPushRoute) private var pushRoute
    private let destination: () -> AnyView
    private let label: Label

    init(@ViewBuilder destination: @escaping () -> some View, @ViewBuilder label: () -> Label) {
        self.destination = { AnyView(destination()) }
        self.label = label()
    }

    var body: some View {
        label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hakoMacPressableRow(push)
    }

    private func push() {
        guard let pushRoute else { return }
        let token = UUID()
        HakoViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}, destination)
        pushRoute(HakoViewRoute(id: token))
    }
}

 
 
 
struct HakoMacRoutedInfoButton: View {
    @Environment(\.hakoPushRoute) private var pushRoute
    let identifier: String
    let page: () -> AnyView

    var body: some View {
        Button {
            guard let pushRoute else { return }
            let token = UUID()
            HakoViewRouteRegistry.set(token, ownership: .oneShot, onReturn: {}, page)
            pushRoute(HakoViewRoute(id: token))
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(identifier)
    }
}
