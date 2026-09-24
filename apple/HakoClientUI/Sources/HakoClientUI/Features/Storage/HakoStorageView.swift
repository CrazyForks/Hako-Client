import Foundation
import SwiftUI

 
 
 
public enum HakoStorageArea: String, CaseIterable, Codable, Identifiable, Sendable {
    case configurations
    case library
    case geodata
    case providerCaches
    case compiledGeodata
    case logs
    case temporary
     
     
     
     
    case other

    public var id: Self { self }

    public var title: String {
        switch self {
        case .configurations: "Configurations"
        case .library: "Node & Rule Library"
        case .geodata: "Geo Data"
        case .providerCaches: "Rule Set & Node Set Cache"
        case .compiledGeodata: "Compiled Geo Data"
        case .logs: "Logs"
        case .temporary: "Temporary Files"
        case .other: "Other"
        }
    }

     
     
     
     
     
    public var unreclaimableReason: String? {
        switch self {
        case .library: "The library removes its own unused data whenever it is written."
        case .providerCaches: "The core clears this cache each time it starts."
        case .other: "The core's own working files and the downloaded dashboard."
        case .configurations, .geodata, .compiledGeodata, .logs, .temporary: nil
        }
    }
}

public struct HakoStorageRow: Codable, Equatable, Identifiable, Sendable {
    public let area: HakoStorageArea
     
    public let bytes: Int64
     
    public let reclaimable: Int64

    public var id: HakoStorageArea { area }

    public init(area: HakoStorageArea, bytes: Int64, reclaimable: Int64) {
        self.area = area
        self.bytes = bytes
        self.reclaimable = reclaimable
    }
}

public struct HakoStorageSnapshot: Codable, Equatable, Sendable {
    public var rows: [HakoStorageRow]
     
     
    public var tunnelIsRunning: Bool

    public init(rows: [HakoStorageRow], tunnelIsRunning: Bool) {
        self.rows = rows
        self.tunnelIsRunning = tunnelIsRunning
    }

    public var totalBytes: Int64 { rows.reduce(0) { $0 + $1.bytes } }
    public var reclaimableBytes: Int64 { rows.reduce(0) { $0 + $1.reclaimable } }
}

 
 
 
public struct HakoStorageCapabilities: Sendable {
    public typealias Measure = @Sendable () async -> HakoStorageSnapshot
     
     
    public typealias Reclaim = @Sendable (Set<HakoStorageArea>) async throws -> Int64
    public typealias Reset = @Sendable () async throws -> Void

    public let measure: Measure
    public let reclaim: Reclaim
    public let reset: Reset?

    public init(measure: @escaping Measure, reclaim: @escaping Reclaim, reset: Reset? = nil) {
        self.measure = measure
        self.reclaim = reclaim
        self.reset = reset
    }
}

 
 
 
 
 
 
public struct HakoStorageView: View {
    private let capabilities: HakoStorageCapabilities
     
     
     
    private let liveTunnelIsRunning: Bool?

    @State private var snapshot: HakoStorageSnapshot?
    @State private var isWorking = false
    @State private var freed: Int64?
     
    @State private var freedByArea: [HakoStorageArea: Int64] = [:]
    @State private var didReset = false
    @State private var failure: String?
    @State private var confirmingReset = false

    public init(capabilities: HakoStorageCapabilities, tunnelIsRunning: Bool? = nil) {
        self.capabilities = capabilities
        self.liveTunnelIsRunning = tunnelIsRunning
    }

    private var tunnelIsRunning: Bool {
        liveTunnelIsRunning ?? snapshot?.tunnelIsRunning ?? false
    }

    public var body: some View {
         
         
         
         
        HakoMacSettingsContainer {
            HakoSection("On This Device") {
                HStack {
                    Text(hako: .copy("Total"))
                    Spacer()
                    Text(verbatim: Self.formatted(snapshot?.totalBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("storage.total")
                ForEach(snapshot?.rows ?? []) { row in
                    storageRow(row)
                }
            }

            HakoSection("Clean Up") {
                 
                 
                 
                if HakoPlatformLayout.pageUsesSystemSettingsIdiom {
                    HStack(spacing: HakoTheme.Spacing.compact) {
                        Button {
                            Task { await reclaim(Set(HakoStorageArea.allCases)) }
                        } label: {
                            Text(hako: .copy("Clean Up Unused Data"))
                        }
                        .hakoMacFormActionChrome()
                        .disabled(isWorking || (snapshot?.reclaimableBytes ?? 0) == 0)
                        .accessibilityIdentifier("storage.reclaim")
                        Text(hako: reclaimableLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    Button {
                        Task { await reclaim(Set(HakoStorageArea.allCases)) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hako: .copy("Clean Up Unused Data"))
                            Text(hako: reclaimableLine)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isWorking || (snapshot?.reclaimableBytes ?? 0) == 0)
                    .accessibilityIdentifier("storage.reclaim")
                }
                if let freed {
                    Text(hako: .format("Freed %@", [Self.formatted(freed)]))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("storage.reclaim.echo")
                }
                if let failure {
                    Text(verbatim: failure)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("storage.failure")
                }
            } footer: {
                Text(hako: .copy(
                    "Removes configurations no longer listed, superseded revisions and downloads, log files from earlier days, and temporary files. Data any configuration still uses is never touched."
                ))
            }

            if capabilities.reset != nil {
                 
                 
                 
                 
                 
                 
                 
                HakoSection("Reset Local Data") {
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        HakoMacFormDestructiveLabel(.copy("Reset Local Data…"))
                    }
                    .hakoMacFormDestructiveActionChrome()
                    .disabled(isWorking || tunnelIsRunning)
                    .accessibilityIdentifier("storage.reset")
                    if didReset {
                        Text(hako: .copy("Local data was reset."))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("storage.reset.echo")
                    }
                } footer: {
                    Text(hako: .copy(
                        tunnelIsRunning
                            ? "Disconnect first to reset local data."
                            : "Deletes every configuration, setting, and stored credential on this device. The VPN configuration in Settings and your iCloud backups stay."
                    ))
                }
            }
        }
        .hakoGroupedList()
        .task { await refresh() }
        .onChange(of: liveTunnelIsRunning) { _ in Task { await refresh() } }
        .confirmationDialog(
            Text(hako: .copy("Reset Local Data?")),
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await reset() }
            } label: {
                Text(hako: .copy("Reset Local Data"))
            }
            Button(role: .cancel) {} label: {
                Text(hako: .copy("Cancel"))
            }
        } message: {
            Text(hako: .copy(
                "Deletes every configuration, setting, and stored credential on this device. The VPN configuration in Settings and your iCloud backups stay. Clash starts over as on first launch."
            ))
        }
    }

     
     
     
     
     
     
    @ViewBuilder
    private func storageRow(_ row: HakoStorageRow) -> some View {
        let area = row.area.rawValue
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(hako: .copy(row.area.title))
                Spacer()
                Text(verbatim: Self.formatted(row.bytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("storage.row.\(area)")
            if row.reclaimable > 0 {
                HStack(spacing: HakoTheme.Spacing.compact) {
                    Text(hako: .format("%@ can be freed", [Self.formatted(row.reclaimable)]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await reclaim([row.area]) }
                    } label: {
                        Text(hako: .copy("Clean Up"))
                            .font(.footnote)
                    }
                     
                     
                     
                     
                     
                    .hakoMacFormActionChrome()
                    .buttonStyle(.borderless)
                    .disabled(isWorking)
                    .accessibilityIdentifier("storage.row.\(area).reclaim")
                }
            } else if row.bytes > 0, let reason = unreclaimableReason(for: row) {
                Text(hako: .copy(reason))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let freed = freedByArea[row.area] {
                Text(hako: .format("Freed %@", [Self.formatted(freed)]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("storage.row.\(area).echo")
            }
        }
    }

     
     
    private func unreclaimableReason(for row: HakoStorageRow) -> String? {
        if row.area == .compiledGeodata, tunnelIsRunning {
            return "Disconnect first to clean up compiled geo data."
        }
        return row.area.unreclaimableReason
    }

    private var reclaimableLine: HakoDisplayText {
        let reclaimable = snapshot?.reclaimableBytes ?? 0
        return reclaimable > 0
            ? .format("%@ can be freed", [Self.formatted(reclaimable)])
            : .copy("Nothing to clean up")
    }

    private func refresh() async {
        snapshot = await capabilities.measure()
    }

    private func reclaim(_ areas: Set<HakoStorageArea>) async {
        isWorking = true
        defer { isWorking = false }
        failure = nil
        do {
            let went = try await capabilities.reclaim(areas)
            if areas.count == 1, let area = areas.first {
                freedByArea[area] = went
            } else {
                freed = went
                freedByArea = [:]
            }
        } catch {
            failure = error.localizedDescription
        }
        await refresh()
    }

    private func reset() async {
        guard let reset = capabilities.reset else { return }
        isWorking = true
        defer { isWorking = false }
        failure = nil
        do {
            try await reset()
            didReset = true
        } catch {
            failure = error.localizedDescription
        }
        await refresh()
    }

     
     
    static func formatted(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
