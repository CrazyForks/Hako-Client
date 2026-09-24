import HakoClientKit
import HakoClientUI
import SwiftUI

 
 
 
public struct HakoMacSubscriptionSettingsState: Equatable, Sendable {
    public var url: String
    public var autoUpdate: Bool
    public var updateIntervalHours: Int
    public var canStripCredentials: Bool

    public init(url: String, autoUpdate: Bool, updateIntervalHours: Int, canStripCredentials: Bool) {
        self.url = url
        self.autoUpdate = autoUpdate
        self.updateIntervalHours = updateIntervalHours
        self.canStripCredentials = canStripCredentials
    }
}

 
 
public struct HakoMacSubscriptionSettingsActions {
    public var save: @MainActor (HakoMacSubscriptionSettingsState) async throws -> HakoMacSubscriptionSettingsState
    public var stripCredentials: @MainActor () async throws -> HakoMacSubscriptionSettingsState

    public init(
        save: @escaping @MainActor (HakoMacSubscriptionSettingsState) async throws -> HakoMacSubscriptionSettingsState,
        stripCredentials: @escaping @MainActor () async throws -> HakoMacSubscriptionSettingsState
    ) {
        self.save = save
        self.stripCredentials = stripCredentials
    }

    public static var unavailable: HakoMacSubscriptionSettingsActions {
        HakoMacSubscriptionSettingsActions(
            save: { _ in throw ConfigurationLibraryError.unreadable },
            stripCredentials: { throw ConfigurationLibraryError.unreadable }
        )
    }
}
