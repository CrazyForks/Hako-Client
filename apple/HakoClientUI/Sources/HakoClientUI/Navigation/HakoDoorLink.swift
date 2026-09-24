import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
public struct HakoDoorLink<Route: Hashable, Destination: View, RowLabel: View>: View {
    private let route: Route
    @Binding private var selection: Route?
    private let destination: () -> Destination
    private let label: () -> RowLabel
#if os(macOS)
    @Environment(\.hakoNavigationHostContext) private var hostContext
    @Environment(\.hakoNavigationDepth) private var depth
#endif

    public init(
        _ route: Route,
        selection: Binding<Route?>,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> RowLabel
    ) {
        self.route = route
        self._selection = selection
        self.destination = destination
        self.label = label
    }

    public var body: some View {
#if os(macOS)
         
         
         
         
        let _ = HakoPushAuthority.trace("door", hostContext, depth)
        if HakoPushAuthority.canPush(hostContext: hostContext, depth: depth) {
            HakoRoutedViewLink {
                destination()
            } label: {
                label()
            }
        } else {
            Button {
                 
                 
                HakoPageProbe.markNavigation()
                selection = route
            } label: {
                HStack(spacing: 6) {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: HakoSymbol.chevronForward.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
#else
        HakoRoutedViewLink {
            destination()
        } label: {
            label()
        }
#endif
    }
}

 
 
 
 
public struct HakoDoorPayload: Identifiable {
    public let id: String
    public let title: String
    public let destination: AnyView

    public init(id: String, title: String, destination: AnyView) {
        self.id = id
        self.title = title
        self.destination = destination
    }
}

 
public struct HakoPayloadDoorLink<Destination: View, RowLabel: View>: View {
    private let id: String
    private let title: String
    @Binding private var selection: HakoDoorPayload?
    private let destination: () -> Destination
    private let label: () -> RowLabel
#if os(macOS)
    @Environment(\.hakoNavigationHostContext) private var hostContext
    @Environment(\.hakoNavigationDepth) private var depth
#endif

    public init(
        id: String,
        title: String,
        selection: Binding<HakoDoorPayload?>,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> RowLabel
    ) {
        self.id = id
        self.title = title
        self._selection = selection
        self.destination = destination
        self.label = label
    }

    public var body: some View {
#if os(macOS)
        if HakoPushAuthority.canPush(hostContext: hostContext, depth: depth) {
            HakoRoutedViewLink {
                destination()
            } label: {
                label()
            }
        } else {
            Button {
                selection = HakoDoorPayload(
                    id: id,
                    title: title,
                    destination: AnyView(destination())
                )
            } label: {
                HStack(spacing: 6) {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: HakoSymbol.chevronForward.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
#else
        HakoRoutedViewLink {
            destination()
        } label: {
            label()
        }
#endif
    }
}

 
 
 
 
 
 
 
 
 
 
public struct HakoDoorSaving {
    public let isDirty: () -> Bool
     
     
    public let save: (@escaping (Bool) -> Void) -> Void
    public let discard: () -> Void

    public init(
        isDirty: @escaping () -> Bool,
        save: @escaping (@escaping (Bool) -> Void) -> Void,
        discard: @escaping () -> Void
    ) {
        self.isDirty = isDirty
        self.save = save
        self.discard = discard
    }
}

public extension View {
     
    @ViewBuilder
    func hakoDoorPresenter(
        payload: Binding<HakoDoorPayload?>,
        saving: HakoDoorSaving? = nil
    ) -> some View {
#if os(macOS)
        hakoProductModal(item: payload, role: .form) { item in
            HakoSingleColumnNavigationContainer {
                 
                 
                item.destination
                    .hakoProductModalRoot(title: item.title)
                    .hakoDoorSaveBar(saving) { payload.wrappedValue = nil }
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    .hakoRegistersDeparture(
                        isDirty: saving?.isDirty() ?? false,
                        save: saving?.save ?? { $0(true) },
                        discard: saving?.discard ?? {}
                    )
            }
        }
#else
        self
#endif
    }

     
     
     
     
    @ViewBuilder
    func hakoDoorPresenter<Route: Hashable & Identifiable, C: View>(
        selection: Binding<Route?>,
        title: @escaping (Route) -> String,
        saving: HakoDoorSaving? = nil,
        @ViewBuilder content: @escaping (Route) -> C
    ) -> some View {
#if os(macOS)
         
         
         
         
        hakoProductModal(item: selection, role: .form) { route in
            HakoSingleColumnNavigationContainer {
                content(route)
                    .hakoProductModalRoot(title: title(route))
                    .hakoDoorSaveBar(saving) { selection.wrappedValue = nil }
                     
                     
                     
                    .hakoRegistersDeparture(
                        isDirty: saving?.isDirty() ?? false,
                        save: saving?.save ?? { $0(true) },
                        discard: saving?.discard ?? {}
                    )
            }
        }
#else
        self
#endif
    }
}

#if os(macOS)
private extension View {
     
     
     
     
    @ViewBuilder
    func hakoDoorSaveBar(_ saving: HakoDoorSaving?, close: @escaping () -> Void) -> some View {
        if let saving {
            safeAreaInset(edge: .bottom, spacing: 0) {
                HakoModalActionBar(
                    primaryTitle: "Save",
                    primaryDisabled: !saving.isDirty(),
                    onPrimary: { saving.save { saved in if saved { close() } } }
                )
            }
        } else {
            self
        }
    }
}
#endif
