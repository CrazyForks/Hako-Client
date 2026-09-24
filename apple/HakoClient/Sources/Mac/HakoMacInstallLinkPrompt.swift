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
        isLocalConfiguration ? "Add this profile?" : "Add this profile URL?"
    }

     
    var lead: String {
        isLocalConfiguration
            ? "An install link wants to add a profile to Clash.\n\n"
            : "An install link wants to add a profile URL to Clash.\n\n"
    }

     
    var link: String {
        ProfileImportRouter.confirmationText(for: pending)
    }

     
    var message: String {
        lead + link
    }

     
     
     
    static let dismissalDeclines = false
}
