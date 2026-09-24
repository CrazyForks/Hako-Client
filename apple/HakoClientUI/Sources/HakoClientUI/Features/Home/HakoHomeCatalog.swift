public enum HakoHomeSection:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case common

    public var id: Self { self }

    public var title: String {
        switch self {
        case .common: "General"
        }
    }
}

public enum HakoHomeCard:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case routing
    case proxies
    case rules
    case traffic
    case externalIP
    case lanIP

    public var id: Self { self }

    public var title: String {
        switch self {
        case .routing: "Outbound Mode"
        case .proxies: "Proxies"
        case .rules: "Rules"
        case .traffic: "Traffic"
        case .externalIP: "External IP"
        case .lanIP: "LAN IP"
        }
    }

    public var symbol: HakoSymbol {
        switch self {
        case .routing: .arrowTriangleBranch
        case .proxies: .serverRack
        case .rules: .ruleDomain
        case .traffic: .waveformPathEcg
        case .externalIP: .globe
        case .lanIP: .point3ConnectedTrianglepathDotted
        }
    }
}

public enum HakoHomeCatalog {
    public static let defaultCards: [HakoHomeCard] = [
        .routing, .proxies, .rules, .traffic,
    ]
    public static let requiredCards: [HakoHomeCard] = [
        .routing, .proxies, .rules,
    ]
    public static let optionalCards: [HakoHomeCard] = [
        .traffic, .externalIP, .lanIP,
    ]

     
     
     
     
    public static func visibleCards(_ cards: [HakoHomeCard], mode: AppleClientOutboundMode) -> [HakoHomeCard] {
        switch mode {
        case .rule: return cards
        case .global: return cards.filter { $0 != .rules }
        case .direct: return cards.filter { $0 != .rules && $0 != .proxies }
        }
    }

    public static func normalized(_ cards: [HakoHomeCard]) -> [HakoHomeCard] {
        var seen = Set<HakoHomeCard>()
        var result = cards.filter { seen.insert($0).inserted }
        for card in requiredCards where seen.insert(card).inserted {
            result.append(card)
        }
        return result
    }
}

