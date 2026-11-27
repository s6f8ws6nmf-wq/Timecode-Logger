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

    var body: some View {
        ZStack {
            BackdropView()
            TabView {
                Stack { HomeView() }
                    .tabItem { Label("Domov", systemImage: "house.fill") }
                Stack { LatestView() }
                    .tabItem { Label("Najnovšie", systemImage: "clock.fill") }
                Stack { ChannelsView() }
                    .tabItem { Label("Stanice", systemImage: "tv.fill") }
                Stack { AZView() }
                    .tabItem { Label("A – Z", systemImage: "textformat") }
                Stack { MineView() }
                    .tabItem { Label("Moje", systemImage: "person.crop.circle") }
                Stack { SearchView() }
                    .tabItem { Label("Hľadať", systemImage: "magnifyingglass") }
            }

            if player.loadingPath != nil {
                HStack(spacing: 24) {
                    ProgressView()
                    Text("Pripravujem video…").font(.headline)
                }
                .padding(.horizontal, 48).padding(.vertical, 32)
                .glassPanel(cornerRadius: 40)
            }
        }
        .onOpenURL { url in
            guard let item = library.item(forDeepLink: url) else { return }
            // krátka pauza, aby bolo okno pripravené aj pri studenom štarte z Top Shelf
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { player.play(item) }
        }
        .onAppear { library.refreshTopShelf() }
        .alert("Video", isPresented: Binding(get: { player.message != nil },
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
