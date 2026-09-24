import SwiftUI

 
 
struct HakoTVIPStackScreen: View {
    @ObservedObject var tunnel: HakoTVTunnelController
    @State private var saved: IPStackSettings?
    @State private var error = ""
    @State private var explainedTitle = String(localized: "IP Query Mode")
    @State private var explained = String(localized: "Choose the IP query mode and how the tunnel handles IPv6. Changes restart a connected VPN.")

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                Section("IP Query Mode") {
                    ForEach(IPQueryMode.allCases) { mode in
                        choice(mode.title, selected: saved?.queryMode == mode,
                               id: "tvos.ipStack.query.\(mode.rawValue)") {
                            guard var next = saved else { return }
                            next.queryMode = mode
                            apply(next)
                        }
                        .onHakoTVFocus {
                            explainedTitle = mode.title.localizedForTelevision
                            explained = Self.explanation(mode)
                        }
                    }
                }
                Section("TUN IPv6 Configuration") {
                    ForEach(TUNIPv6Mode.allCases) { mode in
                        choice(mode.title, selected: saved?.tunIPv6Mode == mode,
                               id: "tvos.ipStack.tun.\(mode.rawValue)") {
                            guard var next = saved else { return }
                            next.tunIPv6Mode = mode
                            apply(next)
                        }
                        .onHakoTVFocus {
                            explainedTitle = mode.title.localizedForTelevision
                            explained = Self.explanation(mode)
                        }
                    }
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                Text(explainedTitle)
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Text(explained).font(.title3).foregroundStyle(.secondary)
                if tunnel.state.isConnected {
                    Text("Changing this setting restarts the VPN.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                if tunnel.isApplyingIPStack {
                    ProgressView("Applying IP Stack settings…")
                        .accessibilityIdentifier("tvos.ipStack.applying")
                }
                if !error.isEmpty {
                    Text(error).foregroundStyle(.orange)
                        .accessibilityIdentifier("tvos.ipStack.error")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)
            .animation(.easeOut(duration: 0.18), value: explained)
        }
        .task { reload() }
        .accessibilityIdentifier("tvos.ipStack.screen")
    }

    private func choice(_ title: String, selected: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title.localizedForTelevision)
                Spacer()
                if selected { Image(systemName: HakoSymbol.checkmark.rawValue) }
            }
        }
        .disabled(saved == nil || tunnel.isApplyingIPStack || tunnel.state.stage == .connecting || tunnel.state.stage == .disconnecting)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func reload() {
        do { saved = try IPStackSettings.load(from: tunnel.ipStackDefaults) }
        catch { self.error = error.localizedDescription }
    }

    private func apply(_ next: IPStackSettings) {
        guard next != saved else { return }
        error = ""
        Task { @MainActor in
            do { try await tunnel.applyIPStack(next) }
            catch { self.error = error.localizedDescription }
            reload()
        }
    }

    static func explanation(_ mode: IPQueryMode) -> String {
        switch mode {
        case .ipv4Only: String(localized: "Query only IPv4 addresses and reject IPv6 connections.")
        case .dualStack: String(localized: "Query IPv4 and IPv6 together and use the first usable response.")
        case .preferIPv4: String(localized: "Wait for both query results. Prefer IPv4 when available; otherwise use IPv6. This can add latency.")
        case .preferIPv6: String(localized: "Wait for both query results. Prefer IPv6 when available; otherwise use IPv4. This can add latency.")
        case .ipv6Only: String(localized: "Query only IPv6 addresses and reject IPv4 connections. Use with caution: some destinations may be unreachable.")
        }
    }

    static func explanation(_ mode: TUNIPv6Mode) -> String {
        switch mode {
        case .disabled: String(localized: "Do not handle IPv6 traffic in the tunnel.")
        case .automatic: String(localized: "Handle IPv6 when the current network supports it. Network changes update the tunnel without restarting it.")
        case .enabled: String(localized: "Always handle IPv6 in the tunnel. This may cause problems on networks without IPv6 support.")
        }
    }
}
