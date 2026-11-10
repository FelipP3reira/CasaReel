import Domain
import FeaturePhotos
import SwiftUI

/// Tab shell shown after sign-in; each tab owns a typed NavigationStack driven by the Router.
struct MainTabView: View {
    @Bindable var router: Router
    let photoSelection: PhotoSelectionModel
    let editor: EditorSession
    let environment: AppEnvironment
    let onSignOut: () -> Void

    var body: some View {
        TabView(selection: $router.selectedTab) {
            stack(for: .properties) { PropertyListScreen(router: router) }
                .tabItem { Label("Imóveis", systemImage: "house") }
                .tag(AppTab.properties)

            stack(for: .create) { PhotoPickerScreen(router: router, selection: photoSelection, editor: editor, environment: environment) }
                .tabItem { Label("Criar", systemImage: "plus.circle") }
                .tag(AppTab.create)

            stack(for: .account) { AccountScreen(router: router, onSignOut: onSignOut) }
                .tabItem { Label("Conta", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
    }

    private func stack<Root: View>(for tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: Binding(
            get: { router.path(for: tab) },
            set: { router.setPath($0, for: tab) }
        )) {
            root().navigationDestination(for: AppRoute.self) { route in
                RouteDestination(route: route, router: router, photoSelection: photoSelection,
                                 editor: editor, environment: environment, onSignOut: onSignOut)
            }
        }
    }
}

/// Maps each pushed route to its screen.
struct RouteDestination: View {
    let route: AppRoute
    let router: Router
    let photoSelection: PhotoSelectionModel
    let editor: EditorSession
    let environment: AppEnvironment
    let onSignOut: () -> Void

    var body: some View {
        switch route {
        case .auth:
            EmptyView()
        case .propertyList:
            PropertyListScreen(router: router)
        case .propertyDetail(let id):
            PropertyDetailScreen(id: id)
        case .photoPicker:
            PhotoPickerScreen(router: router, selection: photoSelection, editor: editor, environment: environment)
        case .videoEditor:
            VideoEditorScreen(router: router, editor: editor)
        case .subscription:
            SubscriptionScreen()
        case .privacy:
            PrivacyScreen()
        case .settings:
            SettingsScreen()
        }
    }
}
