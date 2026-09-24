import HakoClientUI
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

 
 
 
 
enum HakoLogTextPlatform {
    @MainActor
    static func install() {
        HakoLogTextView.platformView = { request in AnyView(HakoLogTextPlatformView(request: request)) }
    }

     
     
    @MainActor
    static func installIfNeeded() {
        if HakoLogTextView.platformView == nil { install() }
    }
}

private struct HakoLogTextPlatformView: View {
    let request: HakoLogTextView.Request

    var body: some View {
        #if os(iOS)
            HakoLogTextViewIOS(entries: request.entries, followsEnd: request.followsEnd, colorScheme: request.colorScheme)
        #elseif os(macOS)
            HakoLogTextViewMacOS(entries: request.entries, followsEnd: request.followsEnd, colorScheme: request.colorScheme)
        #else
            EmptyView()
        #endif
    }
}

#if os(iOS) || os(macOS)
    #if os(iOS)
        fileprivate typealias HakoLogFont = UIFont
        fileprivate typealias HakoLogColor = UIColor
    #else
        fileprivate typealias HakoLogFont = NSFont
        fileprivate typealias HakoLogColor = NSColor
    #endif

     
     
     
    fileprivate struct HakoLogTextUpdate {
        var replaceAll: Bool
        var deletePrefixLength: Int
        var insertSeparator: Bool
        var appended: NSAttributedString
    }

    @MainActor
    fileprivate final class HakoLogTextCoordinator {
         
         
        fileprivate var appliedIDs: [HakoActivityLogEntry.ID] = []
        fileprivate var appliedLineLengths: [Int] = []
        fileprivate var appliedAppearance: Int?
        private var buildVersion = 0
        private var buildTask: Task<Void, Never>?

        deinit { buildTask?.cancel() }

        enum Strategy: Equatable {
            case noUpdate
            case fullRebuild
            case incremental(appendFrom: Int, dropFirst: Int)
        }

         
         
         
         
        fileprivate func strategy(entries: [HakoActivityLogEntry], appearance: Int) -> Strategy {
            if appliedAppearance != appearance { return .fullRebuild }
            if entries.isEmpty { return appliedIDs.isEmpty ? .noUpdate : .fullRebuild }
            guard let last = appliedIDs.last,
                  let overlap = entries.lastIndex(where: { $0.id == last })
            else { return .fullRebuild }
            let dropFirst = appliedIDs.count - (overlap + 1)
            guard dropFirst >= 0 else { return .fullRebuild }
             
             
            let keptCount = appliedIDs.count - dropFirst
            guard overlap + 1 == keptCount,
                  zip(appliedIDs.dropFirst(dropFirst), entries.prefix(keptCount)).allSatisfy({ $0 == $1.id })
            else { return .fullRebuild }
            if dropFirst == 0, overlap == entries.count - 1 { return .noUpdate }
            return .incremental(appendFrom: overlap + 1, dropFirst: dropFirst)
        }

        fileprivate func schedule(
            entries: [HakoActivityLogEntry],
            strategy: Strategy,
            appearance: Int,
            style: HakoLogTextStyle,
            apply: @escaping @MainActor (HakoLogTextUpdate) -> Void
        ) {
            let startIndex: Int, dropFirst: Int, replaceAll: Bool
            switch strategy {
            case .noUpdate: return
            case .fullRebuild: (startIndex, dropFirst, replaceAll) = (0, 0, true)
            case let .incremental(appendFrom, drop): (startIndex, dropFirst, replaceAll) = (appendFrom, drop, false)
            }
            buildTask?.cancel()
            buildVersion += 1
            let version = buildVersion
            let ids = entries.map(\.id)
             
             
             
            buildTask = Task { @MainActor [weak self] in
                let built = await Task.detached(priority: .userInitiated) {
                    try? HakoLogTextBuilder.build(entries, from: startIndex, style: style)
                }.value
                guard let self, let built, self.buildVersion == version, !Task.isCancelled else { return }
                let update: HakoLogTextUpdate
                let lineLengths: [Int]
                if replaceAll {
                    update = .init(replaceAll: true, deletePrefixLength: 0, insertSeparator: false, appended: built.string)
                    lineLengths = built.lineLengths
                } else {
                     
                    let deleteLength = dropFirst > 0
                        ? self.appliedLineLengths.prefix(dropFirst).reduce(0, +) + dropFirst : 0
                    update = .init(replaceAll: false, deletePrefixLength: deleteLength,
                                   insertSeparator: built.string.length > 0, appended: built.string)
                    lineLengths = Array(self.appliedLineLengths.dropFirst(dropFirst)) + built.lineLengths
                }
                apply(update)
                self.appliedIDs = ids
                self.appliedLineLengths = lineLengths
                self.appliedAppearance = appearance
                self.buildTask = nil
            }
        }
    }

     
     
     
     
     
     
     
    fileprivate struct HakoLogTextStyle: @unchecked Sendable {
        let font: HakoLogFont
        let plain: HakoLogColor
        let dim: HakoLogColor
        let background: HakoLogColor
        let info: HakoLogColor
        let warning: HakoLogColor
        let error: HakoLogColor

        init(font: HakoLogFont, plain: HakoLogColor, dim: HakoLogColor, background: HakoLogColor) {
            self.font = font; self.plain = plain; self.dim = dim; self.background = background
            info = HakoLogColor(red: 0.36, green: 0.68, blue: 0.89, alpha: 1).hakoAdjustedForContrast(against: background)
            warning = HakoLogColor(red: 0.90, green: 0.90, blue: 0.00, alpha: 1).hakoAdjustedForContrast(against: background)
            error = HakoLogColor(red: 1.00, green: 0.13, blue: 0.35, alpha: 1).hakoAdjustedForContrast(against: background)
        }

        func color(for role: HakoLogLineStyler.Role) -> HakoLogColor {
            switch role {
            case .dim: return dim
            case .level(.info): return info
            case .level(.warning): return warning
            case .level(.error): return error
            case .level(.debug): return plain
            case .identity(let hash):
                let rgb = HakoLogLineStyler.identityColor(hash: hash)
                return HakoLogColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
                    .hakoAdjustedForContrast(against: background)
            }
        }
    }

     
    fileprivate final class HakoLogTextBuilt: @unchecked Sendable {
        let string: NSAttributedString
        let lineLengths: [Int]
        init(string: NSAttributedString, lineLengths: [Int]) { self.string = string; self.lineLengths = lineLengths }
    }

    fileprivate enum HakoLogTextBuilder {
         
         
        static func build(
            _ entries: [HakoActivityLogEntry], from start: Int, style: HakoLogTextStyle
        ) throws -> HakoLogTextBuilt {
            let result = NSMutableAttributedString()
            var lineLengths: [Int] = []
            let separator = NSAttributedString(string: "\n", attributes: [.font: style.font, .foregroundColor: style.plain])
            for (offset, entry) in entries[start...].enumerated() {
                if offset % 50 == 0 { try Task.checkCancellation() }
                 
                 
                 
                let line = NSMutableAttributedString(string: entry.text, attributes: [
                    .font: style.font, .foregroundColor: style.plain,
                ])
                for segment in HakoLogLineStyler.segments(of: entry.text, severity: entry.severity)
                where segment.range.upperBound <= line.length {
                    line.addAttribute(.foregroundColor, value: style.color(for: segment.role),
                                      range: NSRange(location: segment.range.lowerBound, length: segment.range.count))
                }
                lineLengths.append(line.length)
                if offset > 0 { result.append(separator) }
                result.append(line)
            }
            return HakoLogTextBuilt(string: result, lineLengths: lineLengths)
        }
    }

     
     
     
    fileprivate extension HakoLogColor {
        var hakoRelativeLuminance: CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if os(macOS)
                (usingColorSpace(.sRGB) ?? self).getRed(&r, green: &g, blue: &b, alpha: &a)
            #else
                getRed(&r, green: &g, blue: &b, alpha: &a)
            #endif
            func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        static func hakoContrast(_ a: HakoLogColor, _ b: HakoLogColor) -> CGFloat {
            let l1 = a.hakoRelativeLuminance, l2 = b.hakoRelativeLuminance
            return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }
        func hakoAdjustedForContrast(against background: HakoLogColor, minRatio: CGFloat = 4.5) -> HakoLogColor {
            if Self.hakoContrast(self, background) >= minRatio { return self }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if os(macOS)
                (usingColorSpace(.sRGB) ?? self).getRed(&r, green: &g, blue: &b, alpha: &a)
            #else
                getRed(&r, green: &g, blue: &b, alpha: &a)
            #endif
            let darken = background.hakoRelativeLuminance > 0.5
            var low: CGFloat = 0, high: CGFloat = 1, best = self
            for _ in 0..<10 {
                let mid = (low + high) / 2
                let candidate = darken
                    ? HakoLogColor(red: r * (1 - mid), green: g * (1 - mid), blue: b * (1 - mid), alpha: a)
                    : HakoLogColor(red: r + (1 - r) * mid, green: g + (1 - g) * mid, blue: b + (1 - b) * mid, alpha: a)
                if Self.hakoContrast(candidate, background) >= minRatio { best = candidate; high = mid } else { low = mid }
            }
            return best
        }
    }

    fileprivate extension NSTextStorage {
        func apply(_ update: HakoLogTextUpdate, separator: [NSAttributedString.Key: Any]) {
            if update.deletePrefixLength > 0 {
                deleteCharacters(in: NSRange(location: 0, length: min(update.deletePrefixLength, length)))
            }
            if update.appended.length > 0 {
                if update.insertSeparator, length > 0 { append(NSAttributedString(string: "\n", attributes: separator)) }
                append(update.appended)
            }
        }
    }
#endif

#if os(iOS)
    private struct HakoLogTextViewIOS: UIViewRepresentable {
        let entries: [HakoActivityLogEntry]
        let followsEnd: Bool
         
        let colorScheme: ColorScheme

        private static func style(for traits: UITraitCollection) -> HakoLogTextStyle {
            HakoLogTextStyle(
                font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                plain: UIColor.label.resolvedColor(with: traits),
                dim: UIColor.secondaryLabel.resolvedColor(with: traits),
                background: UIColor.systemBackground.resolvedColor(with: traits))
        }

        func makeUIView(context _: Context) -> UITextView {
            let view = UITextView()
            view.isEditable = false
            view.isSelectable = true
            view.isScrollEnabled = true
            view.alwaysBounceVertical = true
            view.backgroundColor = .clear
            view.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
            view.textContainer.lineFragmentPadding = 0
            view.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            view.textColor = .label
            view.accessibilityIdentifier = "logs.text"
            return view
        }

        func updateUIView(_ view: UITextView, context: Context) {
             
             
            let appearance = view.traitCollection.userInterfaceStyle.rawValue
            let style = Self.style(for: view.traitCollection)
            let strategy = context.coordinator.strategy(entries: entries, appearance: appearance)
            let followsEnd = followsEnd
            context.coordinator.schedule(
                entries: entries, strategy: strategy, appearance: appearance, style: style
            ) { [weak view] update in
                guard let view else { return }
                let wasAtEnd = Self.isAtEnd(view)
                if update.replaceAll {
                    view.attributedText = update.appended
                } else {
                    view.textStorage.apply(update, separator: [.font: style.font, .foregroundColor: style.plain])
                }
                if followsEnd, update.replaceAll || wasAtEnd { Self.scrollToEnd(view) }
            }
        }

         
        private static func isAtEnd(_ view: UITextView) -> Bool {
            if view.isTracking || view.isDragging || view.isDecelerating { return false }
            let bottom = view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom
            return bottom <= 0 || view.contentOffset.y >= bottom - 44
        }

         
         
         
        private static func scrollToEnd(_ view: UITextView) {
            if #available(iOS 16.0, *), let layout = view.textLayoutManager {
                layout.ensureLayout(for: NSTextRange(location: layout.documentRange.endLocation))
            }
            view.layoutIfNeeded()
            let bottom = view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom
            if bottom > 0 { view.setContentOffset(CGPoint(x: 0, y: bottom), animated: false) }
        }

        func makeCoordinator() -> HakoLogTextCoordinator { HakoLogTextCoordinator() }
    }
#endif

#if os(macOS)
    private struct HakoLogTextViewMacOS: NSViewRepresentable {
        let entries: [HakoActivityLogEntry]
        let followsEnd: Bool
         
        let colorScheme: ColorScheme

        private static func style(dark: Bool) -> HakoLogTextStyle {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
            var plain = NSColor.labelColor, dim = NSColor.secondaryLabelColor, ground = NSColor.textBackgroundColor
            appearance.performAsCurrentDrawingAppearance {
                plain = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
                dim = NSColor.secondaryLabelColor.usingColorSpace(.sRGB) ?? .gray
                ground = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .white
            }
            return HakoLogTextStyle(font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                                    plain: plain, dim: dim, background: ground)
        }

        func makeNSView(context _: Context) -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            let view = NSTextView(usingTextLayoutManager: true)
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.textContainerInset = NSSize(width: 16, height: 12)
            view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            view.textColor = .labelColor
            view.autoresizingMask = [.width]
            if let container = view.textContainer {
                container.widthTracksTextView = true
                container.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
                container.lineFragmentPadding = 0
            }
            view.setAccessibilityIdentifier("logs.text")
            scroll.documentView = view
            return scroll
        }

        func updateNSView(_ scroll: NSScrollView, context: Context) {
            guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
            let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let appearance = dark ? 1 : 0
            let style = Self.style(dark: dark)
            let strategy = context.coordinator.strategy(entries: entries, appearance: appearance)
            let followsEnd = followsEnd
            context.coordinator.schedule(
                entries: entries, strategy: strategy, appearance: appearance, style: style
            ) { [weak view, weak storage] update in
                guard let view, let storage else { return }
                let wasAtEnd = Self.isAtEnd(view)
                if update.replaceAll {
                    storage.setAttributedString(update.appended)
                } else {
                    storage.apply(update, separator: [.font: style.font, .foregroundColor: style.plain])
                }
                if followsEnd, update.replaceAll || wasAtEnd {
                    if let layout = view.textLayoutManager {
                        layout.ensureLayout(for: NSTextRange(location: layout.documentRange.endLocation))
                    }
                    view.scrollToEndOfDocument(nil)
                }
            }
        }

        private static func isAtEnd(_ view: NSTextView) -> Bool {
            guard let scroll = view.enclosingScrollView else { return true }
            return scroll.contentView.bounds.maxY >= view.frame.height - 44
        }

        func makeCoordinator() -> HakoLogTextCoordinator { HakoLogTextCoordinator() }
    }
#endif
