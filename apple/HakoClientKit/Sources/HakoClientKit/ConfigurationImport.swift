import Foundation

public extension ConfigurationCreationDraft {
     
     
    mutating func useOriginal(_ payload: ConfigurationSourcePayload) {
        self = .init()
        var source = payload
        source.record.registersSuppliedRules = true
        newSources = [source]
        originalSourceID = source.record.id
        selectedSourceIDs = [source.record.id]
        label = source.record.label
        dnsMode = .source
        step = .finish
    }
}

extension ConfigurationLibraryStore {
    func prepareOriginal(_ draft: ConfigurationCreationDraft, profileID: String,
                         starting: ConfigurationLibrarySnapshot,
                         resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationCreation {
        guard let sourceID = draft.originalSourceID, draft.selectedSourceIDs == [sourceID],
              !starting.recipes.contains(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        var source: ConfigurationSourcePayload
        if let staged = draft.newSources.first(where: { $0.record.id == sourceID }) { source = staged }
        else if let stored = starting.sources.first(where: { $0.id == sourceID }) { source = try payload(.init(stored)) }
        else { throw ConfigurationLibraryError.missingDependency(sourceID) }
        let input = try resolveInput(source)
        guard input.id == sourceID, case .object = input.document else {
            throw ConfigurationCompositionError.invalidDocument(sourceID)
        }
        source.record.registersSuppliedRules = true
        var candidate = starting
        if let index = candidate.sources.firstIndex(where: { $0.id == sourceID }) {
             
             
             
             
             
             
             
            candidate.sources[index].registersSuppliedRules = true
            source.record = candidate.sources[index]
        } else {
            candidate.sources.append(source.record)
        }
        let reference = ConfigurationSourceVersion(source.record)
        let ruleID = "rules-" + sourceID
         
         
        if input.document.topLevelValue("rules") != nil || input.document.topLevelValue("rule-providers") != nil {
            candidate.rules.removeAll { $0.id == ruleID }
            candidate.rules.append(.init(id: ruleID, label: source.record.label, kind: .supplied, sourceID: sourceID))
        }
        let proposed = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        var recipe = ConfigurationRecipe(id: profileID, label: proposed.isEmpty ? source.record.label : proposed,
            sources: [reference], ruleSchemeID: ruleID, ruleSource: reference, dnsMode: .source)
        recipe.preservesOriginal = true
        candidate.recipes.append(recipe)
        return .init(recipe: recipe, composition: .init(document: input.document, sourceIDs: [sourceID]),
            candidate: candidate, payloads: [source])
    }
}

public extension ConfigurationLibraryStore {
     
     
     
     
     
     
     
     
     
    func registerSuppliedRules(sourceID: String, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard let index = candidate.sources.firstIndex(where: { $0.id == sourceID }) else {
            throw ConfigurationLibraryError.missingDependency(sourceID)
        }
        guard candidate.sources[index].hasRules else { throw ConfigurationLibraryError.missingRules }
        candidate.sources[index].registersSuppliedRules = true
        let ruleID = "rules-" + sourceID
        if !candidate.rules.contains(where: { $0.id == ruleID }) {
            candidate.rules.append(.init(id: ruleID, label: candidate.sources[index].label, kind: .supplied, sourceID: sourceID))
        }
        return try commit(candidate, payloads: [], expectedGeneration: expectedGeneration)
    }

     
     
    func prepareWholeSourceEditing(_ profileID: String, replacement: ConfigurationSourcePayload,
        expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationCreation {
        var current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let previous = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
         
         
        guard !current.sources.contains(where: { $0.id == replacement.record.id }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        current.recipes.removeAll { $0.id == profileID }
        var draft = ConfigurationCreationDraft(); draft.useOriginal(replacement)
        draft.label = previous.label
        let prepared = try prepareOriginal(draft, profileID: profileID, starting: current, resolveInput: resolveInput)
        var recipe = prepared.recipe; recipe.followsUpdates = false
        var candidate = prepared.candidate
        candidate.recipes.removeAll { $0.id == profileID }; candidate.recipes.append(recipe)
        return .init(recipe: recipe, composition: prepared.composition, candidate: candidate, payloads: prepared.payloads)
    }
}

public extension ConfigurationLibraryStore {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func prepareOriginalUse(_ profileID: String, uses: Bool, expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationCreation {
        var current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let existing = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        guard (existing.preservesOriginal == true) != uses else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        guard existing.sources.count == 1, let reference = existing.sources.first else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        guard !current.sources.contains(where: { $0.id == reference.id && $0.isRetainedSnapshot == true }) else {
            throw ConfigurationLibraryError.retainedSnapshot
        }
        guard uses else {
             
             
            var draft = ConfigurationCreationDraft()
            draft.step = .finish
            draft.selectedSourceIDs = [reference.id]
            let supplied = "rules-" + reference.id
             
             
            let remembered = existing.composedRuleSchemeID.flatMap { id in
                current.rules.first { $0.id == id && $0.isRetainedSnapshot != true } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
            }
            draft.selectedRuleID = remembered?.id
                ?? (current.rules.contains { $0.id == supplied } ? current.effectiveRuleScheme(supplied)?.id : nil)
                ?? ConfigurationBuiltins.basicRuleID
            draft.label = existing.label
            draft.dnsMode = existing.dnsMode ?? .source
            draft.customDNSJSON = existing.customDNSJSON
            draft.nodeNameservers = existing.nodeNameservers
            return try prepareEditing(draft, profileID: profileID, expectedGeneration: expectedGeneration,
                                      resolveInput: resolveInput)
        }
         
         
        current.recipes.removeAll { $0.id == profileID }
        var draft = ConfigurationCreationDraft()
        draft.useOriginal(try payload(reference))
        draft.label = existing.label
        let prepared = try prepareOriginal(draft, profileID: profileID, starting: current, resolveInput: resolveInput)
        var recipe = prepared.recipe
        recipe.followsUpdates = existing.followsUpdates
        recipe.composedRuleSchemeID = existing.ruleSchemeID
         
         
         
         
        recipe.settingsJSON = existing.settingsJSON
        recipe.originalSettingsJSON = nil
        recipe.settingsSource = existing.settingsSource
        recipe.settingsRuleDependencies = existing.settingsRuleDependencies
         
         
         
         
         
         
         
         
        recipe.dnsMode = existing.dnsMode
        recipe.customDNSJSON = existing.customDNSJSON
        recipe.nodeNameservers = existing.nodeNameservers
        var candidate = prepared.candidate
        candidate.recipes.removeAll { $0.id == profileID }; candidate.recipes.append(recipe)
        return .init(recipe: recipe, composition: prepared.composition, candidate: candidate, payloads: prepared.payloads)
    }
}
