import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    private var browserBinding: Binding<Bool> {
        Binding(
            get: { state.showBrowser },
            set: { state.showBrowser = $0 }
        )
    }

    var body: some View {
        TabView {
            AccountsView()
                .tabItem { Label("账号", systemImage: "person.2.fill") }
            NetworkView()
                .tabItem { Label("网络", systemImage: "network") }
            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .tint(KSDesign.accent)
        .task { state.preloadOCR() }
        .sheet(isPresented: browserBinding) {
            BrowserView(token: state.token, email: state.loggedInEmail)
                .environmentObject(state)
        }
    }
}
