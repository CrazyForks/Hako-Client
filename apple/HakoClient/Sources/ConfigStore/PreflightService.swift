import Foundation
import Hako

struct PreflightOutcome {
    let ok: Bool
    let intentJSON: String?
    let errorMessage: String?
}

 
 
 
enum PreflightService {
     
     
    static func check(finalYAML: String) -> PreflightOutcome {
        AppCoreSetup.serialized { checkConfigured(finalYAML: finalYAML) }
    }

    static func checkApplication(finalYAML: String) -> PreflightOutcome {
        guard let container = AppCoreSetup.applicationContainer else {
            return .init(ok: false, intentJSON: nil, errorMessage: "App Group container unavailable")
        }
        return check(finalYAML: finalYAML, container: container)
    }

    static func check(finalYAML: String, container: URL, settings: IPStackSettings? = nil) -> PreflightOutcome {
        do {
            return try AppCoreSetup.withConfiguration(container: container, settings: settings) {
                checkConfigured(finalYAML: finalYAML)
            }
        } catch {
            return .init(ok: false, intentJSON: nil, errorMessage: error.localizedDescription)
        }
    }

    private static func checkConfigured(finalYAML: String) -> PreflightOutcome {
        var checkError: NSError?
        let ok = HakoCheckConfig(finalYAML, &checkError)
        guard ok, checkError == nil else {
            return PreflightOutcome(
                ok: false, intentJSON: nil,
                errorMessage: checkError?.localizedDescription ?? "config check failed")
        }
        var intentError: NSError?
        guard let box = HakoPlatformConfigIntentJSON(finalYAML, &intentError) else {
            return PreflightOutcome(
                ok: false, intentJSON: nil,
                errorMessage: intentError?.localizedDescription ?? "intent extraction failed")
        }
        return PreflightOutcome(ok: true, intentJSON: box.value, errorMessage: nil)
    }
}
