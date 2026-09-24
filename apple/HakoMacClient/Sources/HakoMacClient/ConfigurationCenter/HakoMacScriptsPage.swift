import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
public struct HakoMacScriptEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) {
        self.id = id
        self.label = label
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
    public var clearPatch: @MainActor () async throws -> HakoMacScriptsState
    public var removeException: @MainActor (Int) async throws -> HakoMacScriptsState

    public init(
        load: @escaping @MainActor () async -> HakoMacScriptsState,
        select: @escaping @MainActor (String?) async throws -> HakoMacScriptsState,
        addLink: @escaping @MainActor (String) async throws -> HakoMacScriptsState,
        addManual: @escaping @MainActor (String, String) async throws -> HakoMacScriptsState,
        remove: @escaping @MainActor (String) async throws -> HakoMacScriptsState,
        clearPatch: @escaping @MainActor () async throws -> HakoMacScriptsState,
        removeException: @escaping @MainActor (Int) async throws -> HakoMacScriptsState
    ) {
        self.load = load
        self.select = select
        self.addLink = addLink
        self.addManual = addManual
        self.remove = remove
        self.clearPatch = clearPatch
        self.removeException = removeException
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

    public var body: some View {
        List {
            Section {
                ForEach(state.scripts) { script in
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
                        Button(role: .destructive) { deleting = script } label: { Text(hako: .copy("Delete")) }
                    }
                }
                HakoMacListAddRow(.copy("Add Script")) { adding = true }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.scripts.add")
            } header: {
                Text(hako: .copy("Scripts"))
            }
            if state.patchFieldCount > 0 {
                Section {
                    HakoMacActionRow(
                        .copy("Field Patch"),
                        actionTitle: .copy("Clear Field Patch"),
                        action: { perform { try await actions.clearPatch() } }
                    ) {
                        Text(hako: .format("%@ fields", [String(state.patchFieldCount)]))
                            .foregroundStyle(.secondary)
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.scripts.patch")
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
                    Text(hako: .copy("This Configuration's Exceptions"))
                }
            }
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.scripts.error")
                }
            }
        }
        .listStyle(.inset)
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
            case .link: "Link"
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
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                ForEach(Tab.allCases) { item in Text(hako: .copy(item.title)).tag(item) }
            } label: {
                Text(hako: .copy("Add Script"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(HakoTheme.Spacing.row)
            .accessibilityIdentifier("configuration-center.script-add.tabs")
            List {
                switch tab {
                case .link:
                    Section {
                        HakoMacFieldRow(.copy("Link"), prompt: "https://", text: $link,
                                        identifier: "configuration-center.script-add.link")
                            .disabled(busy)
                    }
                case .file:
                    Section {
                        HakoMacActionRow(.copy("Choose File"), actionTitle: .copy("Choose File"),
                                         action: { choosingFile = true }) {
                            if !name.isEmpty { Text(verbatim: name).foregroundStyle(.secondary) }
                        }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.script-add.choose-file")
                        HakoMacFieldRow(.copy("Name"), prompt: HakoCopy.string("Name", locale: locale), text: $name,
                                        identifier: "configuration-center.script-add.file-name")
                            .disabled(busy)
                    }
                case .manual:
                    Section {
                        HakoMacFieldRow(.copy("Name"), prompt: HakoCopy.string("New Script", locale: locale), text: $name,
                                        identifier: "configuration-center.script-add.name")
                            .disabled(busy)
                        TextEditor(text: $scriptBody)
                            .font(.body.monospaced())
                            .frame(minHeight: 200)
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
            .listStyle(.inset)
            .accessibilityIdentifier("configuration-center.script-add")
            HStack {
                Button(action: close) { Text(hako: .copy("Cancel")) }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.script-add.cancel")
                Spacer()
                Button(action: add) { HakoActionProgressLabel(.copy("Add"), isBusy: busy) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
                    .accessibilityIdentifier("configuration-center.script-add.add")
            }
            .padding(HakoTheme.Spacing.row)
            .background(.bar)
        }
        .frame(width: 560, height: 480)
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
