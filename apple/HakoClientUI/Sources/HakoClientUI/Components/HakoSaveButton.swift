import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct HakoSaveButton: View {
    private let title: HakoDisplayText
    private let isEnabled: Bool
    private let identifier: String?
    private let action: () async -> Void

    @State private var isSaving = false

    public init(
        _ title: HakoDisplayText = .copy("Save"),
        isEnabled: Bool = true,
        identifier: String? = nil,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button {
             
             
             
            guard !isSaving else { return }
            isSaving = true
            Task {
                await action()
                isSaving = false
            }
        } label: {
            HakoActionProgressLabel(title, isBusy: isSaving)
        }
         
         
        .disabled(isSaving || !isEnabled)
         
         
        .modifier(HakoOptionalIdentifier(identifier: identifier))
         
         
        .accessibilityValue(isSaving ? Text("Saving") : Text(""))
    }
}

 
 
public struct HakoActionProgressLabel: View {
    private let title: HakoDisplayText
    private let isBusy: Bool

    public init(_ title: HakoDisplayText, isBusy: Bool) {
        self.title = title
        self.isBusy = isBusy
    }

    public var body: some View {
        Text(hako: title)
            .opacity(isBusy ? 0 : 1)
            .overlay {
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(Text(hako: title))
            .accessibilityValue(isBusy ? Text("Saving") : Text(""))
    }
}

 
 
 
 
 
struct HakoOptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
