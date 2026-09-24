import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
 
public enum HakoMacConfigurationDoor: Hashable, Sendable, Identifiable {
    public var id: Self { self }
     
    case network
     
    case trust
     
     
    case scheme(String)
}


 
 
struct HakoMacDoorRow: View {
    let title: HakoDisplayText
    let identifier: String
    let open: () -> Void

    init(_ title: HakoDisplayText, identifier: String, open: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.open = open
    }

    var body: some View {
        Button(action: open) {
            HStack {
                Text(hako: title)
                Spacer()
                HakoSymbolImage(symbol: .chevronForward)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

 
public struct HakoMacLibrarySelection: Identifiable, Equatable {
    public let id: String
    public init(id: String) { self.id = id }
}
