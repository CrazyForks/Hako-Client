import HakoClientKit
import HakoClientUI
import SwiftUI

 
struct HakoMacSourceEditorRequest: Hashable, Codable {
    let profileID: String
     
     
    var nodeSourceID: String? = nil
     
     
    var collection: HakoMacCollectionReference? = nil
}

 
 
struct HakoMacCollectionReference: Hashable, Codable {
    let sourceID: String
    let kind: String
    let key: String

    init(_ entry: ConfigurationCollectionEntry) {
        sourceID = entry.id.sourceID
        kind = entry.id.kind.rawValue
        key = entry.id.key
    }

    func matches(_ entry: ConfigurationCollectionEntry) -> Bool {
        entry.id.sourceID == sourceID && entry.id.kind.rawValue == kind && entry.id.key == key
    }
}

 
 
 
 
struct HakoMacSourceEditorWindow: View {
    let request: HakoMacSourceEditorRequest
     
    @ObservedObject var profiles: ProfilesViewModel
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @State private var rawYAML: String??

    var body: some View {
        if let collection = request.collection {
            HakoMacCollectionSourceEditorWindow(reference: collection, profiles: profiles)
        } else if let sourceID = request.nodeSourceID {
            HakoMacNodeSourceEditorWindow(sourceID: sourceID, profiles: profiles)
        } else if let profile = profiles.profiles.first(where: { $0.id == request.profileID }) {
            content(for: profile)
                 
                 
                .task(id: request.profileID) {
                    guard rawYAML == nil else { return }
                     
                     
                     
                     
                    rawYAML = .some(await profiles.loadSourceYAML(for: profile))
                }
        } else {
            HakoEmptyState(
                title: "No Profile",
                message: "The profile is no longer available.",
                symbol: .curlybraces
            )
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    @ViewBuilder
    private func content(for profile: Profile) -> some View {
        if let rawYAML {
            HakoWindowDepartureHost {
                ProfileEditView(
                    profile: profile,
                    rawYAML: rawYAML
                ) { updated, rawYAML, resources, disablingAutoUpdate in
                    try await profiles.updateEdited(
                        updated,
                        sourceYAML: rawYAML,
                        resourceFiles: resources,
                        disablingAutoUpdate: disablingAutoUpdate
                    )
                }
            } windowGuard: { controller in
                HakoMacWindowCloseGuard(controller: controller)
            }
            .navigationTitle(Text(verbatim: profile.label))
            .navigationSubtitle("Edit Source")
            .frame(minWidth: 640, minHeight: 480)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(Text(verbatim: profile.label))
                .navigationSubtitle("Edit Source")
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}

 
 
 
struct HakoMacNodeSourceEditorWindow: View {
    let sourceID: String
    @ObservedObject var profiles: ProfilesViewModel
    @State private var loaded: (record: ConfigurationSourceRecord, yaml: String, version: ConfigurationSourceVersion)?
    @State private var errorMessage: String?

    var body: some View {
        if let loaded {
            HakoWindowDepartureHost {
                ProfileEditView(
                    profile: Profile(
                        id: loaded.record.id, label: loaded.record.label, source: .clipboard, autoUpdate: false,
                        updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil,
                        order: 0, lastUpdatedAt: nil
                    ),
                    rawYAML: loaded.yaml,
                    editorTitle: "Edit Nodes Source"
                ) { _, text, files, _ in
                    guard let text else { return }
                    guard files.isEmpty else { throw CocoaError(.featureUnsupported) }
                    let next = try await profiles.saveConfigurationNodeSource(loaded.version, yaml: text)
                    HakoMacLibraryBridge.apply(next)
                }
            } windowGuard: { controller in
                HakoMacWindowCloseGuard(controller: controller)
            }
            .navigationTitle(Text(verbatim: loaded.record.label))
            .navigationSubtitle(Text(hako: .copy("Edit Nodes Source")))
            .frame(minWidth: 640, minHeight: 480)
        } else if let errorMessage {
            HakoEmptyState(title: "Configuration Unavailable", message: errorMessage, symbol: .curlybraces)
                .frame(minWidth: 480, minHeight: 320)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 480, minHeight: 320)
                .task(id: sourceID) { await load() }
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let id = sourceID
            loaded = try await Task.detached {
                guard let current = try store.snapshot().sources.first(where: { $0.id == id }) else {
                    throw ConfigurationLibraryError.missingDependency(id)
                }
                let payload = try store.payload(.init(current))
                guard case .object(let entries) = try OrderedJSON.parse(payload.documentJSON) else {
                    throw ConfigurationLibraryError.unreadable
                }
                let nodes = OrderedJSON.object(entries.filter { ["proxies", "proxy-providers"].contains($0.key) })
                return (current, try ConfigTransforms.jsonToYAML(nodes.serialized()), ConfigurationSourceVersion(current))
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

 
 
 
struct HakoMacCollectionSourceEditorWindow: View {
    let reference: HakoMacCollectionReference
    @ObservedObject var profiles: ProfilesViewModel
    @State private var loaded: (entry: ConfigurationCollectionEntry, yaml: String)?
    @State private var errorMessage: String?

    var body: some View {
        if let loaded {
            HakoWindowDepartureHost {
                ProfileEditView(
                    profile: Profile(
                        id: loaded.entry.source.id, label: loaded.entry.collection.name, source: .clipboard, autoUpdate: false,
                        updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil,
                        order: 0, lastUpdatedAt: nil
                    ),
                    rawYAML: loaded.yaml,
                    editorTitle: "Edit Source"
                ) { _, text, files, _ in
                    guard let text else { return }
                    guard files.isEmpty else { throw CocoaError(.featureUnsupported) }
                    let json = try ConfigTransforms.yamlToJSON(text)
                    let next = try await profiles.saveConfigurationCollection(loaded.entry, definitionJSON: json)
                    HakoMacLibraryBridge.apply(next)
                }
            } windowGuard: { controller in
                HakoMacWindowCloseGuard(controller: controller)
            }
            .navigationTitle(Text(verbatim: loaded.entry.collection.name))
            .navigationSubtitle(Text(hako: .copy("Edit Source")))
            .frame(minWidth: 640, minHeight: 480)
        } else if let errorMessage {
            HakoEmptyState(title: "Configuration Unavailable", message: errorMessage, symbol: .curlybraces)
                .frame(minWidth: 480, minHeight: 320)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 480, minHeight: 320)
                .task(id: reference) { await load() }
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let reference = reference
            loaded = try await Task.detached {
                let snapshot = try store.snapshot()
                guard let entry = try store.collectionCatalog(snapshot).first(where: { reference.matches($0) }) else {
                    throw ConfigurationLibraryError.missingDependency(reference.key)
                }
                return (entry, try ConfigTransforms.jsonToYAML(entry.collection.definition.serialized()))
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
