import SwiftUI

@main
struct TVArchivApp: App {
    @StateObject private var library: Library
    @StateObject private var player: PlayerCenter

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
        }
    }
}

enum Route: Hashable {
    case show(ShowCard)
    case list(title: String, path: String)
}

struct RootView: View {
    @EnvironmentObject private var player: PlayerCenter

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            TabView {
                Stack { LatestView() }
                    .tabItem { Text("Najnovšie") }
                Stack { ChannelsView() }
                    .tabItem { Text("Stanice") }
                Stack { AZView() }
                    .tabItem { Text("A – Z") }
                Stack { SearchView() }
                    .tabItem { Label("Hľadať", systemImage: "magnifyingglass") }
                Stack { MineView() }
                    .tabItem { Text("Moje") }
            }

            if player.loadingPath != nil {
                ProgressView("Načítavam video…")
                    .padding(48)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .preferredColorScheme(.light)
        .alert("Video", isPresented: Binding(get: { player.message != nil },
                                             set: { if !$0 { player.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.message ?? "")
        }
    }
}

/// NavigationStack so spoločnými cieľmi navigácie.
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
