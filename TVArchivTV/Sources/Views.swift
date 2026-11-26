import SwiftUI

// MARK: - Karta relácie a mriežka

struct ShowCardView: View {
    let show: ShowCard
    private let size = CGSize(width: 260, height: 350)

    var body: some View {
        VStack(spacing: 14) {
            NavigationLink(value: Route.show(show)) {
                RemoteImage(url: show.imageURL)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            .buttonStyle(.card)
            VStack(spacing: 2) {
                Text(show.title).font(.callout.weight(.semibold)).lineLimit(2)
                if !show.info.isEmpty {
                    Text(show.info).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.ink)
            .frame(width: size.width, height: 80, alignment: .top)
        }
    }
}

struct ShowGrid: View {
    let shows: [ShowCard]
    private let columns = Array(repeating: GridItem(.fixed(260), spacing: 48), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
            ForEach(shows) { ShowCardView(show: $0) }
        }
    }
}

/// Zoznam relácií z ľubovoľnej stránky (stanica, písmeno…).
struct ShowListView: View {
    let title: String
    let path: String
    @State private var state: LoadState<[ShowCard]> = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                SectionTitle(text: title)
                content
            }
            .padding(.horizontal, 60)
        }
        .task(id: path) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading: LoadingView()
        case .failed(let msg): ErrorView(message: msg) { Task { await load() } }
        case .loaded(let shows):
            if shows.isEmpty { Text("Nič sa nenašlo.").foregroundStyle(.secondary) } else { ShowGrid(shows: shows) }
        }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await Site.shows(at: path)) } catch { state = .failed(error.localizedDescription) }
    }
}

// MARK: - Riadok videa

struct VideoRow: View {
    @EnvironmentObject private var player: PlayerCenter
    @EnvironmentObject private var library: Library
    let item: VideoItem
    var showShowTitle = false

    var body: some View {
        let entry = library.entry(for: item.path)
        Button {
            player.play(item)
        } label: {
            HStack(spacing: 24) {
                Image(systemName: icon(entry))
                    .font(.title3)
                    .foregroundStyle(item.source.playable ? Theme.blue : .gray)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    if showShowTitle && !item.showTitle.isEmpty {
                        Text(item.showTitle).font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
                    }
                    Text(item.title).font(.headline).lineLimit(2)
                    if !item.note.isEmpty {
                        Text(item.note).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let entry, entry.fraction > 0.01, !entry.finished {
                        ProgressView(value: entry.fraction).tint(Theme.blue).frame(maxWidth: 500)
                    }
                }
                Spacer()
                SourceBadge(source: item.source)
                if player.loadingPath == item.path { ProgressView() }
            }
            .padding(.vertical, 6)
        }
        .contextMenu {
            Button("Prehrať od začiatku") { player.play(item, fromStart: true) }
            if entry != nil {
                Button("Odstrániť z histórie", role: .destructive) { library.remove(item.path) }
            }
        }
    }

    private func icon(_ e: HistoryEntry?) -> String {
        if !item.source.playable { return "lock.fill" }
        if item.source == .youtube { return "play.rectangle.fill" }
        if e?.finished == true { return "checkmark.circle.fill" }
        return "play.circle.fill"
    }
}

// MARK: - Najnovšie

struct LatestView: View {
    @State private var state: LoadState<[VideoItem]> = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text("TV-ARCHÍV").font(Theme.serif(64)).foregroundStyle(Theme.gold)
                    Text("najnovšie videá").font(Theme.serif(30, bold: false)).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
                switch state {
                case .loading: LoadingView()
                case .failed(let msg): ErrorView(message: msg) { Task { await load() } }
                case .loaded(let items):
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { VideoRow(item: $0, showShowTitle: true) }
                    }
                }
            }
            .padding(.horizontal, 60)
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
    private let columns = Array(repeating: GridItem(.fixed(330), spacing: 40), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                SectionTitle(text: "Stanice")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                    ForEach(Site.channels) { ch in
                        NavigationLink(value: Route.list(title: ch.name, path: ch.path)) {
                            VStack(spacing: 10) {
                                Text(ch.name).font(Theme.serif(36)).foregroundStyle(ch.source.playable ? Theme.ink : .gray)
                                Text(ch.source.playable ? " " : "len s predplatným").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 330, height: 160)
                            .background(Color.white)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
            .padding(.horizontal, 60)
        }
    }
}

// MARK: - A – Z

struct AZView: View {
    @State private var letter = "a"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                SectionTitle(text: "Relácie a seriály A – Z")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Site.letters, id: \.self) { l in
                            Button {
                                letter = l
                            } label: {
                                Text(l.uppercased()).font(.headline).frame(minWidth: 40)
                            }
                            .tint(l == letter ? Theme.blue : nil)
                        }
                    }
                    .padding(.vertical, 20)
                }
                LetterGrid(letter: letter)
            }
            .padding(.horizontal, 60)
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
            VStack(alignment: .leading, spacing: 30) {
                if searching { LoadingView() }
                if !shows.isEmpty {
                    SectionTitle(text: "Relácie")
                    ShowGrid(shows: shows)
                }
                if !videos.isEmpty {
                    SectionTitle(text: "Videá")
                    LazyVStack(alignment: .leading) {
                        ForEach(videos) { VideoRow(item: $0, showShowTitle: true) }
                    }
                }
                if !searching && shows.isEmpty && videos.isEmpty && query.count >= 2 {
                    Text("Nič sa nenašlo.").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 60)
        }
        .searchable(text: $query, prompt: "Názov relácie, seriálu alebo filmu")
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

// MARK: - Moje (obľúbené + história)

struct MineView: View {
    @EnvironmentObject private var library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                SectionTitle(text: "Pokračovať v pozeraní")
                let unfinished = library.history.filter { !$0.finished }
                if unfinished.isEmpty {
                    Text("Zatiaľ nič. Rozpozerané videá sa zobrazia tu.").foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading) {
                        ForEach(unfinished.prefix(30)) { VideoRow(item: $0.item, showShowTitle: true) }
                    }
                }
                SectionTitle(text: "Obľúbené relácie")
                if library.favorites.isEmpty {
                    Text("Reláciu pridáte do obľúbených tlačidlom ☆ na jej stránke.").foregroundStyle(.secondary)
                } else {
                    ShowGrid(shows: library.favorites)
                }
                let done = library.history.filter { $0.finished }
                if !done.isEmpty {
                    SectionTitle(text: "Pozreté")
                    LazyVStack(alignment: .leading) {
                        ForEach(done.prefix(50)) { VideoRow(item: $0.item, showShowTitle: true) }
                    }
                }
            }
            .padding(.horizontal, 60)
        }
    }
}

// MARK: - Detail relácie

struct ShowDetailView: View {
    @EnvironmentObject private var library: Library
    let show: ShowCard
    @State private var state: LoadState<ShowDetail> = .loading
    @State private var group: String?

    var body: some View {
        ScrollView {
            switch state {
            case .loading: LoadingView()
            case .failed(let msg): ErrorView(message: msg) { Task { await load() } }
            case .loaded(let d): content(d)
            }
        }
        .task { if case .loading = state { await load() } }
    }

    @ViewBuilder private func content(_ d: ShowDetail) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .top, spacing: 50) {
                RemoteImage(url: d.card.imageURL)
                    .frame(width: 300, height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 18) {
                    Text(d.card.title).font(Theme.serif(56)).foregroundStyle(Theme.gold)
                    if !d.card.info.isEmpty { Text(d.card.info).font(.headline).foregroundStyle(.secondary) }
                    if !d.description.isEmpty {
                        Text(d.description).font(.body).lineLimit(6)
                    }
                    Button {
                        library.toggleFavorite(d.card)
                    } label: {
                        Label(library.isFavorite(d.card.path) ? "V obľúbených" : "Pridať do obľúbených",
                              systemImage: library.isFavorite(d.card.path) ? "star.fill" : "star")
                    }
                }
            }

            if d.groups.isEmpty {
                Text("Táto relácia zatiaľ nemá žiadne videá.").foregroundStyle(.secondary)
            } else {
                let current = selectedGroup(d)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(d.groups) { g in
                            Button {
                                group = g.id
                            } label: {
                                Text("\(g.id) (\(g.items.count))")
                            }
                            .tint(g.id == current.id ? Theme.blue : nil)
                        }
                    }
                    .padding(.vertical, 20)
                }
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(current.items) { VideoRow(item: $0) }
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.bottom, 60)
    }

    private func selectedGroup(_ d: ShowDetail) -> EpisodeGroup {
        if let group, let g = d.groups.first(where: { $0.id == group }) { return g }
        // predvolene: prvá skupina, ktorú vieme prehrať priamo (nie YouTube)
        return d.groups.first { $0.source.playable && $0.source != .youtube } ?? d.groups[0]
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await Site.detail(of: show)) } catch { state = .failed(error.localizedDescription) }
    }
}
