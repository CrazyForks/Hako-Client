import Foundation

 
 
 
 
 
enum HakoTVOverrideScript {
    static let notText = "The script is not text."
    static let noScript = "This profile has no override script to update."

    static func apply(script: String, toYAML yaml: String, profileName: String) throws -> String {
        let json = try ConfigTransforms.yamlToJSON(yaml)
        let scripted = try ScriptEngine.run(script: script, configJSON: json, profileName: profileName)
        return try ConfigTransforms.jsonToYAML(scripted)
    }
}
