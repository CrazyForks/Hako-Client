import SwiftUI

 
extension View {
    public func hakoUnsavedChangesAlert(
        isPresented: Binding<Bool>,
        message: HakoDisplayText,
        isBusy: Bool,
        saveTitle: String = "Save",
        saveDisabled: Bool = false,
        save: @escaping () -> Void,
        discard: @escaping () -> Void
    ) -> some View {
        alert("Save your changes?", isPresented: isPresented) {
            Button(HakoCopy.key(saveTitle), action: save)
                .disabled(isBusy || saveDisabled)
            Button("Discard", role: .destructive, action: discard)
                .disabled(isBusy)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(hako: message)
        }
    }
}
