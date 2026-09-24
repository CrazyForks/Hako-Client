import AppKit
import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
 
 
 
 
public struct HakoMacSourceImportActions {
     
    public var fetch: @MainActor (String, String) async throws -> ConfigurationSourcePayload
     
     
     
    public var readFile: @MainActor (String, String, [HakoMacImportResourceFile]) async throws -> ConfigurationSourcePayload
     
     
     
    public var importOriginal: (@MainActor (ConfigurationSourcePayload) async throws -> Void)?
     
     
    public var readNodes: (@MainActor (String) async throws -> ConfigurationSourcePayload)?
     
     
     
    public var createQuickRule: (@MainActor (String, Bool, String) async throws -> Void)?
     
     
     
    public var quickRuleTargets: (@MainActor () async throws -> [String])?
     
     
    public var geoValues: HakoMacGeoValueLoader?
     
     
    public var addRuleSet: (@MainActor (HakoMacRuleSetImportDraft) async throws -> Void)?
     
     
     
     
    public var customNodesEditor: ((_ accept: @escaping (ConfigurationSourcePayload) async throws -> Void, _ close: @escaping () -> Void) -> AnyView)? = nil

    public init(
        fetch: @escaping @MainActor (String, String) async throws -> ConfigurationSourcePayload,
        readFile: @escaping @MainActor (String, String, [HakoMacImportResourceFile]) async throws -> ConfigurationSourcePayload,
        importOriginal: (@MainActor (ConfigurationSourcePayload) async throws -> Void)? = nil,
        readNodes: (@MainActor (String) async throws -> ConfigurationSourcePayload)? = nil,
        createQuickRule: (@MainActor (String, Bool, String) async throws -> Void)? = nil
    ) {
        self.fetch = fetch
        self.readFile = readFile
        self.importOriginal = importOriginal
        self.readNodes = readNodes
        self.createQuickRule = createQuickRule
    }

    public static var unavailable: HakoMacSourceImportActions {
        HakoMacSourceImportActions(
            fetch: { _, _ in throw ConfigurationLibraryError.unreadable },
            readFile: { _, _, _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
 
public struct HakoMacImportResourceFile: Equatable, Sendable {
    public let fileName: String
    public let data: Data
    public init(fileName: String, data: Data) { self.fileName = fileName; self.data = data }
}

 
 
public enum HakoMacSourceImportPurpose: Sendable {
    case nodes, rules
}

 
 
 
 
 
 
 
 
 
 
public struct HakoMacSourceImportSheet: View {
    public enum Tab: Int, CaseIterable, Identifiable {
        case link, file, nodes, manual
        public var id: Int { rawValue }
        var title: String {
            switch self {
            case .link: "URL"
            case .file: "File"
            case .nodes: "Node"
            case .manual: "Manual"
            }
        }
    }

    private let purpose: HakoMacSourceImportPurpose
    private let actions: HakoMacSourceImportActions
    private let accept: (ConfigurationSourcePayload) async throws -> Void
    private let close: () -> Void
     
    private let closeTitle: HakoDisplayText
    @Environment(\.locale) private var locale
    @State private var tab: Tab = .link
    @State private var url = ""
    @State private var label = ""
    @State private var fileName = ""
    @State private var text = ""
    @State private var nodesText = ""
    @State private var choosingFile = false
    @State private var preview: ConfigurationSourcePayload?
    @State private var busy = false
    @State private var error: String?
    @State private var ruleAction: HakoStructuredRule.Action = .domainSuffix
    @State private var ruleContent = ""
    @State private var ruleTarget = "DIRECT"
    @State private var ruleEnabled = true
    @State private var ruleComment = ""
    @State private var ruleTargets: [String] = ["DIRECT", "REJECT"]
     
    @State private var pickingGeo = false
    @State private var pickedFrom: HakoMacGeoResource?
    @State private var resources: [HakoMacImportResourceFile] = []
    @State private var pendingTab: Tab?
    @State private var confirmsTabDiscard = false
    @State private var importingRuleSet = false
    @State private var reviewsText = false

    public init(
        purpose: HakoMacSourceImportPurpose,
        actions: HakoMacSourceImportActions,
        initialTab: Tab = .link,
        closeTitle: HakoDisplayText = .copy("Cancel"),
        accept: @escaping (ConfigurationSourcePayload) async throws -> Void,
        close: @escaping () -> Void
    ) {
        self.purpose = purpose
        self.actions = actions
        _tab = State(initialValue: initialTab)
        self.closeTitle = closeTitle
        self.accept = accept
        self.close = close
    }

     
     
    private var tabs: [Tab] {
        var result: [Tab] = [.link, .file]
        if purpose == .nodes, actions.readNodes != nil { result.append(.nodes) }
        if purpose == .rules, actions.createQuickRule != nil { result.append(.manual) }
        return result
    }

    private var title: HakoDisplayText {
        purpose == .nodes ? .copy("Create Nodes") : .copy("Create Rules")
    }

    private var subtitle: HakoDisplayText {
        switch tab {
        case .link: .copy("Profile URL or Share Link")
        case .file: .copy("File")
        case .nodes: .copy("Custom Nodes")
        case .manual: .copy("Add Rule")
        }
    }

    private var assembledRule: String {
        var parts = [ruleAction.rawValue]
        if ruleAction.needsContent { parts.append(ruleContent.trimmingCharacters(in: .whitespacesAndNewlines)) }
        parts.append(ruleTarget)
        return parts.joined(separator: ",")
    }

     
     
     
    private var canAdd: Bool {
        if tab == .manual {
            return (!ruleAction.needsContent || !ruleContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !busy && !pickingGeo
        }
        return canRead
    }

    private var canRead: Bool {
        switch tab {
        case .link: !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
        case .file: !text.isEmpty && !busy
        case .nodes: !nodesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
        case .manual: false
        }
    }

     
     
    private var offersOriginalImport: Bool {
        purpose == .nodes && actions.importOriginal != nil && (tab == .link || tab == .file)
    }

    public var body: some View {
        if importingRuleSet, let addRuleSet = actions.addRuleSet {
             
            HakoMacRuleSetImportForm(add: addRuleSet, back: { importingRuleSet = false }, done: close)
        } else {
            importBody
        }
    }

     
    private var tabIsDirty: Bool {
        switch tab {
        case .link: !url.isEmpty || !label.isEmpty
        case .file: !text.isEmpty || !fileName.isEmpty || !label.isEmpty
        case .nodes: !nodesText.isEmpty
        case .manual: !ruleContent.isEmpty
        }
    }

     
     
    private func requestTab(_ next: Tab) {
        guard next != tab, !busy else { return }
        if tabIsDirty {
            pendingTab = next
            confirmsTabDiscard = true
        } else {
            tab = next
        }
    }

    private func discardTabAndSwitch() {
        switch tab {
        case .link: url = ""; label = ""
        case .file: text = ""; fileName = ""; label = ""; resources = []
        case .nodes: nodesText = ""
        case .manual: ruleContent = ""
        }
        if let pendingTab { tab = pendingTab }
        pendingTab = nil
    }

    private var importBody: some View {
        HakoMacSheetFrame(
            title: pickingGeo ? (ruleAction.hakoMacGeoResource?.rowTitle ?? title) : title,
            subtitle: pickingGeo ? nil : subtitle,
            width: 560, height: 540
        ) {
            if pickingGeo, let resource = ruleAction.hakoMacGeoResource, let load = actions.geoValues {
                HakoMacGeoValuePickerPage(
                    resource: resource, current: ruleContent, load: load,
                    identifier: "configuration-center.import.manual.geo"
                ) { picked in
                    ruleContent = picked
                    pickedFrom = resource
                    pickingGeo = false
                }
            } else {
            VStack(spacing: 0) {
                Picker(selection: Binding(get: { tab }, set: { requestTab($0) })) {
                    ForEach(tabs) { item in
                        Text(hako: .copy(item.title)).tag(item)
                    }
                } label: {
                    Text(hako: title)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 16)
                .accessibilityIdentifier("configuration-center.import.tabs")
                if tab == .nodes, let editor = actions.customNodesEditor {
                     
                     
                     
                    editor(accept, close)
                        .accessibilityIdentifier("configuration-center.import.nodes")
                } else {
                HakoMacSheetForm {
                    switch tab {
                    case .link: linkSection
                    case .file: fileSection
                    case .nodes: nodesSection
                    case .manual: manualSection
                    }
                    if purpose == .rules, actions.addRuleSet != nil, tab == .link || tab == .file {
                         
                        Section {
                             
                             
                            Button { importingRuleSet = true } label: { Text(hako: .opens("Import Rule Set", locale: locale)) }
                                .buttonStyle(.bordered).tint(.primary)
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.import.rule-set")
                        } footer: {
                            Text(hako: .copy("For MRS, Text or YAML rule sets."))
                        }
                    }
                    if let error {
                        Section {
                            Text(verbatim: error).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.import.error")
                        }
                    }
                }
                .accessibilityIdentifier("configuration-center.import")
                }
            }
            }
        } leading: {
            if pickingGeo {
                Button { pickingGeo = false } label: { Text(hako: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.import.manual.geo.back")
            } else if offersOriginalImport {
                Button {
                    run { payload in try await actions.importOriginal?(payload) }
                } label: {
                    Text(hako: .copy("Import Original Configuration"))
                }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.original")
            }
        } trailing: {
            if tab != .nodes || actions.customNodesEditor == nil {
                HakoMacSheetButtons(
                    closeTitle: closeTitle,
                    closeIdentifier: "configuration-center.import.cancel",
                    primaryTitle: .copy("Add"),
                    primaryIdentifier: "configuration-center.import.add",
                    primaryDisabled: !canAdd,
                    isBusy: busy,
                    onClose: close,
                    onPrimary: { if tab == .manual { createRule() } else { run(accept) } }
                )
            }
        }
        .onChange(of: tab) { _ in preview = nil; error = nil }
        .onChange(of: ruleAction) { changed in
             
             
            if changed.hakoMacGeoResource != pickedFrom { ruleContent = ""; pickedFrom = nil }
        }
        .alert(Text(hako: .copy("Discard Changes?")), isPresented: $confirmsTabDiscard) {
            Button(role: .destructive) { discardTabAndSwitch() } label: { Text(hako: .copy("Discard Changes")) }
                .accessibilityIdentifier("configuration-center.import.discard.confirm")
            Button(role: .cancel) { pendingTab = nil } label: { Text(hako: .copy("Keep Editing")) }
        } message: {
            Text(hako: .copy("Switching tabs discards what you have not saved."))
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: Self.fileTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let picked): readPickedFiles(picked)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private static var fileTypes: [UTType] {
        [.plainText, .text, UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml"),
         UTType(filenameExtension: "mrs"), UTType(filenameExtension: "txt")].compactMap { $0 }
    }

     

    private var linkSection: some View {
        Section {
            TextField(text: $url, prompt: Text(verbatim: "https://")) { Text(hako: .copy("URL")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.url")
            TextField(text: $label, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.name")
        }
    }

    private var fileSection: some View {
        Section {
            LabeledContent {
                Button { choosingFile = true } label: { Text(hako: .copy("Choose File")) }
                    .buttonStyle(.bordered).tint(.primary)
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.import.choose-file")
            } label: {
                Text(hako: fileName.isEmpty ? .copy("File") : .verbatim(fileName))
            }
            if !resources.isEmpty {
                LabeledContent {
                    Text(verbatim: resources.map(\.fileName).joined(separator: ", ")).lineLimit(2).truncationMode(.middle)
                } label: {
                    Text(hako: .copy("Files"))
                }
                .accessibilityIdentifier("configuration-center.import.resources")
            }
             
             
             
            LabeledContent {
                Button { pasteConfigurationText() } label: { Text(hako: .copy("Paste")) }
                    .buttonStyle(.bordered).tint(.primary)
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.import.paste")
            } label: {
                Text(hako: .copy("Paste YAML text"))
            }
            if !text.isEmpty {
                 
                 
                Button { reviewsText.toggle() } label: {
                    HStack {
                        Text(hako: .format("Review all %@ lines", [String(lineCount)]))
                        Spacer()
                        HakoSymbolImage(symbol: reviewsText ? .chevronDown : .chevronForward).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configuration-center.import.review")
                if reviewsText {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                        .disabled(busy)
                        .accessibilityLabel(Text(hako: .copy("Paste YAML text")))
                        .accessibilityIdentifier("configuration-center.import.text")
                }
            }
            TextField(text: $label, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.file-name")
        } header: {
            Text(hako: .copy("File"))
        }
    }

    private var lineCount: Int {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    private func pasteConfigurationText() {
        guard let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty else { return }
        text = pasted
        reviewsText = false
        error = nil
    }

     
     
    private var nodesSection: some View {
        Section {
            Text(hako: .copy("Custom Nodes")).foregroundStyle(.secondary)
        } header: {
            Text(hako: .copy("Custom Nodes"))
        }
    }

    private var manualSection: some View {
        Section {
            Picker(selection: $ruleAction) {
                ForEach(HakoStructuredRule.Action.allCases, id: \.self) { item in
                    Text(verbatim: item.rawValue).tag(item)
                }
            } label: {
                Text(hako: .copy("Rule Type"))
            }
            .disabled(busy)
            .accessibilityIdentifier("configuration-center.import.manual.action")
            if let resource = ruleAction.hakoMacGeoResource, actions.geoValues != nil {
                 
                HakoMacGeoValueRow(resource: resource, value: ruleContent, identifier: "configuration-center.import.manual.geo") {
                    pickingGeo = true
                }
                .disabled(busy)
            } else if ruleAction.needsContent {
                 
                 
                 
                LabeledContent {
                    TextField(text: $ruleContent, prompt: Text(verbatim: ruleAction.contentPlaceholder)) { Text(hako: .copy(ruleAction.contentLabel)) }
                        .labelsHidden()
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.import.manual.content")
                } label: {
                    Text(hako: .copy(ruleAction.contentLabel))
                }
            }
             
             
            Picker(selection: $ruleTarget) {
                ForEach(ruleTargets, id: \.self) { name in Text(verbatim: name).tag(name) }
            } label: {
                Text(hako: .copy("Policy Groups"))
            }
            .disabled(busy)
            .accessibilityIdentifier("configuration-center.import.manual.target")
            .task {
                guard let targets = actions.quickRuleTargets else { return }
                if let loaded = try? await targets(), !loaded.isEmpty {
                    ruleTargets = loaded
                    if !loaded.contains(ruleTarget) { ruleTarget = loaded[0] }
                }
            }
            Toggle(isOn: $ruleEnabled) { Text(hako: .copy("Enabled")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.manual.enabled")
            TextField(text: $ruleComment) { Text(hako: .copy("Comment")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.manual.comment")
            LabeledContent { Text(verbatim: assembledRule).font(.body.monospaced()) } label: { Text(hako: .copy("Rule")) }
        } header: {
            Text(hako: .copy("Add Rule"))
        }
    }

     

     
     
    private func readPayload() async throws -> ConfigurationSourcePayload {
        switch tab {
        case .link:
            return try await actions.fetch(url.trimmingCharacters(in: .whitespacesAndNewlines), label)
        case .file:
            let name = fileName.isEmpty ? "Configuration.yaml" : fileName
            return try await actions.readFile(label.isEmpty ? name : label, text, resources)
        case .nodes:
            guard let readNodes = actions.readNodes else { throw ConfigurationLibraryError.unreadable }
            return try await readNodes(nodesText)
        case .manual:
            throw ConfigurationLibraryError.unreadable
        }
    }

    private func run(_ operation: @escaping (ConfigurationSourcePayload) async throws -> Void) {
        guard canRead else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let payload: ConfigurationSourcePayload
                if let preview { payload = preview } else { payload = try await readPayload() }
                preview = payload
                try await operation(payload)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func createRule() {
        guard canAdd, let create = actions.createQuickRule else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await create(assembledRule, ruleEnabled, ruleComment.trimmingCharacters(in: .whitespacesAndNewlines))
                close()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

     
     
     
    private func readPickedFiles(_ picked: [URL]) {
        let configuration = picked.first { ["yaml", "yml"].contains($0.pathExtension.lowercased()) } ?? picked.first
        guard let configuration else { return }
        do {
            var companions: [HakoMacImportResourceFile] = []
            for url in picked {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if url == configuration {
                    text = try String(contentsOf: url, encoding: .utf8)
                } else {
                    companions.append(HakoMacImportResourceFile(fileName: url.lastPathComponent, data: try Data(contentsOf: url)))
                }
            }
            resources = companions
            fileName = configuration.lastPathComponent
            if label.isEmpty { label = configuration.deletingPathExtension().lastPathComponent }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
