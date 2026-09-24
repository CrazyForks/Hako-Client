import SwiftUI

extension View {
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func hakoAlwaysEditing() -> some View {
#if os(macOS)
        self
#else
        environment(\.editMode, .constant(.active))
#endif
    }

     
     
     
     
     
     
    @ViewBuilder
    public func hakoBackButtonHidden(_ hidden: Bool) -> some View {
#if os(macOS)
        self
#else
        navigationBarBackButtonHidden(hidden)
#endif
    }
}

extension View {
     
     
     
     
     
     
     
     
    @ViewBuilder
    func hakoEditorFormContainer<Rows: View>(
        @ViewBuilder rows: () -> Rows
    ) -> some View {
#if os(macOS)
        Form { rows() }
            .formStyle(.grouped)
#else
        List { rows() }
#endif
    }
}

 
 
extension View {
    @ViewBuilder
    public func hakoConfigurationFormSpacing() -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(HakoTheme.Spacing.standard)
                .contentMargins(.top, HakoTheme.Spacing.tight, for: .scrollContent)
        } else { self }
        #else
        self
        #endif
    }
}

 
 
 
struct HakoProfilesRootTitleModifier: ViewModifier {
    let showsDismissControl: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsDismissControl {
#if os(iOS)
            content.hakoPageTitle("Profile Center")
#else
            content.hakoPageTitle("Profiles")
#endif
        } else {
            content
        }
    }
}


 
struct HakoConfigurationLibraryList<Content: View>: View {
    let palette: HakoProductPalette
    let accessibilityIdentifier: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        List { content() }
            .modifier(HakoConfigurationLibraryListStyle())
            .hakoConfigurationFormSpacing()
            .background(palette.canvas)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
private struct HakoConfigurationLibraryListStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
#if os(iOS)
        content.listStyle(.insetGrouped)
#else
        content
#endif
    }
}

public extension View {
     
     
    func hakoDeleteConfirmation(_ name: String, isPresented: Binding<Bool>,
                                actionTitle: HakoDisplayText = .copy("Delete"),
                                message: HakoDisplayText,
                                identifier: String,
                                action: @escaping () -> Void) -> some View {
        alert(Text(hako: .format("Delete %@?", [name])), isPresented: isPresented) {
            Button(role: .destructive, action: action) { Text(hako: actionTitle) }
                .accessibilityIdentifier(identifier)
            Button("Cancel", role: .cancel) {}
        } message: { Text(hako: message) }
    }
}
