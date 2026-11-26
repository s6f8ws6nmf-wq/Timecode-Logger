import SwiftUI

// MARK: - Dlaždice

/// Krajinková dlaždica relácie (alebo filmu) – obrázok, pod ním názov.
struct ShowTile: View {
    @EnvironmentObject private var player: PlayerCenter
    let show: ShowCard
    var size = Theme.tileSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if show.isVideo {
                    Button { player.play(show.asVideo) } label: { art }
                } else {
                    NavigationLink(value: Route.show(show)) { art }
                }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 3) {
                Text(show.title).font(.callout.weight(.semibold)).lineLimit(1)
                if !show.info.isEmpty {
                    Text(show.info).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: size.width, alignment: .leading)
        }
    }

    private var art: some View {
        RemoteImage(urls: show.artwork)
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if show.isVideo {
                    Image(systemName: "play.fill").font(.caption).padding(12).glassCapsule().padding(12)
                }
            }
            .reportsBackdrop(show.artwork)
    }
}

/// Dlaždica videa (epizódy) s ukazovateľom rozpozerania.
struct VideoTile: View {
    @EnvironmentObject private var player: PlayerCenter
    @EnvironmentObject private var library: Library
    let item: VideoItem
    var size = Theme.tileSize

    var body: some View {
        let entry = library.entry(for: item.path)
        VStack(alignment: .leading, spacing: 14) {
            Button { player.play(item) } label: {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(urls: item.artwork)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                    Theme.posterGradient
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SourceBadge(source: item.source)
                            Spacer()
                            if player.loadingPath == item.path { ProgressView() }
                        }
                        Spacer()
                        if let entry, entry.fraction > 0.01, !entry.finished {
                            ProgressView(value: entry.fraction).tint(.white)
                        }
                    }
                    .padding(16)
                }
                .frame(width: size.width, height: size.height)
                .reportsBackdrop(item.artwork)
            }
            .buttonStyle(.card)
            .contextMenu {
                Button("Prehrať od začiatku") { player.play(item, fromStart: true) }
                if entry != nil { Button("Odstrániť z histórie", role: .destructive) { library.remove(item.path) } }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.showTitle.isEmpty ? item.title : item.showTitle)
                    .font(.callout.weight(.semibold)).lineLimit(1)
                if !item.showTitle.isEmpty {
                    Text(item.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: size.width, alignment: .leading)
        }
    }
}

/// Vodorovná polica s nadpisom.
struct ShelfRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.bold)).padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 40) { content }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }
}

struct ShowGrid: View {
    let shows: [ShowCard]
    private let columns = Array(repeating: GridItem(.fixed(Theme.tileSize.width), spacing: 40), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 50) {
            ForEach(shows) { ShowTile(show: $0) }
        }
    }
}

struct VideoGrid: View {
    let items: [VideoItem]
    private let columns = Array(repeating: GridItem(.fixed(Theme.tileSize.width), spacing: 40), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 50) {
            ForEach(items) { VideoTile(item: $0) }
        }
    }
}

struct PageTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 64, weight: .bold)).padding(.top, 20)
    }
}

// MARK: - Domov

struct HomeView: View {
    @EnvironmentObject private var library: Library
    @State private var state: LoadState<HomeFeed> = .loading

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                switch state {
                case .loading: LoadingView().frame(height: 700)
                case .failed(let msg): ErrorView(message: msg) { Task { await load() } }.padding(80)
                case .loaded(let feed):
                    if !feed.hero.isEmpty { HeroCarousel(items: feed.hero) }
                    let unfinished = library.history.filter { !$0.finished }
                    if !unfinished.isEmpty {
                        ShelfRow(title: "Pokračovať v pozeraní") {
                            ForEach(unfinished.prefix(20)) { VideoTile(item: $0.item) }
                        }
                    }
                    if !library.favorites.isEmpty {
                        ShelfRow(title: "Obľúbené") {
                            ForEach(library.favorites) { ShowTile(show: $0) }
                        }
                    }
                    ForEach(feed.shelves) { shelf in
                        ShelfRow(title: shelf.id) {
                            ForEach(shelf.items) { ShowTile(show: $0) }
                        }
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .task { if case .loading = state { await load() } }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await Site.home()) } catch { state = .failed(error.localizedDescription) }
    }
}

/// Veľký pás najnovších epizód na vrchu domovskej obrazovky.
struct HeroCarousel: View {
    @EnvironmentObject private var player: PlayerCenter
    let items: [HeroItem]
    private let size = CGSize(width: 1500, height: 600)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 50) {
                ForEach(items) { item in
                    Button { player.play(item.video) } label: { card(item) }
                        .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
    }

    private func card(_ item: HeroItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(urls: item.artwork)
                .frame(width: size.width, height: size.height)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                Text("NOVÁ EPIZÓDA").font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
                Text(item.video.showTitle).font(.system(size: 62, weight: .bold)).lineLimit(1)
                Text(item.video.title).font(.title3).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                HStack(spacing: 16) {
                    Label("Prehrať", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 30).padding(.vertical, 14)
                        .glassCapsule()
                    SourceBadge(source: item.video.source)
                    if player.loadingPath == item.video.path { ProgressView() }
                }
                .padding(.top, 10)
            }
            .foregroundStyle(.white)
            .padding(50)
        }
        .frame(width: size.width, height: size.height)
        .reportsBackdrop(item.artwork)
    }
}

// MARK: - Najnovšie

struct LatestView: View {
    @State private var state: LoadState<[VideoItem]> = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .lastTextBaseline) {
                    PageTitle(text: "Najnovšie")
                    Spacer()
                    Button { Task { await load() } } label: { Label("Obnoviť", systemImage: "arrow.clockwise") }
                        .glassButton()
                }
                switch state {
                case .loading: LoadingView()
                case .failed(let msg): ErrorView(message: msg) { Task { await load() } }
                case .loaded(let items): VideoGrid(items: items)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
        .task { if case .loading = state { await load() } }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await Site.latest()) } catch { state = .failed(error.localizedDescription) }
    }
}

// MARK: - Stanice

struct ChannelsView: View {
    private let columns = Array(repeating: GridItem(.fixed(380), spacing: 44), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                PageTitle(text: "Stanice")
                GlassGroup(spacing: 44) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 44) {
                        ForEach(Site.channels) { ch in
                            NavigationLink(value: Route.list(title: ch.name, path: ch.path)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(ch.name).font(.system(size: 40, weight: .bold))
                                    Text(ch.source.playable ? ch.source.name : "Len s predplatným")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(width: 320, height: 130, alignment: .leading)
                            }
                            .glassButton()
                        }
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
    }
}

/// Relácie z ľubovoľnej stránky so zoznamom (stanica…).
struct ShowListView: View {
    let title: String
    let path: String
    @State private var state: LoadState<[ShowCard]> = .loading

    var body: some View {
        ZStack {
            BackdropView()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    PageTitle(text: title)
                    switch state {
                    case .loading: LoadingView()
                    case .failed(let msg): ErrorView(message: msg) { Task { await load() } }
                    case .loaded(let shows):
                        if shows.isEmpty { Text("Nič sa nenašlo.").foregroundStyle(.secondary) } else { ShowGrid(shows: shows) }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await Site.shows(at: path)) } catch { state = .failed(error.localizedDescription) }
    }
}

// MARK: - A – Z

struct AZView: View {
    @State private var letter = "a"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageTitle(text: "Relácie A – Z")
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassGroup(spacing: 12) {
                        HStack(spacing: 12) {
                            ForEach(Site.letters, id: \.self) { l in
                                Button { letter = l } label: {
                                    Text(l.uppercased()).font(.headline).frame(minWidth: 36)
                                }
                                .glassButton(prominent: l == letter)
                            }
                        }
                    }
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
                LetterGrid(letter: letter)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
    }
}

private struct LetterGrid: View {
    let letter: String
    @State private var state: LoadState<[ShowCard]> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading: LoadingView()
            case .failed(let msg): ErrorView(message: msg) { Task { await load() } }
            case .loaded(let shows): ShowGrid(shows: shows)
            }
        }
        .task(id: letter) { await load() }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await Site.shows(at: "/-filter?pismena=\(letter)")) } catch { state = .failed(error.localizedDescription) }
    }
}

// MARK: - Hľadanie

struct SearchView: View {
    @State private var query = ""
    @State private var shows: [ShowCard] = []
    @State private var videos: [VideoItem] = []
    @State private var searching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if searching { LoadingView() }
                if !shows.isEmpty {
                    Text("Relácie").font(.title3.weight(.bold))
                    ShowGrid(shows: shows)
                }
                if !videos.isEmpty {
                    Text("Videá").font(.title3.weight(.bold))
                    VideoGrid(items: videos)
                }
                if !searching && shows.isEmpty && videos.isEmpty && query.count >= 2 {
                    Text("Nič sa nenašlo.").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
        .searchable(text: $query, prompt: "Relácie, seriály, filmy")
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { shows = []; videos = []; return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            searching = true
            let r = try? await Site.search(q)
            guard !Task.isCancelled else { return }
            searching = false
            shows = r?.shows ?? []
            videos = r?.videos ?? []
        }
    }
}

// MARK: - Moje

struct MineView: View {
    @EnvironmentObject private var library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageTitle(text: "Moje").padding(.horizontal, 80)
                let unfinished = library.history.filter { !$0.finished }
                let done = library.history.filter { $0.finished }
                if unfinished.isEmpty && library.favorites.isEmpty && done.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "sparkles.tv").font(.system(size: 70))
                        Text("Rozpozerané videá a obľúbené relácie sa zobrazia tu.")
                        Text("Reláciu pridáte do obľúbených tlačidlom ☆ na jej stránke.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                    .glassPanel()
                    .padding(.horizontal, 80)
                }
                if !unfinished.isEmpty {
                    ShelfRow(title: "Pokračovať v pozeraní") {
                        ForEach(unfinished.prefix(40)) { VideoTile(item: $0.item) }
                    }
                }
                if !library.favorites.isEmpty {
                    ShelfRow(title: "Obľúbené relácie") {
                        ForEach(library.favorites) { ShowTile(show: $0) }
                    }
                }
                if !done.isEmpty {
                    ShelfRow(title: "Pozreté") {
                        ForEach(done.prefix(40)) { VideoTile(item: $0.item) }
                    }
                }
            }
            .padding(.bottom, 80)
        }
    }
}

// MARK: - Detail relácie

struct ShowDetailView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: PlayerCenter
    let show: ShowCard
    @State private var state: LoadState<ShowDetail> = .loading
    @State private var group: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            RemoteImage(urls: show.artwork, placeholder: false)
                .frame(maxWidth: .infinity)
                .frame(height: 1080)
                .clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55), .black],
                                        startPoint: .top, endPoint: .bottom))
                .overlay(LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .leading, endPoint: .center))
                .ignoresSafeArea()

            ScrollView {
                switch state {
                case .loading: LoadingView().frame(height: 900)
                case .failed(let msg): ErrorView(message: msg) { Task { await load() } }.padding(80)
                case .loaded(let d): content(d)
                }
            }
        }
        .task { if case .loading = state { await load() } }
    }

    @ViewBuilder private func content(_ d: ShowDetail) -> some View {
        let current = d.groups.isEmpty ? nil : selectedGroup(d)
        VStack(alignment: .leading, spacing: 34) {
            Spacer().frame(height: 260)
            Text(d.card.title)
                .font(.system(size: 86, weight: .heavy))
                .lineLimit(2)
                .shadow(radius: 20)
            if !d.card.info.isEmpty {
                Text(d.card.info).font(.headline).foregroundStyle(.secondary)
            }
            if !d.description.isEmpty {
                Text(d.description).font(.body).lineLimit(4).frame(maxWidth: 1100, alignment: .leading)
                    .foregroundStyle(.white.opacity(0.85))
            }

            GlassGroup(spacing: 20) {
                HStack(spacing: 20) {
                    if let current, let first = resumeItem(in: current) {
                        Button { player.play(first) } label: {
                            Label(library.entry(for: first.path) != nil ? "Pokračovať" : "Prehrať najnovšie",
                                  systemImage: "play.fill")
                                .padding(.horizontal, 20)
                        }
                        .glassButton(prominent: true)
                    }
                    Button { library.toggleFavorite(d.card) } label: {
                        Label(library.isFavorite(d.card.path) ? "V obľúbených" : "Obľúbené",
                              systemImage: library.isFavorite(d.card.path) ? "star.fill" : "star")
                    }
                    .glassButton()
                }
            }

            if let current {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassGroup(spacing: 14) {
                        HStack(spacing: 14) {
                            ForEach(d.groups) { g in
                                Button { group = g.id } label: { Text("\(g.id)  \(g.items.count)") }
                                    .glassButton(prominent: g.id == current.id)
                            }
                        }
                    }
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()

                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(current.items) { EpisodeRow(item: $0) }
                }
            } else {
                Text("Táto relácia zatiaľ nemá žiadne videá.").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 80)
    }

    private func resumeItem(in g: EpisodeGroup) -> VideoItem? {
        if let e = library.history.first(where: { $0.item.showPath == show.path && !$0.finished }) { return e.item }
        return g.items.first
    }

    private func selectedGroup(_ d: ShowDetail) -> EpisodeGroup {
        if let group, let g = d.groups.first(where: { $0.id == group }) { return g }
        return d.groups.first { $0.source.playable && $0.source != .youtube } ?? d.groups[0]
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await Site.detail(of: show)) } catch { state = .failed(error.localizedDescription) }
    }
}

/// Riadok epizódy v detaile relácie – sklenený pás.
struct EpisodeRow: View {
    @EnvironmentObject private var player: PlayerCenter
    @EnvironmentObject private var library: Library
    let item: VideoItem

    var body: some View {
        let entry = library.entry(for: item.path)
        Button { player.play(item) } label: {
            HStack(spacing: 28) {
                Image(systemName: icon(entry))
                    .font(.title2)
                    .frame(width: 50)
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.headline).lineLimit(2)
                    if let entry, entry.fraction > 0.01, !entry.finished {
                        ProgressView(value: entry.fraction).frame(maxWidth: 520)
                    }
                }
                Spacer(minLength: 20)
                if player.loadingPath == item.path { ProgressView() }
                SourceBadge(source: item.source)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassButton()
        .contextMenu {
            Button("Prehrať od začiatku") { player.play(item, fromStart: true) }
            if entry != nil { Button("Odstrániť z histórie", role: .destructive) { library.remove(item.path) } }
        }
    }

    private func icon(_ e: HistoryEntry?) -> String {
        if !item.source.playable { return "lock.fill" }
        if item.source == .youtube { return "play.rectangle.fill" }
        if e?.finished == true { return "checkmark.circle.fill" }
        if let e, e.fraction > 0.01 { return "play.circle" }
        return "play.circle.fill"
    }
}
