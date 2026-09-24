import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct HakoTVNodesScreen: View {
    @Binding var state: HakoTVProductState
     
     
     
    var onPin: ((_ member: String, _ group: String) -> Void)?
     
     
    var onTestAll: ((HakoProxyGroupSnapshot) -> Void)?
     
    var onTest: ((HakoProxyMemberSnapshot) -> Void)?

    @State private var shownGroupName: String?

     
     
    private var browsingMode: HakoTVOutboundMode {
        state.observations.mode.hasValue ? state.outboundMode : .rule
    }

     
    private var visibleGroups: [HakoProxyGroupSnapshot] {
        guard state.observations.proxies.hasValue else { return [] }
        return Self.visibleGroups(state.proxyGroups, mode: browsingMode)
    }

     
     
     
     
     
    private var shownGroup: HakoProxyGroupSnapshot? {
        visibleGroups.first { $0.name == shownGroupName } ?? visibleGroups.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HakoTVObservationNote(observations: [state.observations.proxies, state.observations.mode])
            HStack(alignment: .top, spacing: 40) {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if vacancy != .directMode {
                    groups
                        .frame(maxWidth: 520)
                }
                grid
                    .focusSection()
            }
        }
    }

    private var vacancy: Vacancy? {
        guard state.observations.proxies.hasValue else { return .noGroups }
        return Self.vacancy(mode: state.observations.mode.hasValue ? state.outboundMode : .rule, visibleGroups: visibleGroups)
    }

     

    private var groups: some View {
        List {
            Section("Policy groups") {
                ForEach(visibleGroups) { group in
                    Button {
                        shownGroupName = group.name
                    } label: {
                        LabeledContent {
                            Text(Self.groupRowValue(for: group))
                        } label: {
                            Text(group.name)
                            Text(Self.groupRowSubtitle(for: group, state: state))
                        }
                    }
                     
                     
                     
                     
                    .onHakoTVFocus { shownGroupName = group.name }
                    .accessibilityIdentifier("tvos.nodes.group.\(group.name)")
                }
            }
        }
        .listStyle(.grouped)
        .safeAreaPadding(.horizontal, 44)
    }

     

    @ViewBuilder
    private var grid: some View {
        if let group = shownGroup {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.header(for: group, mode: browsingMode))
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 20)
                    if Self.offersTestAll(for: group) {
                         
                         
                         
                         
                         
                        Button {
                            onTestAll?(group)
                        } label: {
                            Text(Self.testAllTitle(isTesting: Self.isTesting(group, state: state)))
                                .font(.caption)
                        }
                        .accessibilityIdentifier("tvos.nodes.test-all")
                    }
                }
                if let refusal = group.memberChoiceRefusal {
                     
                    Text(refusal.localizedForTelevision)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: Self.columnCount(for: group, mode: browsingMode)),
                        alignment: .leading,
                        spacing: 20
                    ) {
                        ForEach(Self.browsedMembers(of: group, mode: browsingMode)) { member in
                            cell(member, in: group)
                        }
                    }
                     
                     
                     
                     
                     
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            switch vacancy {
            case .directMode:
                directModeNotice
            case .noGroups, .none:
                Text(state.observations.proxies.hasValue ? String(localized: "No policy groups in this configuration") : "—")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

     
     
     
     
     
     
    private var directModeNotice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: HakoSymbol.arrowLeftAndRight.rawValue)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Direct Mode")
                .font(.title3)
            Text("This mode sends all traffic without a proxy, so proxy groups and nodes are not listed.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("tvos.nodes.direct-mode-notice")
    }

    private func cell(_ member: HakoProxyMemberSnapshot, in group: HakoProxyGroupSnapshot) -> some View {
        let inUse = group.currentSelection == member.name
        return Button {
            if let onPin {
                onPin(member.name, group.name)
            } else {
                Self.select(member: member.name, in: group.name, state: &state)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                     
                     
                     
                     
                     
                    Text(member.name)
                        .font(Self.nameFont)
                        .lineLimit(Self.nameLineLimit)
                        .minimumScaleFactor(Self.nameMinimumScale)
                        .multilineTextAlignment(.leading)
                    if inUse {
                        Image(systemName: HakoSymbol.checkmark.rawValue)
                            .font(Self.nameFont)
                            .accessibilityLabel("In use")
                    }
                }
                HStack {
                    Text(Self.typeLabel(for: member, state: state))
                        .font(Self.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(Self.readingLabel(for: member, state: state))
                        .font(Self.detailFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("tvos.nodes.member.\(member.name)")
        .accessibilityAddTraits(inUse ? .isSelected : [])
         
         
         
         
         
         
         
         
        .contextMenu {
            if let onTest {
                Button(Self.testOneTitle) { onTest(member) }
            }
        }
    }

     

     
     
     
     
     
     
    static let nameFont: Font = .body
    static let detailFont: Font = .caption

     
    static let nameLineLimit = 2

     
     
     
    static let nameMinimumScale: CGFloat = 0.8

     
     
     
     
     
     
     
    static let longNameThreshold = 48

     
     
     
     
     
    static func columnCount(for group: HakoProxyGroupSnapshot) -> Int {
        columnCount(for: group.members)
    }

     
    static func columnCount(for group: HakoProxyGroupSnapshot, mode: HakoTVOutboundMode) -> Int {
        columnCount(for: browsedMembers(of: group, mode: mode))
    }

    private static func columnCount(for members: [HakoProxyMemberSnapshot]) -> Int {
        let longest = members.map(\.name.count).max() ?? 0
        return longest > longNameThreshold ? 2 : 3
    }

     
    enum Vacancy: Equatable {
         
         
        case directMode
         
        case noGroups
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func browsedMembers(of group: HakoProxyGroupSnapshot, mode: HakoTVOutboundMode) -> [HakoProxyMemberSnapshot] {
        ProxyBrowsingVisibility.members(
            group.members,
            of: group.name,
            mode: .init(coreValue: mode.kernelToken),
            name: { $0.name }
        )
    }

    static func visibleGroups(
        _ groups: [HakoProxyGroupSnapshot],
        mode: HakoTVOutboundMode
    ) -> [HakoProxyGroupSnapshot] {
        ProxyBrowsingVisibility.groups(
            groups,
            mode: .init(coreValue: mode.kernelToken),
            name: { $0.name },
            isHidden: { _ in false }
        )
    }

     
     
     
     
     
     
    static func vacancy(
        mode: HakoTVOutboundMode,
        visibleGroups: [HakoProxyGroupSnapshot]
    ) -> Vacancy? {
        if mode == .direct { return .directMode }
        return visibleGroups.isEmpty ? .noGroups : nil
    }

    static func select(member: String, in groupName: String, state: inout HakoTVProductState) {
        state.pin(member: member, in: groupName)
    }

     
     
    static func header(for group: HakoProxyGroupSnapshot) -> String {
        header(for: group, count: group.isEmpty ? 0 : group.members.count)
    }

     
    static func header(for group: HakoProxyGroupSnapshot, mode: HakoTVOutboundMode) -> String {
        header(for: group, count: group.isEmpty ? 0 : browsedMembers(of: group, mode: mode).count)
    }

    private static func header(for group: HakoProxyGroupSnapshot, count: Int) -> String {
        count == 1
            ? String(localized: "\(group.name) · 1 node · \(group.type)")
            : String(localized: "\(group.name) · \(count) nodes · \(group.type)")
    }

     
     
    static var testOneTitle: String { String(localized: "Test") }

     
     
     
    static func testAllTitle(isTesting: Bool) -> String {
        isTesting ? String(localized: "Testing…") : String(localized: "Test all")
    }

     
     
     
     
    static func offersTestAll(for group: HakoProxyGroupSnapshot) -> Bool {
        !group.isEmpty && !group.members.isEmpty
    }

     
     
     
     
    static func group(named name: String, state: HakoTVProductState) -> HakoProxyGroupSnapshot? {
        state.proxyGroups.first { $0.name == name } ?? state.hiddenProxyGroups.first { $0.name == name }
    }

     
     
     
    static func isEmptyGroup(_ member: HakoProxyMemberSnapshot, state: HakoTVProductState) -> Bool {
        member.isGroup && group(named: member.name, state: state)?.isEmpty == true
    }

     
     
     
     
     
     
     
     
     
    static func displayedLatency(for member: HakoProxyMemberSnapshot, state: HakoTVProductState) -> HakoProxyLatencyState {
        if isEmptyGroup(member, state: state) { return .untested }
        let direct = state.latency[member.name] ?? .untested
        guard direct == .untested, member.isGroup,
              let group = group(named: member.name, state: state),
              let route = group.resolvedRuntimeRoute ?? group.runtimeSelection
        else { return direct }
        return state.latency[route] ?? .untested
    }

     
     
     
    static func displayedLatency(forGroup group: HakoProxyGroupSnapshot, state: HakoTVProductState) -> HakoProxyLatencyState {
        displayedLatency(for: HakoProxyMemberSnapshot(name: group.name, type: group.type, isGroup: true), state: state)
    }

     
     
     
    static func readingLabel(for member: HakoProxyMemberSnapshot, state: HakoTVProductState) -> String {
        if isEmptyGroup(member, state: state) { return "" }
        return latencyLabel(
            displayedLatency(for: member, state: state),
            failureCategory: state.failureReasons[member.name] ?? ""
        )
    }

     
     
     
     
     
     
    static func groupRowSubtitle(for group: HakoProxyGroupSnapshot, state: HakoTVProductState) -> String {
        if group.isEmpty { return "\(group.type) \(noNodes)" }
        guard let selection = group.currentSelection else { return group.type }
        if case .measured(let milliseconds) = displayedLatency(forGroup: group, state: state) {
            return "\(group.type) · \(selection) (\(latencyLabel(.measured(milliseconds: milliseconds))))"
        }
        return "\(group.type) · \(selection)"
    }

     
     
     
    static func groupRowValue(for group: HakoProxyGroupSnapshot) -> String {
        group.isEmpty ? "—" : (group.currentSelection ?? "—")
    }

     
     
     
     
     
    static func typeLabel(for member: HakoProxyMemberSnapshot, state: HakoTVProductState) -> String {
        if state.easyTierNodeNames.contains(member.name) {
            return String(localized: "easytier · Not supported")
        }
        if isEmptyGroup(member, state: state) {
            return "\(member.type) \(noNodes)"
        }
        return member.type
    }

     
     
    private static var noNodes: String { String(localized: "· No nodes") }

     
     
     
    static func sweepMembers(of group: HakoProxyGroupSnapshot, state: HakoTVProductState) -> [HakoProxyMemberSnapshot] {
        guard !group.isEmpty else { return [] }
        return group.members.filter { !isEmptyGroup($0, state: state) }
    }

    static func isTesting(_ group: HakoProxyGroupSnapshot, state: HakoTVProductState) -> Bool {
        group.members.contains { state.latency[$0.name] == .testing }
    }

     
     
     
     
     
     
    static func beginTesting(_ group: HakoProxyGroupSnapshot, state: inout HakoTVProductState) {
        for member in sweepMembers(of: group, state: state) {
            state.latency[member.name] = .testing
        }
    }

     
     
     
     
     
     
     
    static func record(delay: Int, for member: String, state: inout HakoTVProductState) {
        state.latency[member] = HakoProxyLatencyState.measured(milliseconds: delay).normalized
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func merge(
        polled: [String: HakoProxyLatencyState],
        over current: [String: HakoProxyLatencyState],
        sweeping: Set<String>
    ) -> [String: HakoProxyLatencyState] {
        guard !sweeping.isEmpty else { return polled }
        var merged = polled
        for name in sweeping {
            merged[name] = current[name]
        }
        return merged
    }

     
     
    static func latencyLabel(
        _ state: HakoProxyLatencyState,
        failureCategory: String = ""
    ) -> String {
        switch state {
        case .measured(let milliseconds): String(localized: "\(milliseconds) ms")
        case .untested: "—"
        case .testing: "…"
         
         
         
        case .failed, .timedOut:
            String(
                localized: String.LocalizationValue(
                    HakoProbeFailureCopy.badge(
                        for: state == .timedOut ? "timeout" : failureCategory
                    )
                )
            )
        }
    }
}
