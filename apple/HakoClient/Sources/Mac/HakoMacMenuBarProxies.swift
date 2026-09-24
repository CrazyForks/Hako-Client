import Foundation
import HakoClientUI

 
 
 
 
 
 
 
 
struct HakoMacMenuProxyCatalog: Equatable {
    struct Group: Equatable, Identifiable {
        let name: String
        let members: [String]
         
        let now: String
         
         
         
         
         
         
         
         
         
        var checked: String?
         
         
        var type: String = ""
         
         
        var latency: [String: HakoProxyLatencyState] = [:]
         
         
         
         
         
         
         
         
         
         
        var pinsOnRepick = false
        var id: String { name }
    }

    let groups: [Group]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func make(
        groups: [ProxyGroup],
        mode: ProxyBrowsingVisibility.Mode,
        delays: [String: Int] = [:],
        endpointDelays: [String: [String: Int]] = [:],
        testing: Set<String> = [],
        isConnected: Bool = true,
        configuredSelections: [String: String] = [:]
    ) -> HakoMacMenuProxyCatalog {
        let visible = ProxyBrowsingVisibility.groups(
            groups,
            mode: mode,
            name: \.name,
            isHidden: \.hidden
        )
         
         
         
         
        let emptyGroups = Set(groups.filter(\.isEmpty).map(\.name))
        let knownGroups = Set(groups.map(\.name))
        let byName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return HakoMacMenuProxyCatalog(
            groups: visible.compactMap { group in
                guard group.acceptsMemberChoice, !group.members.isEmpty,
                      !group.isEmpty else {
                    return nil
                }
                var latency: [String: HakoProxyLatencyState] = [:]
                for member in group.members {
                    if emptyGroups.contains(member) {
                        latency[member] = .untested
                        continue
                    }
                     
                     
                     
                    let measured = group.memberResolvedNames[member] ?? member
                     
                     
                     
                     
                     
                     
                     
                    let reading = group.memberGroupNames.contains(member) && knownGroups.contains(member)
                        ? NodeInventory.routeDelay(
                            from: member, byName: byName,
                            endpointDelays: endpointDelays, delays: delays
                        )
                        : NodeInventory.memberDelay(
                            measured, groupTestURL: group.testURL,
                            endpointDelays: endpointDelays, delays: delays
                        )
                    if testing.contains(measured) {
                        latency[member] = .testing
                    } else if let delay = reading {
                        latency[member] = delay > 0
                            ? .measured(milliseconds: delay)
                            : .failed
                    } else {
                        latency[member] = .untested
                    }
                }
                return Group(
                    name: group.name,
                    members: group.members,
                    now: group.now,
                    checked: isConnected ? group.now : configuredSelections[group.name],
                    type: group.type,
                    latency: latency,
                    pinsOnRepick: ProxyGroupControlKind(rawType: group.type)
                        == .automatic
                )
            }
        )
    }
}
