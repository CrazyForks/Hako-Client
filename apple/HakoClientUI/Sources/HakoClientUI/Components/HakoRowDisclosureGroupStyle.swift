import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public struct HakoRowDisclosureGroupStyle: DisclosureGroupStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: HakoTheme.Spacing.compact) {
            Button {
                 
                 
                 
                 
                 
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: HakoTheme.Spacing.tight) {
                    Image(systemName: HakoSymbol.chevronForward.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

public extension View {
     
     
     
     
     
     
    @ViewBuilder
    func hakoRowDisclosure() -> some View {
#if os(macOS)
        if #available(macOS 13.0, *) {
            disclosureGroupStyle(HakoRowDisclosureGroupStyle())
        } else {
            self
        }
#elseif os(iOS) || os(tvOS)
         
         
         
        if #available(iOS 16.0, tvOS 16.0, *) {
            disclosureGroupStyle(HakoLibraryDisclosureGroupStyle())
        } else {
            self
        }
#else
        self
#endif
    }
}

 
 
 
 
 
 
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public struct HakoLibraryDisclosureGroupStyle: DisclosureGroupStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    configuration.label
                    Spacer(minLength: 8)
                    Image(systemName: HakoSymbol.chevronForward.rawValue)
                        .font(.body.weight(.semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
