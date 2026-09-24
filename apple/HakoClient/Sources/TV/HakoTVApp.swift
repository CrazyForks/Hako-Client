import Foundation
import SwiftUI

@main
struct HakoTVApp: App {
    @UIApplicationDelegateAdaptor(HakoTVAppDelegate.self) private var appDelegate

    private let launchOverrides = HakoTVLaunchOverrides(environment: [:])


    var body: some Scene {
        WindowGroup {
            HakoTVLaunchRoot(overrides: launchOverrides)
        }
    }
}

 
 
 
final class HakoTVAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HakoTVAutoUpdate.register { await HakoTVAutoUpdate.refreshInBackground() }
        return true
    }
}

private struct HakoTVLaunchRoot: View {
    let overrides: HakoTVLaunchOverrides

    @ViewBuilder
    var body: some View {
        if overrides.contentSize == .accessibilityExtraLarge {
            shell.environment(\.sizeCategory, .accessibilityExtraLarge)
        } else {
            shell
        }
    }

    private var shell: some View {
        HakoTVShell(stage: overrides.stage, connectsOnLaunch: overrides.connectsOnLaunch, updatesOnLaunch: overrides.updatesOnLaunch, matrix: overrides)
            .preferredColorScheme(overrides.appearance?.colorScheme)
    }
}
