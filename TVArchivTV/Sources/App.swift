import SwiftUI

@main
struct TVArchivApp: App {
    @StateObject private var library: Library
    @StateObject private var player: PlayerCenter
    @StateObject private var backdrop = Backdrop()
    @StateObject private var availability = Availability()

    init() {
        let lib = Library()
        _library = StateObject(wrappedValue: lib)
        _player = StateObject(wrappedValue: PlayerCenter(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(backdrop)
                .environmentObject(availability)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum Route: Hashable {
    case show(ShowCard)
    case list(title: String, path: String)
}

struct RootView: View {
    @EnvironmentObject private var player: PlayerCenter
    @EnvironmentObject private var library: Library
    @AppStorage(AppLanguage.storageKey) private var lang = AppLanguage.sk.rawValue
    @State private var installWarning: String?
    @State private var tab = "home"

    var body: some View {
        ZStack {
            BackdropView()
            TabView(selection: $tab) {
                Stack { HomeView() }
                    .tabItem { Label(tr("Domov"), systemImage: "house.fill") }
                    .tag("home")
                Stack { AZView() }
                    .tabItem { Label(tr("Relácie"), systemImage: "film.stack") }
                    .tag("shows")
                Stack { LiveView() }
                    .tabItem { Label(tr("Live"), systemImage: "dot.radiowaves.left.and.right") }
                    .tag("live")
                Stack { SearchView() }
                    .tabItem { Label(tr("Hľadať"), systemImage: "magnifyingglass") }
                    .tag("search")
                Stack { SettingsView() }
                    .tabItem { Label(tr("Nastavenia"), systemImage: "gearshape.fill") }
                    .tag("settings")
            }
            // zmena jazyka prekreslí celé rozhranie
            .id(lang)

            if player.loadingPath != nil {
                HStack(spacing: 24) {
                    ProgressView()
                    Text(tr("Pripravujem video…")).font(.headline)
                }
                .padding(.horizontal, 48).padding(.vertical, 32)
                .glassPanel(cornerRadius: 40)
            }
        }
        .onOpenURL { url in
            // tvarchiv://tab/<live|shows|search|settings> z Top Shelf
            if url.host == "tab" {
                let t = url.lastPathComponent
                if ["home", "shows", "live", "search", "settings"].contains(t) { tab = t }
                return
            }
            guard let item = library.item(forDeepLink: url) else { return }
            // krátka pauza, aby bolo okno pripravené aj pri studenom štarte z Top Shelf
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { player.play(item) }
        }
        .onAppear {
            library.refreshTopShelf()
            installWarning = InstallInfo.warningIfNeeded()
        }
        .alert(tr("Upozornenie"), isPresented: Binding(get: { installWarning != nil },
                                                      set: { if !$0 { installWarning = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installWarning ?? "")
        }
        .alert(tr("Video"), isPresented: Binding(get: { player.message != nil },
                                             set: { if !$0 { player.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.message ?? "")
        }
    }
}

/// NavigationStack so spoločnými cieľmi navigácie; pozadie preberá z BackdropView.
struct Stack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .show(let card): ShowDetailView(show: card)
                    case let .list(title, path): ShowListView(title: title, path: path)
                    }
                }
        }
    }
}
