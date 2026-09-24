import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
 
 
 
 
public struct HakoMacSourceImportActions {
     
    public var fetch: @MainActor (String, String) async throws -> ConfigurationSourcePayload
     
    public var readFile: @MainActor (String, String) async throws -> ConfigurationSourcePayload
     
     
     
    public var importOriginal: (@MainActor (ConfigurationSourcePayload) async throws -> Void)?
     
     
    public var readNodes: (@MainActor (String) async throws -> ConfigurationSourcePayload)?
     
     
    public var createQuickRule: (@MainActor (String) async throws -> Void)?

    public init(
        fetch: @escaping @MainActor (String, String) async throws -> ConfigurationSourcePayload,
        readFile: @escaping @MainActor (String, String) async throws -> ConfigurationSourcePayload,
        importOriginal: (@MainActor (ConfigurationSourcePayload) async throws -> Void)? = nil,
        readNodes: (@MainActor (String) async throws -> ConfigurationSourcePayload)? = nil,
        createQuickRule: (@MainActor (String) async throws -> Void)? = nil
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
            readFile: { _, _ in throw ConfigurationLibraryError.unreadable }
        )
    }
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
            case .nodes: "Nodes"
            case .manual: "Manual"
            }
        }
    }

    private let purpose: HakoMacSourceImportPurpose
    private let actions: HakoMacSourceImportActions
    private let accept: (ConfigurationSourcePayload) async throws -> Void
    private let close: () -> Void
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

    public init(
        purpose: HakoMacSourceImportPurpose,
        actions: HakoMacSourceImportActions,
        accept: @escaping (ConfigurationSourcePayload) async throws -> Void,
        close: @escaping () -> Void
    ) {
        self.purpose = purpose
        self.actions = actions
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
        purpose == .nodes ? .copy("Add Source") : .copy("Add Rule Scheme")
    }

    private var subtitle: HakoDisplayText {
        switch tab {
        case .link: .copy("Profile URL or Share Link")
        case .file: .copy("Read a profile from the clipboard.")
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
            return (!ruleAction.needsContent || !ruleContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !busy
        }
        return preview != nil && !busy
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
        purpose == .nodes && actions.importOriginal != nil && (preview?.record.hasRules ?? false)
    }

    public var body: some View {
        HakoMacSheetFrame(title: title, subtitle: subtitle, width: 560, height: 540) {
            VStack(spacing: 0) {
                Picker(selection: $tab) {
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
                HakoMacSheetForm {
                    switch tab {
                    case .link: linkSection
                    case .file: fileSection
                    case .nodes: nodesSection
                    case .manual: manualSection
                    }
                    if let preview, tab != .manual { previewSection(preview) }
                    if let error {
                        Section {
                            Text(verbatim: error).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.import.error")
                        }
                    }
                }
                .accessibilityIdentifier("configuration-center.import")
            }
        } leading: {
            if offersOriginalImport {
                Button {
                    run { payload in try await actions.importOriginal?(payload) }
                } label: {
                    Text(hako: .copy("Import Original Configuration"))
                }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.original")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.import.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.import.add",
                primaryDisabled: !canAdd,
                isBusy: busy,
                onClose: close,
                onPrimary: { if tab == .manual { createRule() } else { run(accept) } }
            )
        }
        .onChange(of: tab) { _ in preview = nil; error = nil }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: Self.fileTypes) { result in
            switch result {
            case .success(let picked): readPickedFile(picked)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private static var fileTypes: [UTType] {
        [.plainText, .text, UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml"),
         UTType(filenameExtension: "mrs"), UTType(filenameExtension: "txt")].compactMap { $0 }
    }

     

    private var readRow: some View {
        LabeledContent {
            Button(action: read) { HakoActionProgressLabel(.copy("Read"), isBusy: busy) }
                .disabled(!canRead)
                .accessibilityIdentifier("configuration-center.import.read")
        } label: {
            Text(hako: .copy("Read from Source"))
        }
    }

    private var linkSection: some View {
        Section {
            TextField(text: $url, prompt: Text(verbatim: "https://")) { Text(hako: .copy("URL")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.url")
            TextField(text: $label, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.name")
            readRow
        }
    }

    private var fileSection: some View {
        Section {
            LabeledContent {
                Button { choosingFile = true } label: { Text(hako: .copy("Choose File")) }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.import.choose-file")
            } label: {
                Text(hako: fileName.isEmpty ? .copy("File") : .verbatim(fileName))
            }
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .disabled(busy)
                .accessibilityLabel(Text(hako: .copy("Paste YAML text")))
                .accessibilityIdentifier("configuration-center.import.text")
            TextField(text: $label, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.file-name")
            LabeledContent {
                Button(action: read) { HakoActionProgressLabel(.copy("Read"), isBusy: busy) }
                    .disabled(!canRead)
                    .accessibilityIdentifier("configuration-center.import.read-file")
            } label: {
                Text(hako: .copy("Read from Source"))
            }
        } header: {
            Text(hako: .copy("Paste YAML text"))
        }
    }

    private var nodesSection: some View {
        Section {
            TextEditor(text: $nodesText)
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .disabled(busy)
                .accessibilityLabel(Text(hako: .copy("Custom Nodes")))
                .accessibilityIdentifier("configuration-center.import.nodes-text")
            LabeledContent {
                Button(action: read) { HakoActionProgressLabel(.copy("Read"), isBusy: busy) }
                    .disabled(!canRead)
                    .accessibilityIdentifier("configuration-center.import.read-nodes")
            } label: {
                Text(hako: .copy("Read from Source"))
            }
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
            if ruleAction.needsContent {
                TextField(text: $ruleContent, prompt: Text(verbatim: ruleAction.contentPlaceholder)) {
                    Text(verbatim: ruleAction.contentLabel)
                }
                .font(.body.monospaced())
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.import.manual.content")
            }
            Picker(selection: $ruleTarget) {
                ForEach(["DIRECT", "REJECT", "PROXY"], id: \.self) { name in Text(verbatim: name).tag(name) }
            } label: {
                Text(hako: .copy("Policy Groups"))
            }
            .disabled(busy)
            .accessibilityIdentifier("configuration-center.import.manual.target")
            LabeledContent { Text(verbatim: assembledRule).font(.body.monospaced()) } label: { Text(hako: .copy("Rule")) }
        } header: {
            Text(hako: .copy("Add Rule"))
        }
    }

    private func previewSection(_ payload: ConfigurationSourcePayload) -> some View {
        Section {
            LabeledContent { Text(verbatim: payload.record.label) } label: { Text(hako: .copy("Name")) }
            if purpose == .nodes || payload.record.suppliesNodes {
                LabeledContent {
                    Text(verbatim: HakoConfigurationSourceCopy.summary(payload.record, locale: locale))
                } label: {
                    Text(hako: .copy("Nodes"))
                }
            }
            if payload.record.hasRules {
                LabeledContent { Text(hako: HakoConfigurationSourceCopy.ruleSummary(payload.record)) } label: { Text(hako: .copy("Rules")) }
            }
        } header: {
            Text(hako: .copy("Read from Source"))
        } footer: {
            if offersOriginalImport {
                Text(hako: .copy("Keep the document's nodes, rules and settings."))
            }
        }
        .accessibilityIdentifier("configuration-center.import.preview")
    }

     

    private func read() {
        guard canRead else { return }
        busy = true
        error = nil
        preview = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                switch tab {
                case .link:
                    preview = try await actions.fetch(url.trimmingCharacters(in: .whitespacesAndNewlines), label)
                case .file:
                    let name = fileName.isEmpty ? "Configuration.yaml" : fileName
                    preview = try await actions.readFile(label.isEmpty ? name : label, text)
                case .nodes:
                    guard let readNodes = actions.readNodes else { throw ConfigurationLibraryError.unreadable }
                    preview = try await readNodes(nodesText)
                case .manual:
                    break
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func run(_ operation: @escaping (ConfigurationSourcePayload) async throws -> Void) {
        guard let preview, !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await operation(preview)
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
                try await create(assembledRule)
                close()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func readPickedFile(_ picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        do {
            text = try String(contentsOf: picked, encoding: .utf8)
            fileName = picked.lastPathComponent
            if label.isEmpty { label = picked.deletingPathExtension().lastPathComponent }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
