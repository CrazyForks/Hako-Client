import Foundation
import HakoClientKit

 
 
 
 
 
 
 
 
 
enum HakoTVComposedProfile {
    enum Failure: Error, Equatable, LocalizedError {
         
         
        case nodeListNeedsRules
         
         
        case noNodes(String)

        var errorDescription: String? {
            switch self {
            case .nodeListNeedsRules:
                String(localized: "This URL is a node list, not a configuration. Choose Default Rules or Lazy Rules for this profile.")
            case .noNodes(let reason):
                reason.isEmpty
                    ? String(localized: "No nodes were found at this URL.")
                    : String(localized: "No nodes were found at this URL.") + " " + reason
            }
        }
    }

    static func document(body: Data, rules: HakoTVProfileRules) throws -> String {
        guard let schemeID = rules.schemeID else {
            return try asWritten(body)
        }
        let nodesYAML: String
        do {
            nodesYAML = try ProxyImportBridge.derivedSubscription(from: body).yaml
        } catch {
            throw Failure.noNodes(error.localizedDescription)
        }
        let source = try OrderedJSON.parse(try ConfigTransforms.yamlToJSON(nodesYAML))
        guard hasNodes(source), let scheme = try ConfigurationBuiltins.source(for: schemeID) else {
            throw Failure.noNodes("")
        }
        let composition = try ConfigurationComposer.compose(
            sources: [ConfigurationInput(id: "profile", document: source)],
            rules: ConfigurationInput(id: scheme.record.id, document: try OrderedJSON.parse(scheme.documentJSON))
        )
        return try ConfigTransforms.jsonToYAML(composition.document.serialized())
    }

     
     
     
     
    private static func asWritten(_ body: Data) throws -> String {
        guard let text = String(data: body, encoding: .utf8) else {
            throw HakoTVSubscriptionFetcher.FetchError.notText
        }
        if (try? ConfigTransforms.validateSource(text)) == nil,
           let inspected = try? ProxyImportBridge.inspect(body, context: .subscriptionBody),
           !inspected.proxies.isEmpty {
            throw Failure.nodeListNeedsRules
        }
        return text
    }

    private static func hasNodes(_ document: OrderedJSON) -> Bool {
        guard case .object(let fields) = document else { return false }
        for (key, value) in fields where key == "proxies" || key == "proxy-providers" {
            switch value {
            case .array(let items) where !items.isEmpty: return true
            case .object(let entries) where !entries.isEmpty: return true
            default: continue
            }
        }
        return false
    }
}
