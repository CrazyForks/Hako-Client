import HakoClientUI
import SwiftUI

 
public enum HakoMacGeoResource: String, Sendable {
    case geoIP, geoSite
}

 
 
 
public typealias HakoMacGeoValueLoader = @MainActor (HakoMacGeoResource) async -> [String]

extension HakoStructuredRule.Action {
     
     
     
     
     
     
    var hakoMacGeoResource: HakoMacGeoResource? {
        switch self {
        case .geoip, .srcGeoIP: .geoIP
        case .geosite: .geoSite
        default: nil
        }
    }
}

extension HakoMacGeoResource {
     
    var rowTitle: HakoDisplayText {
        switch self {
        case .geoIP: .copy("Country / Region")
        case .geoSite: .copy("Category")
        }
    }

     
    func regionName(_ code: String) -> String? {
        guard self == .geoIP, code.count == 2 else { return nil }
        return Locale.current.localizedString(forRegionCode: code.uppercased())
    }

     
     
    func display(_ value: String) -> String {
        self == .geoIP && value.count == 2 ? value.uppercased() : value
    }

     
    func ruleValue(_ picked: String) -> String {
        self == .geoIP ? picked.uppercased() : picked
    }
}

 
 
 
struct HakoMacGeoValueRow: View {
    let resource: HakoMacGeoResource
    let value: String
    let identifier: String
    let open: () -> Void

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            Text(hako: resource.rowTitle)
            Spacer()
            if !value.isEmpty {
                Text(verbatim: resource.display(value)).font(.body.monospaced()).foregroundStyle(.secondary)
                if let name = resource.regionName(value) {
                    Text(verbatim: name).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HakoSymbolImage(symbol: .chevronForward)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .hakoMacPressableRow(open)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(Text(verbatim: resource.display(value)))
    }
}

 
 
 
 
struct HakoMacGeoValuePickerPage: View {
    let resource: HakoMacGeoResource
    let current: String
    let load: HakoMacGeoValueLoader
    let identifier: String
    let pick: (String) -> Void
    @State private var query = ""
    @State private var values: [String] = []
    @State private var loaded = false

    private var filtered: [String] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return values }
        let folded = needle.lowercased()
        return values.filter { value in
            value.contains(folded)
                || (resource.regionName(value)?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $query, prompt: Text(hako: .copy("Search code or name"))) {
                Text(hako: .copy("Search code or name"))
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityIdentifier("\(identifier).search")
            Divider()
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                HakoMacSheetPlaceholder(title: .copy("No results"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("\(identifier).no-results")
            } else {
                List(filtered, id: \.self) { value in
                    HStack(spacing: HakoTheme.Spacing.compact) {
                        Text(verbatim: resource.display(value)).font(.body.monospaced())
                        if let name = resource.regionName(value) {
                            Text(verbatim: name).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if value == current.lowercased() {
                            HakoSymbolImage(symbol: .checkmark).foregroundStyle(.tint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hakoMacPressableRow { pick(resource.ruleValue(value)) }
                    .accessibilityIdentifier("\(identifier).pick.\(value)")
                }
                 
                 
                 
                 
                 
                .hakoMacSettingsList(minRowHeight: HakoMacSettingsMetrics.listRowMinHeight)
            }
        }
        .task {
            guard !loaded else { return }
            values = await load(resource)
            loaded = true
        }
    }
}
