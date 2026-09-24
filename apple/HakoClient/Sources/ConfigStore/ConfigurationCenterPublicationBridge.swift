import Foundation
import Darwin
import HakoClientKit
import HakoClientUI

 
 
enum ConfigurationCenterPublicationBridge {
    static func stage(_ publication: ConfigurationPublicationPayload,
                            library: ConfigurationLibraryStore, workingDir: URL,
                            writeSource: ((String, Profile, URL) throws -> Void)? = nil) throws -> Profile {
        let store = ProfileStore(fileURL:workingDir.appendingPathComponent("store/profiles.json"))
        if case .unreadable = store.state() { throw ProfileStore.StoreError.unreadableStore }
        var profile = try JSONDecoder().decode(Profile.self,from:publication.profileMetadata)
        guard profile.id == publication.reference.profileID else { throw ConfigurationLibraryError.invalidIdentifier }
        if let existing = store.load().first(where: { $0.id == profile.id }) {
             
             
            return existing
        }
        let snapshot = try library.snapshot()
        guard let recipe = snapshot.recipes.first(where: { $0.id == profile.id }) else {
            throw ConfigurationLibraryError.missingDependency(profile.id)
        }
        var files: [ExternalResourceImportFile] = []
        for reference in Set(recipe.dependencies) {
            files += ConfigurationCenterSourceBridge.boundFiles(try library.payload(reference))
        }
        let prepared = try ProfileExternalResourceImporter.prepare(yaml:publication.yaml,profileID:profile.id,
            source:.localFile,files:files,requiringAllFiles:false)
        profile.externalResources = prepared.references.isEmpty ? nil : prepared.references
        try ProfileExternalResourceStore.replace(prepared.publicResources,profileID:profile.id,coreHomeDir:workingDir)
        if let writeSource { try writeSource(prepared.yaml,profile,workingDir) }
        else {
            let source = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
            try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data(prepared.yaml.utf8).write(to:source,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
        return profile
    }

    static func materialize(_ publication: ConfigurationPublicationPayload,
                            library: ConfigurationLibraryStore, workingDir: URL,
                            writeSource: ((String, Profile, URL) throws -> Void)? = nil) throws -> Profile {
        let profile = try stage(publication,library:library,workingDir:workingDir,writeSource:writeSource)
        let store = ProfileStore(fileURL:workingDir.appendingPathComponent("store/profiles.json"))
        if let existing = store.load().first(where: { $0.id == profile.id }) { return existing }
        try store.upsert(profile)
        return profile
    }
     
     
    static func reconcileDeletedProfiles(library: ConfigurationLibraryStore, profileStore: ProfileStore) throws {
        guard case .unreadable = profileStore.state() else {
            var snapshot = try library.snapshot()
            let ids = Set(profileStore.load().map(\.id))
            let pending = Set((snapshot.pendingPublications ?? []).map(\.profileID))
            let count = snapshot.recipes.count
            snapshot.recipes.removeAll { !ids.contains($0.id) && !pending.contains($0.id) }
             
             
            let orphaned = snapshot.sources.compactMap { registrationOwner(of: $0.id) }
                .filter { !ids.contains($0) && !pending.contains($0) }
            var dropped = false
            for owner in Set(orphaned) { dropped = dropOwnedRegistrations(of: owner, from: &snapshot) || dropped }
            if snapshot.recipes.count != count || dropped {
                _ = try library.commit(snapshot, payloads: [], expectedGeneration: snapshot.generation)
            }
            return
        }
        throw ProfileStore.StoreError.unreadableStore
    }

     
     
     
    static func ownedRegistrations(of profileID: String) -> (sources: [String], rule: String) {
        let sourceID = "legacy-" + profileID
        return ([sourceID, ConfigurationLegacyRegistration.customNodeSourceID(for: profileID)], "rules-" + sourceID)
    }

     
    static func registrationOwner(of sourceID: String) -> String? {
        for prefix in ["legacy-nodes-", "legacy-"] where sourceID.hasPrefix(prefix) {
            let owner = String(sourceID.dropFirst(prefix.count))
            return owner.isEmpty ? nil : owner
        }
        return nil
    }

     
     
     
     
     
     
    @discardableResult
    static func dropOwnedRegistrations(of profileID: String, from snapshot: inout ConfigurationLibrarySnapshot) -> Bool {
        let owned = ownedRegistrations(of: profileID)
        let usedSources = Set(snapshot.recipes.flatMap { $0.sources.map(\.id) + [$0.ruleSource.id] })
        let usedRules = Set(snapshot.recipes.map(\.ruleSchemeID))
        let before = snapshot.sources.count + snapshot.rules.count
        snapshot.sources.removeAll { owned.sources.contains($0.id) && !usedSources.contains($0.id) }
        if !usedRules.contains(owned.rule) { snapshot.rules.removeAll { $0.id == owned.rule } }
        return snapshot.sources.count + snapshot.rules.count != before
    }

    static func removeProfile(_ profile: Profile, library: ConfigurationLibraryStore, profileStore: ProfileStore) throws {
        var snapshot = try library.snapshot()
        let hadRecipe = snapshot.recipes.contains { $0.id == profile.id }
        snapshot.recipes.removeAll { $0.id == profile.id }
        let droppedRegistrations = dropOwnedRegistrations(of: profile.id, from: &snapshot)
        guard hadRecipe || droppedRegistrations else {
            try profileStore.remove(id: profile.id); return
        }
        guard snapshot.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        try profileStore.remove(id: profile.id)
        do { _ = try library.commit(snapshot, payloads: [], expectedGeneration: snapshot.generation) }
        catch {
             
             
            try profileStore.upsert(profile)
            throw error
        }
    }

    struct Replacement {
        let previous: Profile
        let profile: Profile
        let previousYAML: String
        let yaml: String
        let resources: [String: Data]
    }

     
     
     
    private struct RecoveryEntry: Codable {
        let previous: Profile
        let next: Profile
        let previousYAML: String
        let nextYAML: String
        let resourceNames: [String]
    }
    private struct RecoveryRecord: Codable {
        let schemaVersion: Int
        let id: String
        let entries: [RecoveryEntry]
    }
    private static func recoveryDirectory(_ working: URL) -> URL {
        working.appendingPathComponent("configuration-library/materialization-transaction")
    }
    static func hasReplacementRecovery(workingDir: URL) -> Bool {
        FileManager.default.fileExists(atPath: recoveryDirectory(workingDir).path)
    }
    private static func withReplacementLock<T>(workingDir: URL, _ operation: () throws -> T) throws -> T {
#if canImport(UIKit)
        let finishAccess = ConfigStoreSuspensionShield.beginLibraryAccess()
        defer { finishAccess() }
#endif
        let directory = workingDir.appendingPathComponent("configuration-library")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("materialization.lock").path,
                      O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ConfigurationLibraryError.unreadable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ConfigurationLibraryError.busy }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
    static func recoverReplacements(library: ConfigurationLibraryStore, workingDir: URL) throws {
        guard hasReplacementRecovery(workingDir: workingDir) else { return }
        try withReplacementLock(workingDir: workingDir) {
            try recoverReplacementsLocked(library: library, workingDir: workingDir)
        }
    }
    private static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\0")
    }
    private static func recoverReplacementsLocked(library: ConfigurationLibraryStore, workingDir: URL) throws {
        let fm = FileManager.default
        let folder = recoveryDirectory(workingDir)
        guard fm.fileExists(atPath: folder.path) else { return }
        let ready = folder.appendingPathComponent("ready.json")
        guard fm.fileExists(atPath: ready.path) else {
             
            try fm.removeItem(at: folder); return
        }
        let record = try JSONDecoder().decode(RecoveryRecord.self, from: Data(contentsOf: ready))
        guard record.schemaVersion == 1, UUID(uuidString: record.id) != nil,
              Set(record.entries.map { $0.previous.id }).count == record.entries.count,
              record.entries.allSatisfy({ safeComponent($0.previous.id) && $0.previous.id == $0.next.id
                  && Set($0.resourceNames).count == $0.resourceNames.count
                  && $0.resourceNames.allSatisfy(safeComponent) }) else { throw ConfigurationLibraryError.unreadable }
        if try library.snapshot().lastMaterializationID != record.id {
            let store = ProfileStore(fileURL: workingDir.appendingPathComponent("store/profiles.json"))
            if case .unreadable = store.state() { throw ProfileStore.StoreError.unreadableStore }
            let current = store.load()
             
            for entry in record.entries {
                guard let profile = current.first(where: { $0.id == entry.previous.id }),
                      profile == entry.previous || profile == entry.next else { throw ConfigurationLibraryError.staleGeneration }
                let raw = try String(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: workingDir,
                    profileID: profile.id), encoding: .utf8)
                guard raw == entry.previousYAML || raw == entry.nextYAML else { throw ConfigurationLibraryError.staleGeneration }
            }
            for entry in record.entries {
                let resources = try Dictionary(uniqueKeysWithValues: entry.resourceNames.map { name in
                    (name, try Data(contentsOf: folder.appendingPathComponent(entry.previous.id).appendingPathComponent(name)))
                })
                try ProfileExternalResourceStore.replace(resources, profileID: entry.previous.id, coreHomeDir: workingDir)
                try Data(entry.previousYAML.utf8).write(to: ProfileSourceStore.runnableURL(workingDirectory: workingDir,
                    profileID: entry.previous.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            try store.save(current.map { current in
                record.entries.first(where: { $0.previous.id == current.id })?.previous ?? current
            })
        }
         
        try fm.removeItem(at: folder)
    }

    @MainActor
    static func replaceOffMain(_ replacements: [Replacement], candidate: ConfigurationLibrarySnapshot,
                               payloads: [ConfigurationSourcePayload], library: ConfigurationLibraryStore,
                               workingDir: URL, expectedGeneration: UInt64,
                               beforeSourceWrite: (@Sendable (Int) throws -> Void)? = nil) async throws {
         
         
        try await Task.detached(priority: .userInitiated) {
            try HakoPerf.measure("configuration.save.commit") {
                try replace(replacements, candidate: candidate, payloads: payloads, library: library,
                    workingDir: workingDir, expectedGeneration: expectedGeneration, beforeSourceWrite: beforeSourceWrite)
            }
        }.value
    }

    static func replace(_ replacements: [Replacement], candidate: ConfigurationLibrarySnapshot,
                        payloads: [ConfigurationSourcePayload], library: ConfigurationLibraryStore,
                        workingDir: URL, expectedGeneration: UInt64,
                        beforeSourceWrite: ((Int) throws -> Void)? = nil) throws {
        try withReplacementLock(workingDir: workingDir) {
            try recoverReplacementsLocked(library: library, workingDir: workingDir)
            if replacements.isEmpty {
                _ = try library.commit(candidate, payloads: payloads, expectedGeneration: expectedGeneration)
                return
            }
            let store = ProfileStore(fileURL: workingDir.appendingPathComponent("store/profiles.json"))
            if case .unreadable = store.state() { throw ProfileStore.StoreError.unreadableStore }
            let originals = store.load()
            guard try library.snapshot().generation == expectedGeneration,
                  Set(replacements.map { $0.profile.id }).count == replacements.count else {
                throw ConfigurationLibraryError.staleGeneration
            }
            let fm = FileManager.default
            let folder = recoveryDirectory(workingDir)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var entries: [RecoveryEntry] = []
            for replacement in replacements {
                guard safeComponent(replacement.profile.id), replacement.previous.id == replacement.profile.id,
                      originals.first(where: { $0.id == replacement.previous.id }) == replacement.previous,
                      candidate.recipes.contains(where: { $0.id == replacement.profile.id }),
                      try Data(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: workingDir,
                          profileID: replacement.profile.id)) == Data(replacement.previousYAML.utf8) else {
                    throw ConfigurationLibraryError.staleGeneration
                }
                let resources = workingDir.appendingPathComponent("store/\(replacement.profile.id)/resources")
                let backup = folder.appendingPathComponent(replacement.profile.id)
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                var names: [String] = []
                if fm.fileExists(atPath: resources.path) {
                    for file in try fm.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil) {
                        guard safeComponent(file.lastPathComponent) else { throw ConfigurationLibraryError.unreadable }
                        try fm.copyItem(at: file, to: backup.appendingPathComponent(file.lastPathComponent))
                        names.append(file.lastPathComponent)
                    }
                }
                entries.append(.init(previous: replacement.previous, next: replacement.profile,
                    previousYAML: replacement.previousYAML, nextYAML: replacement.yaml, resourceNames: names))
            }
            let record = RecoveryRecord(schemaVersion: 1, id: UUID().uuidString, entries: entries)
            try JSONEncoder().encode(record).write(to: folder.appendingPathComponent("ready.json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            do {
                for (index, replacement) in replacements.enumerated() {
                    try beforeSourceWrite?(index)
                    try ProfileExternalResourceStore.replace(replacement.resources,
                        profileID: replacement.profile.id, coreHomeDir: workingDir)
                    try Data(replacement.yaml.utf8).write(to: ProfileSourceStore.runnableURL(
                        workingDirectory: workingDir, profileID: replacement.profile.id),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                try store.save(originals.map { original in
                    replacements.first(where: { $0.profile.id == original.id })?.profile ?? original
                })
                var committed = candidate
                committed.lastMaterializationID = record.id
                _ = try library.commit(committed, payloads: payloads, expectedGeneration: expectedGeneration)
            } catch {
                let originalError = error
                do { try recoverReplacementsLocked(library: library, workingDir: workingDir) }
                catch { throw BackupArchive.BackupError.rollbackFailed }
                throw originalError
            }
             
             
            try? fm.removeItem(at: folder)
        }
    }
}
