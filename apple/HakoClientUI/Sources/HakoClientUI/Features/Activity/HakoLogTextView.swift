import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct HakoLogTextView: View {
     
    public struct Request: Sendable {
        public let entries: [HakoActivityLogEntry]
        public let followsEnd: Bool
         
         
         
        public let colorScheme: ColorScheme
    }

     
    nonisolated(unsafe) public static var platformView: (@MainActor (Request) -> AnyView)?

    let entries: [HakoActivityLogEntry]
    let followsEnd: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(entries: [HakoActivityLogEntry], followsEnd: Bool) {
        self.entries = entries
        self.followsEnd = followsEnd
    }

    public var body: some View {
        platformOrPlain
            .accessibilityIdentifier("logs.text")
    }

    @ViewBuilder
    private var platformOrPlain: some View {
        if let make = Self.platformView {
            make(Request(entries: entries, followsEnd: followsEnd, colorScheme: colorScheme))
        } else {
            ScrollView {
                Text(entries.map(\.message).joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
