import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
struct ProfileQuickAddState: Equatable {
    enum Notice: Equatable { case nodeBelongsInCustomNodes }
    enum Phase: Equatable {
        case idle
        case busy(host: String)
        case failed(String)
        case notice(Notice)
    }

    var text = ""
    var phase: Phase = .idle
     
     
    private(set) var pending: ProfileQuickAddInput?

    var isBusy: Bool {
        if case .busy = phase { return true }
        return false
    }

    var canSubmit: Bool {
        !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

     
     
    mutating func accept(_ input: ProfileQuickAddInput) {
        switch input {
        case .nothing:
            phase = .idle
        case .nodeShareLink:
            phase = .notice(.nodeBelongsInCustomNodes)
        case .link(let url):
            text = url
            pending = input
        case .document, .nodes:
            pending = input
        }
    }

    mutating func begin(_ input: ProfileQuickAddInput) {
        pending = nil
        switch input {
        case .link(let url):
            text = url
            phase = .busy(host: URL(string: url)?.host ?? url)
        case let .document(fileName, _):
            phase = .busy(host: fileName)
        case .nodes:
            phase = .busy(host: "Custom Nodes")
        case .nodeShareLink, .nothing:
            phase = .idle
        }
    }

    mutating func succeed() {
        phase = .idle
        text = ""
    }

     
    mutating func fail(_ message: String) {
        phase = .failed(message)
    }
}

 
 
 
 
 
 
 
@MainActor
final class ProfileQuickAddController: ObservableObject {
     
     
     
     
     
    enum Target { case profile, source, rules, scripts }

    let target: Target
    @Published var state = ProfileQuickAddState()
    @Published var showsImporter = false
    @Published var showsQRCapture = false {
        didSet {
             
             
            if showsQRCapture, !oldValue { hasDeliveredScan = false }
        }
    }
    @Published var showsQRPhotoPicker = false
     
     
    var onFirstProfileCreated: (() -> Void)?
     
    var onSourceAdded: ((ConfigurationLibrarySnapshot) -> Void)?
     
    var onScriptAdded: ((ConfigScript) -> Void)?
     
     
     
    private var pendingScan: Result<String, Error>?
     
     
    private var hasDeliveredScan = false
    private let model: ProfilesViewModel

    init(model: ProfilesViewModel, target: Target) {
        self.model = model
        self.target = target
    }

     
     
     
     
     
    var importContentTypes: [UTType] {
        switch target {
         
         
         
         
         
         
        case .profile, .source, .rules: [.yaml, .plainText, .text]
        case .scripts: [.javaScript, .plainText, .text]
        }
    }

    var headerKey: String {
        switch target {
        case .profile: "Add Profile"
        case .source: "Add Nodes"
        case .rules: "Add Rules"
         
         
        case .scripts: "Add Script"
        }
    }

    func submitTyped() {
        guard state.canSubmit else { return }
        state.accept(classify(state.text))
        runPending()
    }

    func acceptPasted(_ raw: String) {
        state.accept(classify(raw))
        runPending()
    }

    func acceptScanned(_ code: String) {
        state.accept(classify(code))
        runPending()
    }

     
     
    func classify(_ raw: String) -> ProfileQuickAddInput {
        Self.classify(raw, for: target)
    }

    nonisolated static func classify(_ raw: String, for target: Target) -> ProfileQuickAddInput {
         
         
         
        if target == .source, case .nodeShareLinks(let links) = PastedContentClassifier.classify(raw) {
            return .nodes(links.joined(separator: "\n"))
        }
        return ProfileQuickAddInput.classify(raw)
    }

     
    func holdScan(_ result: Result<String, Error>) {
         
         
         
         
         
        guard !hasDeliveredScan else { return }
        hasDeliveredScan = true
        pendingScan = result
        showsQRCapture = false
        showsQRPhotoPicker = false
#if os(macOS)
         
         
         
         
         
         
         
        deliverPendingScan()
#endif
    }

     
    func deliverPendingScan() {
        guard let result = pendingScan else { return }
        pendingScan = nil
        switch result {
        case .success(let code): acceptScanned(code)
        case .failure(let error): state.fail(error.localizedDescription)
        }
    }

    func importFile(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = AddProfileDraft.configurationFile(among: urls) else {
                throw ProfileInstallLinkError.unsupportedFile
            }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw ProfileInstallLinkError.unreadableFile }
            guard data.count <= ProfileExternalResourceImporter.maximumResourceBytes else {
                throw ProfileInstallLinkError.fileTooLarge
            }
            state.accept(.document(fileName: url.lastPathComponent, data: data))
            runPending()
        } catch {
            state.fail(error.localizedDescription)
        }
    }

     
    private func runPending() {
        guard let input = state.pending else { return }
        state.begin(input)
        Task { @MainActor in
            do {
                switch target {
                case .profile:
                    let outcome = try await model.quickCreate(input)
                    state.succeed()
                    if outcome.isFirstUserProfile { onFirstProfileCreated?() }
                case .source:
                    let snapshot = try await model.quickAddSource(input)
                    state.succeed()
                    onSourceAdded?(snapshot)
                case .rules:
                    let snapshot = try await model.quickAddRules(input)
                    state.succeed()
                    onSourceAdded?(snapshot)
                case .scripts:
                     
                     
                     
                     
                     
                    let script = try await ScriptQuickAdd.add(input)
                    state.succeed()
                    onScriptAdded?(script)
                }
            } catch {
                state.fail(
                    ConfigurationFailureClassifier.classify(
                        error, context: .localImport, preservesLastKnownGood: false
                    )?.localizedDescription ?? error.localizedDescription
                )
            }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
struct ProfileQuickAddIdentifiers {
    let linkIdentifier: String
    let scanIdentifier: String
    let fileIdentifier: String
    let manualIdentifier: String
    let statusIdentifier: String
}

struct ProfileQuickAddCard: View {
    @ObservedObject var controller: ProfileQuickAddController
    let identifiers: ProfileQuickAddIdentifiers
     
    var onFirstProfileCreated: (() -> Void)? = nil
     
    var manual: (() -> Void)? = nil

    var body: some View {
        Section {
            HStack(spacing: HakoTheme.Spacing.compact) {
                linkField
                HakoPasteControl(style: .square) { pasted in
                    controller.acceptPasted(pasted)
                }
                .disabled(controller.state.isBusy)
            }
            statusRow
            actionRow
        } header: {
             
             
            HakoConfigurationLibraryHeader(title: .copy(controller.headerKey))
        }
        .onAppear { controller.onFirstProfileCreated = onFirstProfileCreated }
    }

     
     
     
     
     
     
     
     
     
     
     
    private var actionRow: some View {
        HStack(alignment: .top, spacing: HakoTheme.Spacing.compact) {
            Button {
                controller.showsQRCapture = true
            } label: {
                 
                Label(HakoCopy.key("Scan"), systemImage: HakoSymbol.qrcodeViewfinder.name)
            }
            .accessibilityIdentifier(identifiers.scanIdentifier)
            Button {
                controller.showsImporter = true
            } label: {
                Label(HakoCopy.key("Import"), systemImage: HakoSymbol.arrowUpDocument.name)
            }
            .accessibilityIdentifier(identifiers.fileIdentifier)
            if let manual {
                Button(action: manual) {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    Label(HakoCopy.key("quick-add.door.create"), systemImage: HakoSymbol.pencilLine.name)
                }
                .accessibilityIdentifier(identifiers.manualIdentifier)
            }
        }
        .labelStyle(QuickAddDoorLabelStyle())
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(controller.state.isBusy)
        .padding(.vertical, HakoTheme.Spacing.tight)
    }

     
     
     
    private var linkField: some View {
        TextField("", text: $controller.state.text, prompt: Text(verbatim: "https://example.com/config.yaml"))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { controller.submitTyped() }
            .disabled(controller.state.isBusy)
            .accessibilityIdentifier(identifiers.linkIdentifier)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch controller.state.phase {
        case .idle:
            EmptyView()
        case .busy(let host):
            HStack(spacing: HakoTheme.Spacing.compact) {
                ProgressView().controlSize(.small)
                Text(hako: .format("Downloading %@…", [host]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier(identifiers.statusIdentifier)
        case .failed(let message):
            HakoStatusMessage(text: .verbatim(message), kind: .error)
                .accessibilityIdentifier(identifiers.statusIdentifier)
        case .notice(.nodeBelongsInCustomNodes):
            HakoStatusMessage(
                text: .copy("That is a node, not a profile URL. Add it under a profile's Custom Nodes."),
                kind: .warning
            )
            .accessibilityIdentifier(identifiers.statusIdentifier)
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct QuickAddDoorLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: HakoTheme.Spacing.compact - 2) {
            configuration.icon
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    .tint.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: HakoTheme.Radius.icon, style: .continuous)
                )
            configuration.title
                .font(.footnote)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

extension View {
     
     
    func profileQuickAddPresenters(_ controller: ProfileQuickAddController) -> some View {
        modifier(ProfileQuickAddPresenters(controller: controller))
    }
}

private struct ProfileQuickAddPresenters: ViewModifier {
    @ObservedObject var controller: ProfileQuickAddController

    func body(content: Content) -> some View {
        content
             
             
             
            .fileImporter(isPresented: $controller.showsImporter,
                          allowedContentTypes: controller.importContentTypes,
                          allowsMultipleSelection: false) { result in
                controller.importFile(result)
            }
            .hakoProductModal(isPresented: $controller.showsQRCapture, role: .page,
                              onDismiss: { controller.deliverPendingScan() }) {
                HakoFeatureNavigationContainer {
                    Form {
                         
                         
                         
                         
                        Section {
                            QRScannerView { code in
                                controller.holdScan(.success(code))
                            }
                             
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: HakoTheme.Radius.card, style: .continuous))
                        }
                        Section {
                            Button {
#if os(macOS)
                                 
                                 
                                QRImagePanel.choose { result in
                                    guard let result else { return }
                                    controller.holdScan(result)
                                    controller.showsQRCapture = false
                                }
#else
                                controller.showsQRCapture = false
                                controller.showsQRPhotoPicker = true
#endif
                            } label: {
                                Label("Choose QR from Photos", systemImage: HakoSymbol.photo.name)
                                    .foregroundStyle(.primary)
                            }
                             
                             
                             
                             
                             
                             
                            .hakoMacFormActionChrome()
                        }
                    }
                    .hakoPageTitle("Scan QR Code")
                    .hakoToolbarUnlessInPanel {
                        ToolbarItem(placement: .cancellationAction) {
                            HakoSheetCloseButton { controller.showsQRCapture = false }
                        }
                    }
                    .hakoProductModalRoot(title: "Scan QR Code")
                }
                .hakoModalPresentation(.page)
            }
            .hakoProductModal(isPresented: $controller.showsQRPhotoPicker, role: .page,
                              onDismiss: { controller.deliverPendingScan() }) {
                QRPhotoPicker { result in
                     
                    if let result { controller.holdScan(result) } else { controller.showsQRPhotoPicker = false }
                }
                .hakoModalPresentation(.page)
                .hakoProductModalRoot(title: "Choose QR from Photos")
            }
    }
}
