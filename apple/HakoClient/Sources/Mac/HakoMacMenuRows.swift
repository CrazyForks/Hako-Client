import AppKit
import HakoClientUI
import SwiftUI

 
 
 
@MainActor
final class HakoMacMenuRowModel: ObservableObject {
    enum Kind: Equatable {
         
        case member
         
        case test
    }

    let kind: Kind
    let name: String
    @Published var latency: HakoProxyLatencyState
    @Published var isCurrent: Bool
    @Published var isHighlighted = false
    @Published var isTesting = false

    init(
        kind: Kind,
        name: String,
        latency: HakoProxyLatencyState = .untested,
        isCurrent: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.latency = latency
        self.isCurrent = isCurrent
    }

     
     
     
    var badgeText: String {
        switch latency {
        case .measured(let milliseconds): "\(milliseconds) ms"
        case .failed, .timedOut: "—"
        case .untested, .testing: ""
        }
    }
}

 
 
 
 
struct HakoMacMenuRow: View {
    @ObservedObject var model: HakoMacMenuRowModel
    let pointSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
             
            Group {
                if model.isCurrent {
                    Image(systemName: HakoSymbol.checkmark.rawValue)
                        .font(.system(size: pointSize - 2, weight: .semibold))
                } else {
                    Color.clear
                }
            }
            .frame(width: HakoMacMenuRowMetrics.leadingColumn, alignment: .center)

            HakoRegionalFlag.label(model.name, pointSize: pointSize, relativeTo: .body)
                .font(.system(size: pointSize))
                .lineLimit(1)
                .truncationMode(.middle)
                 
                 
                 
                 
                 

            Spacer(minLength: 8)

            switch model.kind {
            case .test:
                 
                 
                if model.isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: HakoSymbol.bolt.rawValue)
                        .font(.system(size: pointSize - 1, weight: .semibold))
                        .foregroundStyle(model.isHighlighted ? .white : .secondary)
                }
            case .member:
                badge
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .padding(.trailing, 8)
        .frame(height: HakoMacMenuRowHost.rowHeight)
        .background(
            model.isHighlighted
                ? Color(nsColor: .selectedContentBackgroundColor)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .padding(.horizontal, HakoMacMenuRowMetrics.highlightInset)
        .foregroundStyle(model.isHighlighted ? Color.white : Color(nsColor: .labelColor))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
    }

     
     
     
     
    @ViewBuilder
    private var badge: some View {
        switch model.latency {
        case .measured:
             
             
             
             
             
             
             
            Text(verbatim: model.badgeText)
                .font(.system(size: pointSize - 3, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(model.isHighlighted ? Color.white : tierInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    tierColor.opacity(model.isHighlighted ? 0.45 : 0.22),
                    in: Capsule()
                )
        case .failed, .timedOut:
            Text(verbatim: model.badgeText)
                .font(.system(size: pointSize - 3, weight: .medium, design: .monospaced))
                .foregroundStyle(model.isHighlighted ? .white : .secondary)
                .padding(.horizontal, 6)
        case .testing:
            ProgressView()
                .controlSize(.mini)
        case .untested:
            EmptyView()
        }
    }

     
     
    private var tierColor: Color {
        switch model.latency.tier {
        case .fast: .green
        case .slow: .yellow
        case .slower: .orange
        case nil: .secondary
        }
    }

     
     
     
     
    private var tierInk: Color {
        let tier = tierColor
        return Color(nsColor: NSColor(name: nil) { appearance in
            let base = NSColor(tier)
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua { return base }
            return base.blended(withFraction: 0.4, of: .black) ?? base
        })
    }

    private var accessibilityDescription: String {
        var parts = [model.name]
        if !model.badgeText.isEmpty { parts.append(model.badgeText) }
        if model.isCurrent { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}

 
 
 
 
 
 
 
 
 
@MainActor
final class HakoMacMenuRowHost: NSHostingView<HakoMacMenuRow> {
     
     
     
     
     
    static let rowHeight: CGFloat = {
        func height(rows: Int) -> CGFloat {
            let menu = NSMenu()
            for _ in 0..<rows {
                menu.addItem(NSMenuItem(title: "Sample", action: nil, keyEquivalent: ""))
            }
            return menu.size.height
        }
        let measured = height(rows: 2) - height(rows: 1)
        return measured > 0 ? measured : 22
    }()

    var model: HakoMacMenuRowModel { rootView.model }
     
     
    var closesMenuOnClick = true
    var onClick: () -> Void = {}

    static func make(
        model: HakoMacMenuRowModel,
        width: CGFloat,
        pointSize: CGFloat,
        closesMenuOnClick: Bool,
        onClick: @escaping () -> Void
    ) -> HakoMacMenuRowHost {
        let host = HakoMacMenuRowHost(rootView: HakoMacMenuRow(model: model, pointSize: pointSize))
        host.closesMenuOnClick = closesMenuOnClick
        host.onClick = onClick
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: width, height: rowHeight)
        host.autoresizingMask = [.width]
        return host
    }

    required init(rootView: HakoMacMenuRow) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HakoMacMenuRowHost is built in code")
    }

    override func mouseUp(with event: NSEvent) {
        performClick()
    }

     
     
    func performClick() {
        if closesMenuOnClick {
            enclosingMenuItem?.menu?.cancelTracking()
        }
        onClick()
    }
}

 
 
 
 
 
 
 
@MainActor
enum HakoMacMenuRowMetrics {
    static var font: NSFont { NSFont.menuFont(ofSize: 0) }
    static var pointSize: CGFloat { font.pointSize }

     
     
     
    static let memberCap: CGFloat = 300

     
    static let highlightInset: CGFloat = 5
     
     
    static let leadingColumn: CGFloat = 19

     
     
     
    private static let chrome: CGFloat = highlightInset * 2 + leadingColumn + 8 + 8

    private static func widest(_ strings: [String]) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (strings + [""]).map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
    }

     
     
     
    static func memberRowWidth(names: [String]) -> CGFloat {
        let sample = HakoMacMenuRowModel(kind: .member, name: "", latency: .measured(milliseconds: 999)).badgeText
        let badge = (sample as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize - 3, weight: .medium),
        ]).width + 12
        return min(memberCap, (chrome + widest(names) + badge).rounded(.up))
    }
}

 
 
 
 
 
 
 
 
@MainActor
final class HakoMacProxySubmenuController: NSObject, NSMenuDelegate {
    private let group: () -> HakoMacMenuProxyCatalog.Group?
    private let actions: HakoMacStatusMenuActions
    private let locale: Locale
    private(set) var rows: [String: HakoMacMenuRowModel] = [:]
    private(set) var testRow: HakoMacMenuRowModel?

     
    var groupName: String? { group()?.name }

    init(
        group: @escaping () -> HakoMacMenuProxyCatalog.Group?,
        actions: HakoMacStatusMenuActions,
        locale: Locale
    ) {
        self.group = group
        self.actions = actions
        self.locale = locale
    }

     
     
     
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.items.isEmpty else { return }
        rows = [:]
        testRow = nil
        guard let group = group() else { return }
        let pointSize = HakoMacMenuRowMetrics.pointSize
        let width = HakoMacMenuRowMetrics.memberRowWidth(
            names: group.members + [HakoCopy.string("Test latency", locale: locale)]
        )

        let test = HakoMacMenuRowModel(kind: .test, name: HakoCopy.string("Test latency", locale: locale))
        let testItem = NSMenuItem(title: test.name, action: nil, keyEquivalent: "")
        testItem.setAccessibilityIdentifier("menu-bar.test-group")
        testItem.view = HakoMacMenuRowHost.make(
            model: test, width: width, pointSize: pointSize, closesMenuOnClick: false
        ) { [weak self, weak test] in
            test?.isTesting = true
            self?.actions.testGroup(group.name)
        }
        testRow = test
        menu.addItem(testItem)
        menu.addItem(.separator())

        for member in group.members {
             
            let isCurrent = member == group.checked
            let model = HakoMacMenuRowModel(
                kind: .member,
                name: member,
                latency: group.latency[member] ?? .untested,
                isCurrent: isCurrent
            )
            let pick = { [actions] in
                 
                 
                guard !isCurrent || group.pinsOnRepick else { return }
                actions.select(group.name, member)
            }
            let target = HakoMacMenuRowAction(pick)
            let item = NSMenuItem(
                title: member,
                action: #selector(HakoMacMenuRowAction.fire(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = target
            item.state = isCurrent ? .on : .off
            item.view = HakoMacMenuRowHost.make(
                model: model, width: width, pointSize: pointSize, closesMenuOnClick: true, onClick: pick
            )
            rows[member] = model
            menu.addItem(item)
        }
    }

     
     
     
     
     
    func menuDidClose(_ menu: NSMenu) {
        for item in menu.items {
            (item.view as? HakoMacMenuRowHost)?.model.isHighlighted = false
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for candidate in menu.items {
            (candidate.view as? HakoMacMenuRowHost)?.model.isHighlighted = candidate === item
        }
    }

     
    func apply(latency: [String: HakoProxyLatencyState]) {
        for (name, model) in rows {
            if let fresh = latency[name], fresh != model.latency {
                model.latency = fresh
            }
        }
    }

    func setTesting(_ isTesting: Bool) {
        testRow?.isTesting = isTesting
    }
}
