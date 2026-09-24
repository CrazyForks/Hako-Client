import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
 
 
 
 
public struct HakoMacSourceImportActions {
     
    public var fetch: @MainActor (String, String) async throws -> ConfigurationSourcePayload
     
    public var readFile: @MainActor (String, String) async throws -> ConfigurationSourcePayload
     
     
     
    public var importOriginal: (@MainActor (ConfigurationSourcePayload) async throws -> Void)?

    public init(
        fetch: @escaping @MainActor (String, String) async throws -> ConfigurationSourcePayload,
        readFile: @escaping @MainActor (String, String) async throws -> ConfigurationSourcePayload,
        importOriginal: (@MainActor (ConfigurationSourcePayload) async throws -> Void)? = nil
    ) {
        self.fetch = fetch
        self.readFile = readFile
        self.importOriginal = importOriginal
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

 
 
 
 
 
 
 
public struct HakoMacSourceImportPage: View {
    public enum Tab: Int, CaseIterable, Identifiable {
        case link, file
        public var id: Int { rawValue }
        var title: String {
            switch self {
            case .link: "Link"
            case .file: "File"
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
    @State private var choosingFile = false
    @State private var preview: ConfigurationSourcePayload?
    @State private var busy = false
    @State private var error: String?

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

     
    private var canAdd: Bool { preview != nil && !busy }

    private var canRead: Bool {
        switch tab {
        case .link: !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
        case .file: !text.isEmpty && !busy
        }
    }

     
     
    private var offersOriginalImport: Bool {
        purpose == .nodes && actions.importOriginal != nil && (preview?.record.hasRules ?? false)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(hako: .copy(item.title)).tag(item)
                }
            } label: {
                Text(hako: .copy("Add Source"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(HakoTheme.Spacing.row)
            .accessibilityIdentifier("configuration-center.import.tabs")
            List {
                switch tab {
                case .link: linkSection
                case .file: fileSection
                }
                if let preview { previewSection(preview) }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration-center.import.error")
                    }
                }
            }
            .listStyle(.inset)
            HStack {
                Button(action: close) { Text(hako: .copy("Cancel")) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("configuration-center.import.cancel")
                Spacer()
                if offersOriginalImport {
                    Button {
                        run { payload in try await actions.importOriginal?(payload) }
                    } label: {
                        Text(hako: .copy("Import Original Configuration"))
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.import.original")
                }
                Button {
                    run(accept)
                } label: {
                    HakoActionProgressLabel(.copy("Add"), isBusy: busy)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
                .accessibilityIdentifier("configuration-center.import.add")
            }
            .padding(HakoTheme.Spacing.row)
            .background(.bar)
        }
        .onChange(of: tab) { _ in preview = nil; error = nil }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: Self.fileTypes) { result in
            switch result {
            case .success(let picked): readPickedFile(picked)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .accessibilityIdentifier("configuration-center.import")
    }

    private static var fileTypes: [UTType] {
        [.plainText, .text, UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml"),
         UTType(filenameExtension: "mrs"), UTType(filenameExtension: "txt")].compactMap { $0 }
    }

     

    private var linkSection: some View {
        Section {
            HakoMacFieldRow(.copy("Link"), prompt: "https://", text: $url,
                            identifier: "configuration-center.import.url")
                .disabled(busy)
            HakoMacFieldRow(.copy("Name"), prompt: HakoCopy.string("Name", locale: locale), text: $label,
                            identifier: "configuration-center.import.name")
                .disabled(busy)
            HakoMacActionRow(.copy("Read from Source"), actionTitle: .copy("Read"), action: read) {
                if busy { ProgressView().controlSize(.small) }
            }
            .disabled(!canRead)
            .accessibilityIdentifier("configuration-center.import.read")
        } header: {
            Text(hako: .copy("Subscription URL or Share Link"))
        } footer: {
            Text(hako: .copy("Subscription links and install links both work."))
        }
    }

    private var fileSection: some View {
        Section {
            HakoMacActionRow(.copy(fileName.isEmpty ? "Choose File" : "File"), actionTitle: .copy("Choose File"),
                             action: { choosingFile = true }) {
                if !fileName.isEmpty { Text(verbatim: fileName).foregroundStyle(.secondary) }
            }
            .disabled(busy)
            .accessibilityIdentifier("configuration-center.import.choose-file")
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .disabled(busy)
                .accessibilityLabel(Text(hako: .copy("Paste config text")))
                .accessibilityIdentifier("configuration-center.import.text")
            HakoMacFieldRow(.copy("Name"), prompt: HakoCopy.string("Name", locale: locale), text: $label,
                            identifier: "configuration-center.import.file-name")
                .disabled(busy)
            HakoMacActionRow(.copy("Read from Source"), actionTitle: .copy("Read"), action: read) {
                if busy { ProgressView().controlSize(.small) }
            }
            .disabled(!canRead)
            .accessibilityIdentifier("configuration-center.import.read-file")
        } header: {
            Text(hako: .copy("Paste config text"))
        }
    }

    private func previewSection(_ payload: ConfigurationSourcePayload) -> some View {
        Section {
            HakoMacNavigationRowLabel(.copy("Name"), value: .verbatim(payload.record.label))
            if purpose == .nodes || payload.record.suppliesNodes {
                HakoMacNavigationRowLabel(
                    .copy("Nodes"),
                    value: .verbatim(HakoConfigurationSourceCopy.summary(payload.record, locale: locale))
                )
            }
            if payload.record.hasRules {
                HakoMacNavigationRowLabel(.copy("Rules"), value: HakoConfigurationSourceCopy.ruleSummary(payload.record))
            }
            if offersOriginalImport {
                Text(hako: .copy("Keep the document's nodes, rules and settings."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(hako: .copy("Read from Source"))
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
