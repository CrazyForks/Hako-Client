import HakoClientUI
import SwiftUI

 
 
 
 
 
public enum HakoMacQuickAddStatus: Equatable, Sendable {
     
    case busy(String)
     
    case failure(String)
     
     
    case notice(HakoDisplayText)
}

 
 
 
 
 
public struct HakoMacQuickAddDoors: Equatable, Sendable {
    public let scans: Bool
    public let importsFile: Bool

    public init(scans: Bool = true, importsFile: Bool = true) {
        self.scans = scans
        self.importsFile = importsFile
    }

    var isEmpty: Bool { !scans && !importsFile }
}

 
 
 
 
 
 
 
 
 
 
 
public struct HakoMacQuickAddCard<Paste: View>: View {
    private let header: HakoDisplayText
    @Binding private var text: String
    private let placeholder: String
    private let status: HakoMacQuickAddStatus?
    private let isBusy: Bool
    private let doors: HakoMacQuickAddDoors
    private let identifiers: HakoMacQuickAddIdentifiers
    private let submit: () -> Void
    private let scan: () -> Void
    private let importFile: () -> Void
    private let paste: () -> Paste

    public init(
        header: HakoDisplayText,
        text: Binding<String>,
        placeholder: String,
        status: HakoMacQuickAddStatus?,
        isBusy: Bool,
        doors: HakoMacQuickAddDoors = .init(),
        identifiers: HakoMacQuickAddIdentifiers,
        submit: @escaping () -> Void,
        scan: @escaping () -> Void,
        importFile: @escaping () -> Void,
        @ViewBuilder paste: @escaping () -> Paste
    ) {
        self.header = header
        _text = text
        self.placeholder = placeholder
        self.status = status
        self.isBusy = isBusy
        self.doors = doors
        self.identifiers = identifiers
        self.submit = submit
        self.scan = scan
        self.importFile = importFile
        self.paste = paste
    }

    public var body: some View {
        HakoMacCardSection(header) {
             
             
             
             
             
             
             
            HStack(spacing: HakoTheme.Spacing.compact) {
                 
                 
                TextField("", text: $text, prompt: Text(verbatim: placeholder))
                    .textFieldStyle(.plain)
                    .onSubmit(submit)
                    .disabled(isBusy)
                    .accessibilityIdentifier(identifiers.linkIdentifier)
                paste()
                    .disabled(isBusy)
                if doors.scans {
                    Button(action: scan) {
                        Label {
                            Text(HakoCopy.key("Scan"))
                        } icon: {
                            HakoSymbolImage(symbol: .qrcodeViewfinder)
                        }
                    }
                    .accessibilityIdentifier(identifiers.scanIdentifier)
                }
                if doors.importsFile {
                     
                     
                     
                     
                    Button(action: importFile) {
                        Label {
                            Text(HakoCopy.key("Import"))
                        } icon: {
                            HakoSymbolImage(symbol: .arrowUpDocument)
                        }
                    }
                    .accessibilityIdentifier(identifiers.fileIdentifier)
                }
            }
             
             
             
             
             
             
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.primary)
            .disabled(isBusy)
            .hakoMacCardRow(isLast: status == nil)

            if let status {
                statusRow(status)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hakoMacCardRow(isLast: true)
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ status: HakoMacQuickAddStatus) -> some View {
        switch status {
        case .busy(let host):
            HStack(spacing: HakoTheme.Spacing.compact) {
                ProgressView().controlSize(.small)
                Text(hako: .format("Downloading %@…", [host]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier(identifiers.statusIdentifier)
        case .failure(let message):
             
             
            Text(verbatim: message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifiers.statusIdentifier)
        case .notice(let text):
            Text(hako: text)
                .font(.subheadline)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifiers.statusIdentifier)
        }
    }
}

 
 
 
public struct HakoMacQuickAddIdentifiers: Sendable {
    public let linkIdentifier: String
    public let scanIdentifier: String
    public let fileIdentifier: String
    public let statusIdentifier: String

    public init(
        linkIdentifier: String,
        scanIdentifier: String,
        fileIdentifier: String,
        statusIdentifier: String
    ) {
        self.linkIdentifier = linkIdentifier
        self.scanIdentifier = scanIdentifier
        self.fileIdentifier = fileIdentifier
        self.statusIdentifier = statusIdentifier
    }
}

