import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
 
 
public struct HakoMacRuleSetImportDraft: Equatable, Sendable {
    public var name = ""
    public var link = ""
    public var fileName: String?
    public var fileData: Data?
     
    public var behavior = "domain"
     
    public var format = "yaml"

    public init() {}

    public var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isDirty: Bool { !name.isEmpty || !link.isEmpty || fileData != nil }
    public var missingRequired: Bool { title.isEmpty || (fileData == nil && link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

     
     
     
     
    public func document() throws -> OrderedJSON {
        guard !title.isEmpty, !title.contains(",") else { throw ConfigurationLibraryError.emptyName }
        var definition = OrderedJSON.object([
            ("type", .string(fileData == nil ? "http" : "file")),
            ("behavior", .string(behavior)),
            ("format", .string(format))
        ])
        if let fileName, fileData != nil {
            definition = definition.settingTopLevel("path", to: .string(fileName))
        } else {
            let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw ConfigurationLibraryError.unreadable
            }
            definition = definition.settingTopLevel("url", to: .string(link)).settingTopLevel("interval", to: .scalar("86400"))
        }
        return OrderedJSON.object([("rule-providers", .object([(title, definition)]))])
    }

     
     
    public func record() -> ConfigurationSourceRecord {
        var record = ConfigurationSourceRecord(label: title, origin: .file(title + ".yaml"), suppliesNodes: false)
        record.registersSuppliedRules = false
        record.ruleProviderCount = 1
        return record
    }

     
    public var resourceFiles: [String: Data]? {
        guard let fileName, let fileData else { return nil }
        return [fileName: fileData]
    }
}

 
 
 
struct HakoMacRuleSetImportForm: View {
    let add: @MainActor (HakoMacRuleSetImportDraft) async throws -> Void
    let back: () -> Void
    let done: () -> Void
    @State private var draft = HakoMacRuleSetImportDraft()
    @State private var choosingFile = false
    @State private var busy = false
    @State private var error: String?

    private static var fileTypes: [UTType] {
        [.plainText, .text, UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml"),
         UTType(filenameExtension: "mrs"), UTType(filenameExtension: "txt")].compactMap { $0 }
    }

    var body: some View {
        HakoMacSheetFrame(title: .copy("Import Rule Set"), subtitle: .copy("For MRS, Text or YAML rule sets."), width: 560, height: 540) {
            HakoMacSheetForm {
                Section {
                    TextField(text: $draft.name, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.rule-set.name")
                    TextField(text: $draft.link, prompt: Text(verbatim: "https://")) { Text(hako: .copy("Rule URL")) }
                        .disabled(busy || draft.fileData != nil)
                        .accessibilityIdentifier("configuration-center.rule-set.url")
                    LabeledContent {
                        HStack(spacing: 6) {
                            if draft.fileData != nil {
                                Button { draft.fileData = nil; draft.fileName = nil } label: { Text(hako: .copy("Remove File")) }
                                    .disabled(busy)
                                    .accessibilityIdentifier("configuration-center.rule-set.clear-file")
                            }
                            Button { choosingFile = true } label: { Text(hako: .copy("Choose File…")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.rule-set.choose-file")
                        }
                    } label: {
                        Text(hako: draft.fileName.map { .verbatim($0) } ?? .copy("File"))
                    }
                }
                Section {
                    Picker(selection: $draft.behavior) {
                        Text(hako: .copy("Domain")).tag("domain")
                        Text(hako: .copy("IP CIDR")).tag("ipcidr")
                        Text(hako: .copy("Classical")).tag("classical")
                    } label: {
                        Text(hako: .copy("Rule Type"))
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("configuration-center.rule-set.behavior")
                    Picker(selection: $draft.format) {
                        Text(verbatim: "YAML").tag("yaml")
                        Text(verbatim: "Text").tag("text")
                        if draft.behavior != "classical" { Text(verbatim: "MRS").tag("mrs") }
                    } label: {
                        Text(hako: .copy("Format"))
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("configuration-center.rule-set.format")
                }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration-center.rule-set.error")
                    }
                }
            }
            .accessibilityIdentifier("configuration-center.rule-set")
        } trailing: {
            HakoMacSheetButtons(
                closeTitle: .copy("Back"),
                closeIdentifier: "configuration-center.rule-set.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.rule-set.add",
                primaryDisabled: draft.missingRequired || busy,
                isBusy: busy,
                onClose: back,
                onPrimary: submit
            )
        }
        .onChange(of: draft.behavior) { value in
             
            if value == "classical", draft.format == "mrs" { draft.format = "yaml" }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: Self.fileTypes) { result in
            switch result {
            case .success(let picked): readPickedFile(picked)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private func submit() {
        guard !busy, !draft.missingRequired else { return }
        busy = true
        error = nil
        let value = draft
        Task { @MainActor in
            defer { busy = false }
            do {
                try await add(value)
                done()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func readPickedFile(_ picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        do {
            draft.fileData = try Data(contentsOf: picked)
            draft.fileName = picked.lastPathComponent
            if draft.name.isEmpty { draft.name = picked.deletingPathExtension().lastPathComponent }
            if picked.pathExtension.lowercased() == "mrs" { draft.format = "mrs" }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
