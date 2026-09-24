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
        let bases = ConfigurationBuiltins.schemes + availableRules.filter {
            $0.baseSchemeID == nil || $0.baseSchemeID.map(ConfigurationBuiltins.isNative) == true
        }
        var seen = Set<String>()
        return bases.filter { seen.insert($0.id).inserted }.map { base in
            ConfigurationBuiltins.isNative(base.id) ? base : (availableRules.first(where: { $0.baseSchemeID == base.id }) ?? base)
        }
    }
    func effectiveRuleScheme(_ id: String) -> ConfigurationRuleScheme? {
        if ConfigurationBuiltins.isNative(id) { return ConfigurationBuiltins.schemes.first { $0.id == id } }
        return availableRules.first { $0.baseSchemeID == id } ?? rules.first { $0.id == id } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
    }

     
    func ruleSchemeAfterSavingCustomization(_ id: String) -> ConfigurationRuleScheme? {
        if ConfigurationBuiltins.isNative(id) {
            return availableRules.last { $0.baseSchemeID == id } ?? effectiveRuleScheme(id)
        }
        return effectiveRuleScheme(id)
    }
}
