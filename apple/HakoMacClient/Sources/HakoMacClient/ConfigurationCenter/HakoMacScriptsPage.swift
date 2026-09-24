import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
public struct HakoMacScriptEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
     
    public let canRefresh: Bool
    public init(id: String, label: String, canRefresh: Bool = false) {
        self.id = id
        self.label = label
        self.canRefresh = canRefresh
    }
}

 
public struct HakoMacScriptsState: Equatable, Sendable {
    public var scripts: [HakoMacScriptEntry]
     
    public var selectedID: String?
     
    public var patchFieldCount: Int
     
    public var exceptions: [String]

    public init(scripts: [HakoMacScriptEntry], selectedID: String?, patchFieldCount: Int, exceptions: [String]) {
        self.scripts = scripts
        self.selectedID = selectedID
        self.patchFieldCount = patchFieldCount
        self.exceptions = exceptions
    }

    public static let empty = HakoMacScriptsState(scripts: [], selectedID: nil, patchFieldCount: 0, exceptions: [])
}

 
 
 
public struct HakoMacScriptsActions {
    public var load: @MainActor () async -> HakoMacScriptsState
     
    public var select: @MainActor (String?) async throws -> HakoMacScriptsState
     
    public var addLink: @MainActor (String) async throws -> HakoMacScriptsState
     
    public var addManual: @MainActor (String, String) async throws -> HakoMacScriptsState
    public var remove: @MainActor (String) async throws -> HakoMacScriptsState
     
    public var edit: (@MainActor (String) -> Void)? = nil
     
     
     
     
    public var refresh: (@MainActor (String) async throws -> HakoMacScriptsState)? = nil
    public var clearPatch: @MainActor () async throws -> HakoMacScriptsState
    public var removeException: @MainActor (Int) async throws -> HakoMacScriptsState

    public init(
        load: @escaping @MainActor () async -> HakoMacScriptsState,
        select: @escaping @MainActor (String?) async throws -> HakoMacScriptsState,
        addLink: @escaping @MainActor (String) async throws -> HakoMacScriptsState,
        addManual: @escaping @MainActor (String, String) async throws -> HakoMacScriptsState,
        remove: @escaping @MainActor (String) async throws -> HakoMacScriptsState,
        clearPatch: @escaping @MainActor () async throws -> HakoMacScriptsState,
        removeException: @escaping @MainActor (Int) async throws -> HakoMacScriptsState,
        refresh: (@MainActor (String) async throws -> HakoMacScriptsState)? = nil
    ) {
        self.load = load
        self.select = select
        self.addLink = addLink
        self.addManual = addManual
        self.remove = remove
        self.clearPatch = clearPatch
        self.removeException = removeException
        self.refresh = refresh
    }

    public static var unavailable: HakoMacScriptsActions {
        HakoMacScriptsActions(
            load: { .empty },
            select: { _ in throw ConfigurationLibraryError.unreadable },
            addLink: { _ in throw ConfigurationLibraryError.unreadable },
            addManual: { _, _ in throw ConfigurationLibraryError.unreadable },
            remove: { _ in throw ConfigurationLibraryError.unreadable },
            clearPatch: { throw ConfigurationLibraryError.unreadable },
            removeException: { _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
 
 
 
 
public struct HakoMacScriptsPage: View {
    private let actions: HakoMacScriptsActions
    @State private var state: HakoMacScriptsState
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var adding = false
    @State private var deleting: HakoMacScriptEntry?

    public init(actions: HakoMacScriptsActions, initial: HakoMacScriptsState = .empty) {
        self.actions = actions
        _state = State(initialValue: initial)
    }

     
     
    @ViewBuilder
    private func scriptRow(_ script: HakoMacScriptEntry) -> some View {
        HakoMacChoiceRow(
            title: .verbatim(script.label),
            subtitle: .copy("Script"),
            style: .single,
            isSelected: state.selectedID == script.id,
            identifier: "configuration-center.scripts.row.\(script.id)",
            toggle: { perform { try await actions.select(state.selectedID == script.id ? nil : script.id) } }
        )
        .disabled(busy)
        .contextMenu {
            if let edit = actions.edit {
                Button { edit(script.id) } label: { Text(hako: .copy("Edit")) }
            }
            if script.canRefresh, let refresh = actions.refresh {
                Button { perform { try await refresh(script.id) } } label: { Text(hako: .copy("Update")) }
            }
            if actions.edit != nil || (script.canRefresh && actions.refresh != nil) { Divider() }
            Button(role: .destructive) { deleting = script } label: { Text(hako: .copy("Delete")) }
        }
    }

    public var body: some View {
        List {
             
             
             
             
             
             
             
             
            let chosen = state.scripts.first { $0.id == state.selectedID }
            let others = state.scripts.filter { $0.id != state.selectedID }
            if let chosen {
                Section {
                    scriptRow(chosen)
                } header: {
                    Text(hako: .copy("Script"))
                        .accessibilityIdentifier("configuration-center.scripts.selected")
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { script in
                        scriptRow(script)
                    }
                } header: {
                    if chosen == nil {
                        Text(hako: .copy("Scripts"))
                    } else {
                        Text(hako: .copy("Other Scripts"))
                            .accessibilityIdentifier("configuration-center.scripts.other")
                    }
                }
            }
            Section {
                HakoMacListAddRow(.copy("Add Script")) { adding = true }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.scripts.add")
            } header: {
                if chosen == nil, others.isEmpty {
                    Text(hako: .copy("Scripts"))
                }
            }
            if state.patchFieldCount > 0 {
                Section {
                    LabeledContent {
                        Button { perform { try await actions.clearPatch() } } label: { Text(hako: .copy("Clear Field Patch")) }
                            .disabled(busy)
                            .accessibilityIdentifier("configuration-center.scripts.patch")
                    } label: {
                        Text(hako: .copy("Field Patch"))
                        Text(hako: .format("%@ fields", [String(state.patchFieldCount)]))
                    }
                }
            }
            if !state.exceptions.isEmpty {
                Section {
                    ForEach(Array(state.exceptions.enumerated()), id: \.offset) { index, rule in
                        Text(verbatim: rule)
                            .font(.body.monospaced())
                            .contextMenu {
                                Button(role: .destructive) {
                                    perform { try await actions.removeException(index) }
                                } label: {
                                    Text(hako: .copy("Delete"))
                                }
                            }
                            .accessibilityIdentifier("configuration-center.scripts.exception.\(index)")
                    }
                } header: {
                    Text(hako: .copy("This Profile's Exceptions"))
                }
            }
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.scripts.error")
                }
            }
        }
        .hakoMacCardList()
        .task {
            guard !loaded else { return }
            loaded = true
            state = await actions.load()
        }
        .sheet(isPresented: $adding) {
            HakoMacScriptAddSheet(
                addLink: { link in try await apply { try await actions.addLink(link) } },
                addManual: { name, body in try await apply { try await actions.addManual(name, body) } },
                close: { adding = false }
            )
            .hakoModalPresentation(.fitted)
        }
        .alert(Text(hako: .verbatim(deleting?.label ?? "")), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(role: .destructive) {
                if let script = deleting { perform { try await actions.remove(script.id) } }
                deleting = nil
            } label: {
                Text(hako: .copy("Delete"))
            }
            Button(role: .cancel) { deleting = nil } label: { Text(hako: .copy("Cancel")) }
        }
        .hakoFrameWatch("configuration-scripts")
        .accessibilityIdentifier("configuration-center.scripts")
    }

    private func perform(_ operation: @escaping () async throws -> HakoMacScriptsState) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { state = try await operation() } catch { self.error = error.localizedDescription }
        }
    }

     
     
    private func apply(_ operation: @escaping () async throws -> HakoMacScriptsState) async throws {
        state = try await operation()
        adding = false
    }
}

 
 
 
 
struct HakoMacScriptAddSheet: View {
    enum Tab: Int, CaseIterable, Identifiable {
        case link, file, manual
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .link: "URL"
            case .file: "File"
            case .manual: "Manual"
            }
        }
    }

    let addLink: (String) async throws -> Void
    let addManual: (String, String) async throws -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @State private var tab: Tab = .link
    @State private var link = ""
    @State private var name = ""
    @State private var scriptBody = ""
    @State private var choosingFile = false
    @State private var busy = false
    @State private var error: String?

    private var canAdd: Bool {
        switch tab {
        case .link: !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
        case .file, .manual: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !scriptBody.isEmpty && !busy
        }
    }

    var body: some View {
        HakoMacSheetFrame(title: .copy("Add Script"), subtitle: .copy("Scripts"), width: 560, height: 500) {
            VStack(spacing: 0) {
                Picker(selection: $tab) {
                    ForEach(Tab.allCases) { item in Text(hako: .copy(item.title)).tag(item) }
                } label: {
                    Text(hako: .copy("Add Script"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 16)
                .accessibilityIdentifier("configuration-center.script-add.tabs")
                HakoMacSheetForm {
                    switch tab {
                    case .link:
                        Section {
                            TextField(text: $link, prompt: Text(verbatim: "https://")) { Text(hako: .copy("URL")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.link")
                        }
                    case .file:
                        Section {
                            LabeledContent {
                                Button { choosingFile = true } label: { Text(hako: .copy("Choose File")) }
                                    .disabled(busy)
                                    .accessibilityIdentifier("configuration-center.script-add.choose-file")
                            } label: {
                                Text(hako: name.isEmpty ? .copy("File") : .verbatim(name))
                            }
                            TextField(text: $name, prompt: Text(hako: .copy("Name"))) { Text(hako: .copy("Name")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.file-name")
                        }
                    case .manual:
                        Section {
                            TextField(text: $name, prompt: Text(hako: .copy("New Script"))) { Text(hako: .copy("Name")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.name")
                            TextEditor(text: $scriptBody)
                                .font(.body.monospaced())
                                .frame(minHeight: 180)
                                .disabled(busy)
                                .accessibilityLabel(Text(hako: .copy("Script")))
                                .accessibilityIdentifier("configuration-center.script-add.body")
                        }
                    }
                    if let error {
                        Section {
                            Text(verbatim: error).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.script-add.error")
                        }
                    }
                }
                .accessibilityIdentifier("configuration-center.script-add")
            }
        } trailing: {
            HakoMacSheetButtons(
                closeIdentifier: "configuration-center.script-add.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.script-add.add",
                primaryDisabled: !canAdd,
                isBusy: busy,
                onClose: close,
                onPrimary: add
            )
        }
        .onChange(of: tab) { _ in error = nil }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.plainText, .text, .javaScript].compactMap { $0 }) { result in
            switch result {
            case .success(let picked):
                let scoped = picked.startAccessingSecurityScopedResource()
                defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
                do {
                    scriptBody = try String(contentsOf: picked, encoding: .utf8)
                    if name.isEmpty { name = picked.deletingPathExtension().lastPathComponent }
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }

    private func add() {
        guard canAdd else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                switch tab {
                case .link: try await addLink(link.trimmingCharacters(in: .whitespacesAndNewlines))
                case .file, .manual: try await addManual(name.trimmingCharacters(in: .whitespacesAndNewlines), scriptBody)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
