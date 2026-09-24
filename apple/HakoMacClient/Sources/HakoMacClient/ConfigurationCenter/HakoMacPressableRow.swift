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
