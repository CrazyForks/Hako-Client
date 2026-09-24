import BackgroundTasks
import Foundation

 
 
 
 
 
 
 
enum HakoTVAutoUpdate {
    static let taskIdentifier = HakoAppIdentifiers.backgroundRefreshTask
    static let foregroundScanInterval: TimeInterval = 20 * 60
    static let foregroundScanKey = "hako.tv.autoUpdate.lastForegroundScan"
     
     
    static let minimumLead: TimeInterval = 3600

     
     
     
    static func isDue(_ row: HakoTVSubscription, now: Date) -> Bool {
        guard let hours = row.updateIntervalHours, hours > 0, row.hasFetchableAddress else { return false }
        guard let last = row.updatedAt else { return true }
        if last > now { return false }
        return last.addingTimeInterval(TimeInterval(hours) * 3600) <= now
    }

     
     
     
    static func nextEligibility(rows: [HakoTVSubscription], now: Date) -> Date? {
        let dates = rows.compactMap { row -> Date? in
            guard let hours = row.updateIntervalHours, hours > 0, row.hasFetchableAddress else { return nil }
            let due = (row.updatedAt ?? now).addingTimeInterval(TimeInterval(hours) * 3600)
            return max(due, now.addingTimeInterval(minimumLead))
        }
        return dates.min()
    }

    static func shouldScanOnForeground(now: Date, lastScan: Date?, minimumInterval: TimeInterval = foregroundScanInterval) -> Bool {
        guard let lastScan else { return true }
        if lastScan > now { return false }
        return now.timeIntervalSince(lastScan) >= minimumInterval
    }

     
     
     
    @MainActor
    static func scanOnForegroundIfDue(
        store: HakoTVSubscriptionStore,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        refresh: (HakoTVSubscription) async -> Void
    ) async {
        let lastScan = defaults.object(forKey: foregroundScanKey) as? Date
        guard shouldScanOnForeground(now: now, lastScan: lastScan) else { return }
        defaults.set(now, forKey: foregroundScanKey)
        guard let current = store.current, isDue(current, now: now) else { return }
        HakoLogStore.shared.append("tv auto update: row in use is due (interval \(current.updateIntervalHours ?? 0) h)", stream: .app)
        await refresh(current)
    }

     

     
     
     
     
    static func register(handler: @escaping () async -> Bool) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let work = Task {
                let success = await handler()
                task.setTaskCompleted(success: success)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule(earliest date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        guard let date else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }

     
     
    @MainActor
    static func refreshInBackground(now: Date = Date()) async -> Bool {
        var store = HakoTVSubscriptionStore(defaults: .standard)
        guard let current = store.current, isDue(current, now: now),
              let container = HakoTVTunnelController.defaultContainer
        else { return true }
        do {
            _ = try await HakoTVConfigPipeline(container: container).activate(subscription: current) { _ in }
            store.markUpdated(current.id, at: now)
            HakoLogStore.shared.append("tv auto update: background fetch published", stream: .app)
            return true
        } catch {
            HakoLogStore.shared.append("tv auto update: background fetch failed  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            return false
        }
    }
}
