import HakoClientUI
import SwiftUI

 
 
 
 
 
 
struct HakoMacCardSection<Content: View>: View {
    private let header: HakoDisplayText?
     
    private let footer: HakoDisplayText?
    private let content: () -> Content

    init(_ header: HakoDisplayText? = nil, footer: HakoDisplayText? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(hako: header)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                 
                 
                 
                .padding(.top, -1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.055)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                 
                 
                 
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("hako.mac.card")
            if let footer {
                Text(hako: footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
            }
        }
    }
}

 
 
struct HakoMacCardRow: ViewModifier {
    let isLast: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            if !isLast { Divider().padding(.leading, 12) }
        }
    }
}

 
 
struct HakoMacCardRowAbove: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 12)
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
}

extension View {
    func hakoMacCardRow(isLast: Bool) -> some View { modifier(HakoMacCardRow(isLast: isLast)) }
    func hakoMacCardRow() -> some View { modifier(HakoMacCardRowAbove()) }

     
     
     
     
     
    func hakoMacCardList() -> some View {
        self
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hako.mac.card-list")
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
    }
}

 
 
struct HakoMacCardPage<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content() }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

 
 
struct HakoMacCardButtons<Leading: View, Trailing: View>: View {
    private let leading: () -> Leading
    private let trailing: () -> Trailing

    init(@ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            leading()
            Spacer()
            trailing()
        }
        .menuStyle(.borderedButton)
        .buttonStyle(.bordered)
         
         
        .tint(.primary)
        .padding(.top, -6)
    }
}

extension HakoDisplayText {
     
     
    static func opens(_ key: String, locale: Locale) -> HakoDisplayText {
        .verbatim(HakoCopy.string(key, locale: locale) + "…")
    }

     
     
    static func count(_ count: Int, one: String, other: String) -> HakoDisplayText {
        .format(count == 1 ? one : other, [String(count)])
    }
}

 
 
struct HakoMacCheckRow: View {
    let title: HakoDisplayText
    let subtitle: HakoDisplayText?
    let isOn: Bool
    let identifier: String
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: HakoTheme.Control.pointerRowTarget)
            VStack(alignment: .leading, spacing: 2) {
                Text(hako: title).lineLimit(1)
                if let subtitle {
                    Text(hako: subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: HakoTheme.Spacing.row)
        }
        .hakoMacPressableRow(toggle)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

 
struct HakoMacTickRow: View {
    let title: HakoDisplayText
    let subtitle: HakoDisplayText?
    let isOn: Bool
    let identifier: String
    let select: () -> Void

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            Group {
                if isOn { HakoSymbolImage(symbol: .checkmark).foregroundStyle(Color.accentColor) } else { Color.clear }
            }
            .frame(width: HakoTheme.Control.pointerRowTarget)
            VStack(alignment: .leading, spacing: 2) {
                Text(hako: title).fontWeight(isOn ? .semibold : .regular).lineLimit(1)
                if let subtitle {
                    Text(hako: subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: HakoTheme.Spacing.row)
        }
        .hakoMacPressableRow(select)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

 
struct HakoMacShowAllRow: View {
    let title: HakoDisplayText
    let identifier: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(hako: title).foregroundStyle(Color.accentColor)
            Spacer()
        }
        .hakoMacPressableRow(action)
        .accessibilityIdentifier(identifier)
    }
}
