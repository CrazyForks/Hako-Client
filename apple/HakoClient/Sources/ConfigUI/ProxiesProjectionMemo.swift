import Foundation
import HakoClientUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ProxiesProjectionMemo {
    struct GroupsKey: Equatable {
         
         
         
         
        let outboundMode: ProxyBrowsingVisibility.Mode
        let source: [ProxiesOverviewModel.Group]
        let runtimeCatalog: [ProxyGroup]
        let nowByGroup: [String: String]
        let resolvedNowByGroup: [String: String]
        let isConnected: Bool
    }

    struct UngroupedKey: Equatable {
         
        let outboundMode: ProxyBrowsingVisibility.Mode
        let source: [ProxiesOverviewModel.Proxy]
        let runtimeNodes: [ProxiesOverviewModel.Proxy]
        let runtimeGroups: [ProxyGroup]
        let isConnected: Bool
        let runtimeIsAuthoritative: Bool
    }

    private var groupsKey: GroupsKey?
     
     
     
    struct GroupProjection: Equatable {
        var listed: [HakoProxyGroupSnapshot]
        var hidden: [HakoProxyGroupSnapshot] = []
    }

    private var groupsValue = GroupProjection(listed: [])
    private var ungroupedKey: UngroupedKey?
    private var ungroupedValue: [HakoProxySnapshot] = []

     
     
    private(set) var builds = 0

     
     
     
     
     
    private var memberRowsByGroup:
        [String: (members: [ProxiesOverviewModel.Member], endpoint: String?, rows: [HakoProxyMemberSnapshot])] = [:]
    private(set) var memberBuilds = 0

    private var endpointStates: (input: [String: [String: Int]], namedURLs: Set<String>,
                                 reasons: [String: String], defaultURL: String,
                                 output: [String: HakoProxyLatencyState])?

     
     
     
    func endpointLatencyStates(
        _ endpointDelays: [String: [String: Int]],
        namedURLs: Set<String>,
        failureReasons: [String: String],
        defaultURL: String
    ) -> [String: HakoProxyLatencyState] {
        if let kept = endpointStates, kept.defaultURL == defaultURL, kept.namedURLs == namedURLs,
           kept.reasons == failureReasons, kept.input == endpointDelays {
            return kept.output
        }
        var output: [String: HakoProxyLatencyState] = [:]
        for (url, readings) in endpointDelays where namedURLs.contains(url) {
            let prefix = NodeInventory.latencyKey("", endpoint: url, defaultURL: defaultURL)
            for (name, value) in readings {
                output[prefix + name] = ProxiesLatencyMapping.state(
                    delay: value, category: failureReasons[name] ?? "")
            }
        }
        endpointStates = (endpointDelays, namedURLs, failureReasons, defaultURL, output)
        return output
    }

    func members(
        of group: ProxiesOverviewModel.Group,
        latencyEndpoint: String? = nil,
        defaultURL: String = ""
    ) -> [HakoProxyMemberSnapshot] {
        let endpoint = latencyEndpoint
        if let kept = memberRowsByGroup[group.name],
           kept.members == group.members, kept.endpoint == endpoint {
            return kept.rows
        }
        memberBuilds += 1
        let rows = group.members.map {
            HakoProxyMemberSnapshot(
                name: $0.name,
                type: $0.type,
                isGroup: $0.isGroup,
                chainedThrough: $0.chainedThrough,
                placeholderType: $0.placeholderType,
                latencyKey: $0.isGroup ? nil
                    : NodeInventory.latencyKey($0.name, endpoint: endpoint, defaultURL: defaultURL)
            )
        }
        memberRowsByGroup[group.name] = (group.members, endpoint, rows)
        return rows
    }

     
     
     
     
     
     
     
    private static func firstDifference(
        _ old: GroupsKey, _ new: GroupsKey
    ) -> String {
        if old.source != new.source { return "source" }
        if old.runtimeCatalog != new.runtimeCatalog { return "runtimeCatalog" }
        if old.nowByGroup != new.nowByGroup { return "nowByGroup" }
        if old.resolvedNowByGroup != new.resolvedNowByGroup {
            return "resolvedNowByGroup"
        }
        if old.isConnected != new.isConnected { return "isConnected" }
         
         
         
        return "unknown"
    }

    func groups(
        _ key: GroupsKey,
        build: () -> GroupProjection
    ) -> GroupProjection {
        if let groupsKey {
            if groupsKey == key { return groupsValue }
            HakoPerf.count(
                "proxies.memo.miss." + Self.firstDifference(groupsKey, key)
            )
        }
        builds += 1
        let value = build()
        groupsKey = key
        groupsValue = value
        return value
    }

    func ungrouped(
        _ key: UngroupedKey,
        build: () -> [HakoProxySnapshot]
    ) -> [HakoProxySnapshot] {
        if let ungroupedKey, ungroupedKey == key { return ungroupedValue }
        builds += 1
        let value = build()
        ungroupedKey = key
        ungroupedValue = value
        return value
    }
}


 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProxiesSweepSnapshotHold {
    struct Key: Equatable {
        let preferences: HakoProxiesDisplayPreferences
        let outboundModeToken: String
        let isConnected: Bool
        let nowByGroup: [String: String]
        let resolvedNowByGroup: [String: String]
        let groupCount: Int
        let ungroupedCount: Int
    }

    static func servesHeld(
        isSweeping: Bool,
        held: Key?,
        current: Key
    ) -> Bool {
        guard isSweeping, let held else { return false }
        return held == current
    }
}
