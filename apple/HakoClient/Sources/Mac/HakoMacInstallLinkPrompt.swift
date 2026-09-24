import Foundation

 
 
 
 
 
 
 
 
 
 
 
struct HakoMacInstallLinkPrompt {
     
     
     
    let pending: String

    init(pending: String) {
        self.pending = pending
    }

     
     
     
    var isLocalConfiguration: Bool {
        FlClashInstallLink.isLocalOrigin(pending)
    }

    var title: String {
        isLocalConfiguration ? "Add this configuration?" : "Add this config URL?"
    }

     
    var lead: String {
        isLocalConfiguration
            ? "A link wants to add a configuration to Clash.\n\n"
            : "A link wants to add a config URL to Clash.\n\n"
    }

     
    var link: String {
        ProfileImportRouter.confirmationText(for: pending)
    }

     
    var message: String {
        lead + link
    }

     
     
     
    static let dismissalDeclines = false
}
