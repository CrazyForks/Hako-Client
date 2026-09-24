import Foundation
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

struct ConfigScript: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var body: String
}

enum ScriptImportError: LocalizedError, Equatable {
    case emptyAddress
    case notAnAddress
    case unsupportedScheme(String)
    case notText
    case empty

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "Enter the address of the script you want to import."
        case .notAnAddress:
             
             
            return "That is not a web address. Paste the script file's URL, not the script."
        case let .unsupportedScheme(scheme):
            return HakoCopy.format(
                "Scripts are imported over http or https. This address uses %@.",
                locale: .current,
                scheme
            )
        case .notText:
            return "The address answered with something that is not text."
        case .empty:
            return "The address answered with an empty document."
        }
    }
}

 
 
 
 
 
 
 
enum ScriptEditorSource: Hashable { case write, url, file }

 
 
 
 
 
 
 
 
 
enum ScriptEditorSaveIntent: Equatable {
    case save
    case importThenSave

    static func decide(source: ScriptEditorSource, address: String) -> ScriptEditorSaveIntent {
        guard source == .url,
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .save }
        return .importThenSave
    }
}

 
 
 
 
 
 
 
 
enum ScriptImport {
     
     
    static let maxBytes = 1 << 20

     
    static func address(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScriptImportError.emptyAddress }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { throw ScriptImportError.notAnAddress }
        guard scheme == "http" || scheme == "https" else {
            throw ScriptImportError.unsupportedScheme(scheme)
        }
        return url
    }

     
     
     
     
     
    static func suggestedName(for url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty, stem != "/", !stem.contains("..") else { return nil }
        return String(stem.prefix(64))
    }

     
     
     
     
     
     
     
    static func body(
        at raw: String,
        using downloader: HTTPFetching = ResourceDownloader()
    ) async throws -> String {
        var request = URLRequest(url: try address(raw))
        request.setValue(ClientUserAgent.resolved(), forHTTPHeaderField: "User-Agent")
        let result = try await downloader.fetch(
            request,
            maxBytes: maxBytes,
            redirectPolicy: .followAcrossOrigins(maxHops: 5)
        )
        guard let text = String(data: result.data, encoding: .utf8) else {
            throw ScriptImportError.notText
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScriptImportError.empty
        }
        return text
    }
}

enum ScriptLibraryError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case let .missing(id): return "Selected override script '\(id)' no longer exists."
        }
    }
}

 
 
 
 
 
 
 
 
enum UnsavedEditPolicy: Equatable {
    case leave
    case offerToSave

    static func decision(original: String, current: String) -> UnsavedEditPolicy {
         
         
         
        current == original ? .leave : .offerToSave
    }
}

enum ScriptLibrary {
    private static let key = "script.library"

    static var appGroupDefaults: UserDefaults {


        return UserDefaults(suiteName: HakoAppIdentifiers.appGroup) ?? .standard
    }



     
    static let defaultLabel = "New Script"

     
    static func fresh() -> ConfigScript {
        ConfigScript(id: UUID().uuidString.lowercased(), label: defaultLabel, body: ScriptSettings.template)
    }

    static func load(from defaults: UserDefaults = appGroupDefaults) -> [ConfigScript] {
        guard let data = defaults.data(forKey: key),
              let scripts = try? JSONDecoder().decode([ConfigScript].self, from: data) else {
            return []
        }
        return scripts
    }

     
     
     
     
     
     
     
    static let didChange = Notification.Name("HakoScriptLibraryDidChange")

    static func save(_ scripts: [ConfigScript], in defaults: UserDefaults = appGroupDefaults) {
        guard let data = try? JSONEncoder().encode(scripts) else { return }
        defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: didChange, object: defaults)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let testConfigYAML = """
    mode: rule
    log-level: info
    proxies:
      - name: "HK-01"
        type: trojan
        server: hk01.example.com
        port: 443
        password: "test-only"
      - name: "JP-01 2x"
        type: ss
        server: jp01.example.com
        port: 8388
        cipher: aes-128-gcm
        password: "test-only"
    proxy-providers: {}
    proxy-groups:
      - name: PROXY
        type: select
        proxies:
          - HK-01
          - JP-01 2x
          - DIRECT
    rules:
      - MATCH,PROXY
    """

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func editedScript(
        id: String,
        label: String,
        body: String,
        existing: [ConfigScript] = []
    ) -> ConfigScript? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let taken = existing.contains {
            $0.id != id
                && $0.label.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !taken else { return nil }
        return ConfigScript(id: id, label: trimmed, body: body)
    }

    static func upsert(_ script: ConfigScript, in defaults: UserDefaults = appGroupDefaults) {
        var scripts = load(from: defaults)
        if let index = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[index] = script
        } else {
            scripts.append(script)
        }
        save(scripts, in: defaults)
    }

    static func remove(
        id: String,
        in defaults: UserDefaults = appGroupDefaults,
        unlinkProfiles: Bool = true
    ) {
        save(load(from: defaults).filter { $0.id != id }, in: defaults)
        guard unlinkProfiles else { return }
        guard let container = HakoAppIdentifiers.appGroupContainer else { return }
        let store = ProfileStore(
            fileURL: container.appendingPathComponent("working/store/profiles.json")
        )
        let profiles = unlinkReferences(to: id, from: store.load())
        try? store.save(profiles)
    }

     
     
     
     
    static func activeProfileName() -> String {
        guard let container = HakoAppIdentifiers.appGroupContainer,
              let configStore = try? ConfigResourceStore(containerURL: container),
              let activeID = (try? configStore.activeIdentity())?.profileID
        else { return "" }
        let profiles = ProfileStore(
            fileURL: container.appendingPathComponent("working/store/profiles.json")
        )
        return profiles.load().first { $0.id == activeID }?.label ?? ""
    }

    static func unlinkReferences(to id: String, from profiles: [Profile]) -> [Profile] {
        profiles.map { profile in
            guard profile.selectedScriptID == id || profile.postMergeScriptID == id else {
                return profile
            }
            var updated = profile
            if updated.selectedScriptID == id {
                updated.selectedScriptID = nil
            }
            if updated.postMergeScriptID == id {
                updated.postMergeScriptID = nil
            }
            return updated
        }
    }

    static func apply(id: String?, to yaml: String,
                      profileName: String = "",
                      from defaults: UserDefaults = appGroupDefaults) throws -> String {
        try apply(
            id: id, to: yaml, scripts: load(from: defaults), profileName: profileName
        )
    }

    static func apply(
        id: String?,
        to yaml: String,
        scripts: [ConfigScript],
        profileName: String = ""
    ) throws -> String {
        guard let id else { return yaml }
        guard let script = scripts.first(where: { $0.id == id }) else {
            throw ScriptLibraryError.missing(id)
        }
        let configJSON = try ConfigTransforms.yamlToJSON(yaml)
        let rewritten = try ScriptEngine.run(
            script: script.body, configJSON: configJSON, profileName: profileName
        )
        return try ConfigTransforms.jsonToYAML(rewritten)
    }
}

struct ScriptLibraryView: View {
    @State private var scripts = ScriptLibrary.load()
    @State private var deletingScripts: [ConfigScript] = []
    @State private var editing: ConfigScript?
    @State private var adding: ConfigScript?

    var body: some View {
        Group {
#if os(macOS)
         
         
         
         
         
         
        Form {
            if scripts.isEmpty {
                Section {
                HakoEmptyState(
                    title: "No Scripts",
                    message: "",
                    symbol: .curlybraces
                )
                .listRowSeparator(.hidden)
                }
            } else {
                Section {
            ForEach(scripts) { script in
                Button { editing = script } label: {
                    HakoDestinationRow(
                         
                        title: .verbatim(script.label),
                        subtitle: "JavaScript main(config)",
                        symbol: .curlybraces,
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scripts.row.\(script.id)")
            }
            .onDelete { offsets in
                deletingScripts = offsets.compactMap { scripts.indices.contains($0) ? scripts[$0] : nil }
            }
                }
            }
            Section {
                HakoAddRow(Text(HakoCopy.key("Add Script"))) {
                    adding = ScriptLibrary.fresh()
                }
                .accessibilityIdentifier("scripts.row.add")
            }
        }
#else
        List {
            if scripts.isEmpty {
                HakoEmptyState(
                    title: "No Scripts",
                    message: "",
                    symbol: .curlybraces
                )
                .listRowSeparator(.hidden)
            }
            ForEach(scripts) { script in
                Button { editing = script } label: {
                    HakoDestinationRow(
                         
                        title: .verbatim(script.label),
                        subtitle: "JavaScript main(config)",
                        symbol: .curlybraces,
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scripts.row.\(script.id)")
            }
            .onDelete { offsets in
                deletingScripts = offsets.compactMap { scripts.indices.contains($0) ? scripts[$0] : nil }
            }
        }
        .hakoInsetGroupedListStyle()
#endif
        }
        .hakoPageTitle("Scripts")
        .hakoDetailPageInsets()
        .accessibilityIdentifier("scripts.screen")
        .hakoDeleteConfirmation(deletingScripts.map(\.label).joined(separator: ", "),
            isPresented: Binding(get: { !deletingScripts.isEmpty }, set: { if !$0 { deletingScripts = [] } }),
            message: .copy("These scripts will be deleted. Profiles using them must choose another script before starting."),
            identifier: "scripts.delete.confirm") { [deletingScripts] in
                deletingScripts.forEach { ScriptLibrary.remove(id: $0.id) }
                scripts = ScriptLibrary.load()
                self.deletingScripts = []
            }
        .hakoToolbarUnlessInPanel {
            ToolbarItemGroup(placement: .hakoNavigationTrailing) {
                HakoEditButton()
                Button { adding = ScriptLibrary.fresh() } label: {
                    Label("Add Script", systemImage: HakoSymbol.plus.name)
                }
            }
        }
         
        .hakoProductModal(item: $editing, role: .page, immersive: { _ in true }) { script in
            ScriptEditorView(script: script, showsImportInMenu: true) { save($0) }
                .hakoModalPresentation(.page)
        }
        .hakoProductModal(item: $adding, role: .page, immersive: { _ in true }) { script in
            ScriptEditorView(script: script, showsImportInMenu: true) { save($0) }
                .hakoModalPresentation(.page)
        }
    }

    private func save(_ script: ConfigScript) {
        ScriptLibrary.upsert(script)
        scripts = ScriptLibrary.load()
        editing = nil
        adding = nil
    }
}

 
 
 
 
 
 
 
 
 
 
private struct ScriptEditorTitle: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .hakoPageTitle(.verbatim(label), watchAs: "Script")
            .navigationBarTitleDisplayMode(.inline)
#else
        content.hakoPageTitle(.verbatim(label), watchAs: "Script")
#endif
    }
}

struct ScriptEditorView: View {
    let script: ConfigScript
    let save: (ConfigScript) -> Void

     
     
     
     
     
     
    @State private var dismiss = HakoDismissHandle()
    @Environment(\.hakoProductModalDismiss) private var productModalDismiss
    @Environment(\.hakoInsideProductModalPresentation)
    private var insideProductModal
    @State private var label: String
    @State private var bodyText: String
    @State private var result = ""
     
     
     
     
     
     
     
     
     
     
    @State private var activeProfileName: String?
     
     
    @State private var activeProfileNameLoad: Task<String, Never>?
    @State private var diagnosticLine: Int?
    @State private var asksAboutUnsaved = false

    @State private var importAddress = ""
    @State private var showsFileImporter = false
    @State private var importing = false
     
     
     
     
    @State private var importResult = ""
     
     
     
    @State private var saveResult = ""
    @State private var typing = false
    @State private var findPresented = false
    @State private var showsLineNumbers = CodeEditorLineNumbers.isOn
    @State private var softWrap = CodeEditorSoftWrap.isOn
    @State private var renaming = false
    @State private var renameDraft = ""
    @State private var importingFromLink = false
    @State private var showsTestResult = false
    @State private var showsSaveResult = false
    @State private var showsImportError = false
    private let originalBody: String

     
     
    let showsImportInMenu: Bool

    init(script: ConfigScript, showsImportInMenu: Bool = false, save: @escaping (ConfigScript) -> Void) {
        self.script = script
        self.showsImportInMenu = showsImportInMenu
        self.save = save
        originalBody = script.body
        _label = State(initialValue: script.label)
        _bodyText = State(initialValue: script.body)
    }

     
     
     
     
     
    var body: some View {
        HakoFeatureNavigationContainer {
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HakoTheme.canvas.ignoresSafeArea())
                .modifier(HakoBarFadesWhileTyping(typing: $typing))
                .modifier(ScriptEditorTitle(label: label))
                .fileImporter(
                    isPresented: $showsFileImporter,
                    allowedContentTypes: [.javaScript, .plainText, .text],
                    allowsMultipleSelection: false
                ) { outcome in
                    importFromFile(outcome)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if !insideProductModal {
                            Button("Cancel") {
                                switch UnsavedEditPolicy.decision(
                                    original: originalBody,
                                    current: bodyText
                                ) {
                                case .leave: dismissPresentation()
                                case .offerToSave: asksAboutUnsaved = true
                                }
                            }
                            .accessibilityIdentifier("scripts.editor.cancel")
                        }
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        if !insideProductModal {
                            Menu {
                                moreMenu
                            } label: {
                                Image(systemName: HakoSymbol.ellipsisCircle.name)
                            }
                            .accessibilityLabel("More")
                            .accessibilityIdentifier("scripts.editor.more")
                            Button("Save") {
                                persist()
                            }
                            .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("scripts.editor.save")
                        }
                    }
                }
                .hakoProductModalRoot(title: "Script")
                .task { await loadActiveProfileName() }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if insideProductModal {
                        HakoModalActionBar(
                            primaryTitle: "Save",
                            primaryDisabled: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            onPrimary: persist
                        )
                    }
                }
                .alert("Rename…", isPresented: $renaming) {
                    TextField("Script name", text: $renameDraft)
                        .accessibilityIdentifier("scripts.editor.name")
                    Button("OK") {
                        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { label = trimmed }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Test Run", isPresented: $showsTestResult) {
                    Button("OK") {}
                } message: {
                    Text(verbatim: result)
                }
                .alert("Cannot Save", isPresented: $showsSaveResult) {
                    Button("OK") {}
                } message: {
                    Text(verbatim: saveResult)
                }
                .alert("Import Failed", isPresented: $showsImportError) {
                    Button("OK") {}
                } message: {
                    Text(verbatim: importResult)
                }
                 
                 
                 
                 
                 
                 
                 
                .alert("Import from URL…", isPresented: $importingFromLink) {
                    TextField("Script URL", text: $importAddress)
#if !os(macOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("scripts.editor.import.address")
                    Button("Import") {
                        Task { @MainActor in
                            await importFromAddress()
                            if !importResult.isEmpty { showsImportError = true }
                        }
                    }
                    .accessibilityIdentifier("scripts.editor.import.url")
                    Button("Cancel", role: .cancel) {}
                }
        }
        .hakoStackNavigationViewStyle()
        .hakoRegistersDeparture(
            isDirty: UnsavedEditPolicy.decision(
                original: originalBody,
                current: bodyText
            ) == .offerToSave,
            save: { completion in
                persist()
                completion(true)
            },
            discard: { bodyText = originalBody }
        )
        .alert("Save your changes?", isPresented: $asksAboutUnsaved) {
            Button("Save") {
                persist()
            }
            Button("Discard", role: .destructive) {
                dismissPresentation()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This script has changes that have not been saved.")
        }
        .accessibilityIdentifier("scripts.editor.screen")
        .hakoCapturesDismiss(dismiss)
    }

    private var editor: some View {
        CodeEditorPanel(
            text: $bodyText,
            language: .javascript,
            minHeight: 200,
            diagnosticLine: diagnosticLine,
            expandsVertically: true,
            chrome: .minimal,
            showsLineNumbers: showsLineNumbers,
            softWrap: softWrap,
            findPresented: $findPresented,
            typing: $typing
        )
        .padding(.horizontal, HakoTheme.Spacing.standard)
        .padding(.vertical, HakoTheme.Spacing.compact)
    }

    @ViewBuilder
    private var moreMenu: some View {
        Button {
            renameDraft = label
            renaming = true
        } label: {
            Label("Rename…", systemImage: HakoSymbol.pencil.name)
        }
        .accessibilityIdentifier("scripts.editor.rename")
        Button {
            findPresented = true
        } label: {
            Label("Find", systemImage: HakoSymbol.magnifyingglass.name)
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityIdentifier("scripts.editor.find")
        Button {
            showsLineNumbers.toggle()
            CodeEditorLineNumbers.isOn = showsLineNumbers
        } label: {
            Label(
                "Line Numbers",
                systemImage: showsLineNumbers ? HakoSymbol.checkmark.name : HakoSymbol.listBullet.name
            )
        }
        .accessibilityIdentifier("scripts.editor.lineNumbers")
        Button {
            softWrap.toggle()
            CodeEditorSoftWrap.isOn = softWrap
        } label: {
            Label(
                "Wrap Long Lines",
                systemImage: softWrap ? HakoSymbol.checkmark.name : HakoSymbol.arrowRightToLine.name
            )
        }
        .accessibilityIdentifier("scripts.editor.softWrap")
        if showsImportInMenu {
            Divider()
            Button {
                importResult = ""
                importingFromLink = true
            } label: {
                Label("Import from URL…", systemImage: HakoSymbol.link.name)
            }
            .accessibilityIdentifier("scripts.editor.import.link")
            Button {
                showsFileImporter = true
            } label: {
                Label("Import File…", systemImage: HakoSymbol.squareAndArrowDown.name)
            }
            .accessibilityIdentifier("scripts.editor.import.file")
        }
        Divider()
        Button {
            Task { await test() }
        } label: {
            Label("Test Run", systemImage: HakoSymbol.play.name)
        }
        .accessibilityIdentifier("scripts.editor.test")
    }

     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    private func loadActiveProfileName() async -> String {
        if let activeProfileName { return activeProfileName }
        if let inFlight = activeProfileNameLoad { return await inFlight.value }
        let load = Task.detached(priority: .utility) {
            ScriptLibrary.activeProfileName()
        }
        activeProfileNameLoad = load
        let name = await load.value
        activeProfileName = name
        activeProfileNameLoad = nil
        return name
    }

    @discardableResult
    private func validate(name: String) -> Bool {
        do {
            let json = try ConfigTransforms.yamlToJSON(ScriptLibrary.testConfigYAML)
             
             
             
             
             
            let output = try ScriptEngine.run(
                script: bodyText,
                configJSON: json,
                profileName: name
            )
            _ = try ConfigTransforms.jsonToYAML(output)
            result = "OK — script returned a valid config object."
            diagnosticLine = nil
            return true
        } catch {
            diagnosticLine = CodeEditorDiagnosticParser.line(in: error.localizedDescription)
            result = "Error: \(error.localizedDescription)"
            return false
        }
    }

     
     
     
     
     
    @MainActor
    private func importFromAddress() async {
        importing = true
        importResult = ""
        defer { importing = false }
        do {
            let text = try await ScriptImport.body(at: importAddress)
            bodyText = text
            result = ""
            diagnosticLine = nil
            if label == ScriptLibrary.defaultLabel || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let url = try? ScriptImport.address(importAddress),
               let suggested = ScriptImport.suggestedName(for: url) {
                label = suggested
            }
        } catch {
            importResult = (error as NSError).localizedDescription
        }
    }

    private func importFromFile(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case let .success(urls):
            guard let url = urls.first else { return }
             
             
             
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importResult = ""
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    importResult = ScriptImportError.empty.localizedDescription
                    return
                }
                bodyText = text
                result = ""
                diagnosticLine = nil
            } catch {
                importResult = ScriptImportError.notText.localizedDescription
            }
        case let .failure(error):
            importResult = (error as NSError).localizedDescription
        }
        showsImportError = !importResult.isEmpty
    }

    private func test() async {
        _ = validate(name: await loadActiveProfileName())
        showsTestResult = !result.isEmpty
    }

    private func persist() {
         
        let source: ScriptEditorSource = importAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .write : .url
        switch ScriptEditorSaveIntent.decide(source: source, address: importAddress) {
        case .importThenSave:
             
             
             
             
             
             
             
            Task { @MainActor in
                await importFromAddress()
                 
                 
                guard importResult.isEmpty else { return }
                commit()
            }
        case .save:
            commit()
        }
    }

    private func commit() {
        guard let edited = ScriptLibrary.editedScript(
            id: script.id,
            label: label,
            body: bodyText,
            existing: ScriptLibrary.load()
        ) else {
            saveResult = "Another script already uses that name."
            showsSaveResult = true
            return
        }
        saveResult = ""
        save(edited)
        dismissPresentation()
    }

    private func dismissPresentation() {
        (productModalDismiss ?? { dismiss() })()
    }
}

 
 
 
struct ScriptAddSheet: View {
    let library: UserDefaults
    let close: () -> Void
    let added: (ConfigScript) -> Void

    @State private var tab = 1
    @State private var address = ""
    @State private var name = ""
    @State private var bodyText = ScriptLibrary.fresh().body
    @State private var importing = false
    @State private var failure = ""
    @State private var showsFailure = false
    @State private var showsFileImporter = false

    var body: some View {
        HakoFeatureNavigationContainer {
            VStack(spacing: 0) {
                tabs
                Form { fields }
            }
            .hakoPageTitle("Add Script")
            .hakoToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                        .accessibilityIdentifier("scripts.add.cancel")
                }
                ToolbarItem(placement: .confirmationAction) { commitButton }
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.javaScript, .plainText, .text],
            allowsMultipleSelection: false
        ) { outcome in
            importFile(outcome)
        }
        .alert("Import Failed", isPresented: $showsFailure) {
            Button("OK") {}
        } message: {
            Text(verbatim: failure)
        }
    }

    private var tabs: some View {
        Picker("Add Script", selection: $tab) {
            Text(HakoCopy.key("URL")).tag(1)
            Text(HakoCopy.key("File")).tag(2)
            Text(HakoCopy.key("Manual")).tag(3)
        }
        .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 8)
        .accessibilityIdentifier("scripts.add.tabs")
    }

    @ViewBuilder
    private var fields: some View {
        switch tab {
        case 1:
            Section {
                TextField("Script URL", text: $address)
                    .textContentType(.URL)
#if !os(macOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("scripts.add.link.address")
            }
        case 2:
            Section {
                Button("Choose File…") { showsFileImporter = true }
                    .accessibilityIdentifier("scripts.add.file.choose")
            }
        default:
            Section {
                TextField("Script name", text: $name)
                    .accessibilityIdentifier("scripts.add.name")
            }
            Section {
                CodeEditorPanel(
                    text: $bodyText,
                    language: .javascript,
                    minHeight: 240,
                    diagnosticLine: nil
                )
            }
        }
    }

    @ViewBuilder
    private var commitButton: some View {
        if tab == 1 {
            Button(importing ? "Importing…" : "Import") {
                Task { @MainActor in await importLink() }
            }
            .disabled(importing || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("scripts.add.link.import")
        } else if tab == 3 {
            Button("Save") { saveManual() }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("scripts.add.save")
        }
    }

    private func importLink() async {
        importing = true
        defer { importing = false }
        do {
            let text = try await ScriptImport.body(at: address)
            let label = (try? ScriptImport.address(address)).flatMap(ScriptImport.suggestedName(for:))
                ?? ScriptLibrary.defaultLabel
            finish(label: label, body: text)
        } catch {
            fail((error as NSError).localizedDescription)
        }
    }

    private func importFile(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case let .success(urls):
            guard let url = urls.first else { return }
             
             
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    fail(ScriptImportError.empty.localizedDescription)
                    return
                }
                finish(label: url.deletingPathExtension().lastPathComponent, body: text)
            } catch {
                fail(ScriptImportError.notText.localizedDescription)
            }
        case let .failure(error):
            fail((error as NSError).localizedDescription)
        }
    }

    private func saveManual() {
        finish(label: name, body: bodyText)
    }

     
     
    private func finish(label: String, body: String) {
        let existing = ScriptLibrary.load(from: library)
        let id = UUID().uuidString
        var candidate = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { candidate = ScriptLibrary.defaultLabel }
        var attempt = 2
        var script = ScriptLibrary.editedScript(id: id, label: candidate, body: body, existing: existing)
        while script == nil, attempt < 100 {
            script = ScriptLibrary.editedScript(id: id, label: "\(candidate) \(attempt)", body: body, existing: existing)
            attempt += 1
        }
        guard let script else { fail(ScriptImportError.empty.localizedDescription); return }
        ScriptLibrary.upsert(script, in: library)
        added(script)
    }

    private func fail(_ message: String) {
        failure = message
        showsFailure = true
    }
}
