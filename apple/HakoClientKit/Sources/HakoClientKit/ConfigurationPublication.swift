import Foundation

 
 
public struct ConfigurationPublicationReference: Codable, Equatable, Hashable, Sendable {
    public let profileID: String
    public let version: String
    public init(profileID: String, version: String = UUID().uuidString) {
        self.profileID = profileID; self.version = version
    }
}

 
 
public struct ConfigurationPublicationPayload: Codable, Equatable, Sendable {
    public let reference: ConfigurationPublicationReference
    public let profileMetadata: Data
    public let yaml: String
    public init(reference: ConfigurationPublicationReference, profileMetadata: Data, yaml: String) {
        self.reference = reference; self.profileMetadata = profileMetadata; self.yaml = yaml
    }
}
