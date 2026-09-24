import HakoClientUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ActivityView: View, Equatable {
    let command: ClashCommandClient
    let connections: ConnectionsModel
    @Binding var lens: HakoActivityLens
    var loadsPersistedLogs = true
    #if os(macOS)
     
     
     
     
    @State private var segmentTitles: [(lens: HakoActivityLens, title: String)] = []
    @Environment(\.locale) private var locale
    #endif

    static func == (lhs: ActivityView, rhs: ActivityView) -> Bool {
        lhs.command === rhs.command
            && lhs.connections === rhs.connections
            && lhs.lens == rhs.lens
            && lhs.loadsPersistedLogs == rhs.loadsPersistedLogs
    }

     
     
    private static var searchFieldStyle: HakoActivitySearchFieldStyle {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .phoneBottomBar : .standard
        #else
        .standard
        #endif
    }

     
     
     
    private static var showsLensStrip: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    var body: some View {
         
         
        let _ = HakoLogTextPlatform.installIfNeeded()
        page
            #if os(macOS)
             
             
            .hakoToolbarUnlessInPanel {
                ToolbarItem(placement: .principal) {
                    Picker(selection: $lens) {
                        ForEach(segmentTitles, id: \.lens) { segment in
                            Text(verbatim: segment.title).tag(segment.lens)
                        }
                    } label: {
                        Text(hako: .copy("Activity"))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("activity.lens.segment")
                }
            }
            .task(id: locale) {
                segmentTitles = HakoActivityLens.allCases.map { ($0, HakoCopy.string($0.title, locale: locale)) }
            }
            #endif
    }

    private var page: some View {
        HakoActivityPageView(
            lens: $lens,
            palette: HakoActivityIOSAdapter.palette,
            searchFieldStyle: Self.searchFieldStyle,
            showsLensStrip: Self.showsLensStrip
        ) { query, isShown in
             
             
             
            ConnectionsView(
                model: connections,
                command: command,
                autoStart: false,
                query: query,
                isShown: isShown
            )
        } requests: { query, isShown in
            RequestsView(model: connections, query: query, isShown: isShown)
        } logs: { query, isShown in
            LogsDestinationView(
                command: command,
                loadsPersistedLogs: loadsPersistedLogs,
                query: query,
                isShown: isShown
            )
        }
    }
}
