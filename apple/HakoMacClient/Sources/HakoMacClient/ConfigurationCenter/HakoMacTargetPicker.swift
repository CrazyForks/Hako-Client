import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
 
struct HakoMacTargetRow: View {
    let title: HakoDisplayText
    let value: String
    let identifier: String
    let open: () -> Void

    var body: some View {
        HStack(spacing: HakoTheme.Spacing.compact) {
            Text(hako: title)
            Spacer()
            if !value.isEmpty {
                Text(verbatim: value).foregroundStyle(.secondary).lineLimit(1)
            }
            HakoSymbolImage(symbol: .chevronForward)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .hakoMacPressableRow(open)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(Text(verbatim: value))
    }
}

 
 
 
 
 
struct HakoMacTargetPickerPage: View {
    let candidates: ConfigurationRuleTargetCandidates
    let current: String
    let identifier: String
    let pick: (String) -> Void
    @State private var query = ""

    private var shown: ConfigurationRuleTargetCandidates { candidates.filtered(by: query) }

    private func title(_ section: ConfigurationRuleTargetCandidates.Section) -> HakoDisplayText {
        switch section.kind {
        case .builtin: return .copy("Built-in")
        case .groups: return .copy("Policy Groups")
        case .source: return .verbatim(section.sourceLabel ?? section.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $query, prompt: Text(hako: .copy("Search"))) { Text(hako: .copy("Search")) }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityIdentifier("\(identifier).search")
            Divider()
            if shown.sections.isEmpty {
                HakoMacSheetPlaceholder(title: .copy("No results"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("\(identifier).no-results")
            } else {
                List {
                    ForEach(shown.sections) { section in
                        Section {
                            ForEach(section.names, id: \.self) { name in
                                HStack(spacing: HakoTheme.Spacing.compact) {
                                    Text(verbatim: name)
                                    Spacer()
                                    if name == current {
                                        HakoSymbolImage(symbol: .checkmark).foregroundStyle(.tint)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .hakoMacPressableRow { pick(name) }
                                .accessibilityIdentifier("\(identifier).pick.\(name)")
                            }
                        } header: {
                            Text(hako: title(section))
                        }
                    }
                }
                .hakoMacSettingsList(minRowHeight: HakoMacSettingsMetrics.listRowMinHeight)
            }
        }
    }
}
