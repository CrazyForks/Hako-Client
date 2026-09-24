import Foundation

public struct ConfigurationLocalRuleSet: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var input: String
    public var rules: [String]
    public init(id: String = UUID().uuidString.lowercased(), name: String, input: String, rules: [String]) {
        self.id = id; self.name = name; self.input = input; self.rules = rules
    }
}

public extension ConfigurationLibrarySnapshot {
    var visibleRuleSchemes: [ConfigurationRuleScheme] {
         
         
         
        let available = availableRules
        let baseIDs = Set(available.filter { $0.baseSchemeID == nil }.map(\.id))
         
         
         
         
        let bases = ConfigurationBuiltins.schemes + available.filter {
            guard let base = $0.baseSchemeID else { return true }
            return ConfigurationBuiltins.isNative(base) || !baseIDs.contains(base)
        }
        var firstDerivative: [String: ConfigurationRuleScheme] = [:]
        for scheme in available {
            if let base = scheme.baseSchemeID, firstDerivative[base] == nil { firstDerivative[base] = scheme }
        }
        var seen = Set<String>()
        return bases.filter { seen.insert($0.id).inserted }.map { base in
            ConfigurationBuiltins.isNative(base.id) ? base : (firstDerivative[base.id] ?? base)
        }
    }
     
     
     
     
     
     
     
     
     
     
     
     
    func effectiveRuleScheme(_ id: String) -> ConfigurationRuleScheme? {
        if ConfigurationBuiltins.isNative(id) { return ConfigurationBuiltins.schemes.first { $0.id == id } }
        if let own = rules.first(where: { $0.id == id }), own.isRetainedSnapshot != true,
           own.collectionKey == nil, own.kind == .custom || own.kind == .imported {
            return own
        }
        let derivatives = availableRules.filter { $0.baseSchemeID == id }
        if let running = derivatives.first(where: { derivative in recipes.contains { $0.ruleSchemeID == derivative.id } }) {
            return running
        }
        return derivatives.last ?? rules.first { $0.id == id } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
    }

     
     
     
    func ruleSchemeAfterSavingCustomization(_ id: String) -> ConfigurationRuleScheme? {
        if let own = rules.first(where: { $0.id == id }), own.isRetainedSnapshot != true,
           own.collectionKey == nil, own.kind == .custom || own.kind == .imported {
            return own
        }
        return availableRules.last { $0.baseSchemeID == id } ?? effectiveRuleScheme(id)
    }
}
