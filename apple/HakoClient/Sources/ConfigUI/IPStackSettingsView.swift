import HakoClientUI
import SwiftUI

 
 
 
struct IPStackSettingsView: View {
    let defaults: UserDefaults
    let connectionIsTransitioning: Bool
    var applicationInProgress: Bool = false
    var saveNotice: String = ""
    let applySettings: (IPStackSettings) async throws -> Void

    @State private var draft = IPStackSettings()
    @State private var hasLoaded = false
    @State private var isApplying = false
    @State private var error = ""

    var body: some View {
        HakoMacSettingsFormContainer {
            Section {
                ForEach(IPQueryMode.allCases) { mode in
                    choice(mode.title, selected: draft.queryMode == mode,
                           identifier: "ipStack.query.\(mode.rawValue)") {
                        var next = draft
                        next.queryMode = mode
                        apply(next)
                    }
                }
            } header: {
                Text("IP Query Mode")
            } footer: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("IPv4 Only: Use IPv4 for requests, do not send AAAA DNS queries, and reject IPv6 connections.\nIPv4 & IPv6: Query A and AAAA concurrently and prefer the faster response.\nPrefer IPv4: Query A and AAAA concurrently. Use IPv4 results when available, otherwise use IPv6.\nPrefer IPv6: Query A and AAAA concurrently. Use IPv6 results when available, otherwise use IPv4.")
                    Text("Prefer IPv4 and Prefer IPv6 wait for both A and AAAA queries to finish, which may add latency. Changing this setting restarts the VPN.")
                }
            }

            Section {
                ForEach(TUNIPv6Mode.allCases) { mode in
                    choice(mode.title, selected: draft.tunIPv6Mode == mode,
                           identifier: "ipStack.tun.\(mode.rawValue)") {
                        var next = draft
                        next.tunIPv6Mode = mode
                        apply(next)
                    }
                }
            } header: {
                Text("TUN IPv6 Configuration")
            } footer: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Control IPv6 traffic in the tunnel:\nOff: Do not handle IPv6 traffic in the tunnel.\nAutomatic: Decide based on the current network.\nOn: Always handle IPv6 traffic in the tunnel. This may cause problems on networks without IPv6 support.")
                    Text("Changing this setting restarts the VPN.")
                }
            }

            if isApplying || applicationInProgress {
                Section {
                    ProgressView("Applying IP Stack settings…")
                        .accessibilityIdentifier("ipStack.applying")
                    if !saveNotice.isEmpty { Text(saveNotice).foregroundStyle(.secondary) }
                }
            }
            if !error.isEmpty {
                Section {
                    HakoStatusMessage(text: .copy(error), kind: .error)
                        .accessibilityIdentifier("ipStack.error")
                }
            }
        }
        .hakoPageTitle(.verbatim("IP Stack"), watchAs: "IP Stack")
        .task {
            guard !hasLoaded else { return }
            do {
                draft = try IPStackSettings.load(from: defaults)
                hasLoaded = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func choice(
        _ title: String, selected: Bool, identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(LocalizedStringKey(title)).foregroundStyle(Color.primary)
                Spacer(minLength: 16)
                if selected && hasLoaded {
                    Image(systemName: HakoSymbol.checkmark.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasLoaded || isApplying || applicationInProgress || connectionIsTransitioning)
        .accessibilityAddTraits(selected && hasLoaded ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func apply(_ next: IPStackSettings) {
        guard hasLoaded, !isApplying, !applicationInProgress, !connectionIsTransitioning, next != draft else { return }
        isApplying = true
        error = ""
        Task { @MainActor in
            defer { isApplying = false }
            do {
                try await applySettings(next)
                draft = try IPStackSettings.load(from: defaults)
            } catch {
                self.error = error.localizedDescription
                if let saved = try? IPStackSettings.load(from: defaults) { draft = saved }
            }
        }
    }
}
