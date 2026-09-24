import HakoClientKit
import HakoClientUI
import HakoMacClient
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
struct MacQuickAddCard: View {
    @ObservedObject var controller: ProfileQuickAddController
    let identifiers: HakoMacQuickAddIdentifiers
    let doors: HakoMacQuickAddDoors

    var body: some View {
        HakoMacQuickAddCard(
            header: .copy(controller.headerKey),
            text: Binding(
                get: { controller.state.text },
                set: { controller.state.text = $0 }
            ),
            placeholder: Self.placeholder,
            status: Self.status(controller.state.phase),
            isBusy: controller.state.isBusy,
            doors: doors,
            identifiers: identifiers,
            submit: { controller.submitTyped() },
            scan: { controller.showsQRCapture = true },
            importFile: { controller.showsImporter = true }
        ) {
            HakoPasteControl(style: .square) { pasted in
                controller.acceptPasted(pasted)
            }
        }
         
         
        .profileQuickAddPresenters(controller)
    }

     
     
    static let placeholder = "https://example.com/config.yaml"

     
     
     
    static func status(_ phase: ProfileQuickAddState.Phase) -> HakoMacQuickAddStatus? {
        switch phase {
        case .idle:
            return nil
        case .busy(let host):
            return .busy(host)
        case .failed(let message):
            return .failure(message)
        case .notice(.nodeBelongsInCustomNodes):
            return .notice(
                .copy("That is a node, not a profile URL. Add it under a profile's Custom Nodes.")
            )
        }
    }
}

extension HakoMacQuickAddIdentifiers {
     
     
     
     
     
     
     
     
     
     
    static let configurations = HakoMacQuickAddIdentifiers(
        linkIdentifier: "configuration.library.configurations.quick-add.link",
        scanIdentifier: "configuration.library.configurations.quick-add.scan",
        fileIdentifier: "configuration.library.configurations.quick-add.file",
        statusIdentifier: "configuration.library.configurations.quick-add.status"
    )
    static let nodes = HakoMacQuickAddIdentifiers(
        linkIdentifier: "configuration.library.nodes.quick-add.link",
        scanIdentifier: "configuration.library.nodes.quick-add.scan",
        fileIdentifier: "configuration.library.nodes.quick-add.file",
        statusIdentifier: "configuration.library.nodes.quick-add.status"
    )
    static let rules = HakoMacQuickAddIdentifiers(
        linkIdentifier: "configuration.library.rules.quick-add.link",
        scanIdentifier: "configuration.library.rules.quick-add.scan",
        fileIdentifier: "configuration.library.rules.quick-add.file",
        statusIdentifier: "configuration.library.rules.quick-add.status"
    )
    static let scripts = HakoMacQuickAddIdentifiers(
        linkIdentifier: "configuration.library.scripts.quick-add.link",
        scanIdentifier: "configuration.library.scripts.quick-add.scan",
        fileIdentifier: "configuration.library.scripts.quick-add.file",
        statusIdentifier: "configuration.library.scripts.quick-add.status"
    )
}
