import Foundation

 
 
 
 
 
 
 
 
 
 
enum HakoWidgetPlatform {
    static var countsWired: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}

 
 
 
extension HakoAppIdentifiers {
     
     
     
     
     
     
    static let packetTunnelProviderBundleIDs: Set<String> = [
        packetTunnelExtensionBundleID,
        macPacketTunnelExtensionBundleID,
    ]
}
