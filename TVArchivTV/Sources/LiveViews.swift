import SwiftUI

// MARK: - Live

struct LiveView: View {
    @EnvironmentObject private var player: PlayerCenter
    @State private var catalog: WebcamCatalog?
    private let columns = Array(repeating: GridItem(.fixed(380), spacing: 40), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                PageTitle(text: tr("Živé vysielanie")).padding(.horizontal, 80)
                channels
                if let catalog {
                    // americké televízie, letiská… (skupiny s "live": true)
                    ForEach(catalog.liveGroups) { g in
                        ShelfRow(title: g.displayTitle) {
                            ForEach(g.cams) { WebcamTile(cam: $0) }
                        }
                    }
                    WebcamsSection(catalog: catalog)
                } else {
                    LoadingView()
                }
            }
            .padding(.bottom, 80)
        }
        .task { if catalog == nil { catalog = await WebcamStore.load() } }
    }

    private var channels: some View {
        VStack(alignment: .leading, spacing: 34) {
            ForEach(groups, id: \.self) { group in
                Text(group).font(.title3.weight(.bold))
                GlassGroup(spacing: 40) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                        ForEach(LiveChannel.all.filter { $0.group == group }) { ch in
                            Button {
                                player.playLive(id: ch.id, title: ch.name, subtitle: ch.group) { await ch.resolve() }
                            } label: {
                                HStack(spacing: 18) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ch.name).font(.system(size: 34, weight: .bold))
                                            .lineLimit(1).minimumScaleFactor(0.6)
                                        Text(tr("NAŽIVO")).font(.caption2.weight(.heavy)).foregroundStyle(.red)
                                    }
                                    Spacer(minLength: 0)
                                    if player.loadingPath == "live:" + ch.id { ProgressView() }
                                }
                                .frame(width: 320, height: 110, alignment: .leading)
                            }
                            .glassButton()
                        }
                    }
                }
            }
            Text(tr("Česká televize vysiela väčšinu programov len pre Česko; ČT24 býva dostupná aj na Slovensku."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 80)
    }

    private var groups: [String] {
        var seen = Set<String>(); var out: [String] = []
        for c in LiveChannel.all where !seen.contains(c.group) { seen.insert(c.group); out.append(c.group) }
        return out
    }
}

// MARK: - Webkamery

struct WebcamTile: View {
    @EnvironmentObject private var player: PlayerCenter
    @EnvironmentObject private var library: Library
    let cam: Webcam
    var size = Theme.tileSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { player.playWebcam(cam) } label: {
                ZStack(alignment: .topLeading) {
                    if cam.youtube != nil {
                        RemoteImage(urls: cam.thumbnail)
                    } else {
                        ZStack {
                            LinearGradient(colors: [Color(red: 0.15, green: 0.35, blue: 0.6), Color(red: 0.05, green: 0.12, blue: 0.25)],
                                           startPoint: .top, endPoint: .bottom)
                            Image(systemName: "mountain.2.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 10, height: 10)
                        Text("LIVE").font(.caption2.weight(.heavy))
                        if cam.youtube != nil {
                            Image(systemName: "play.rectangle.fill").font(.caption2)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassCapsule()
                    .padding(14)
                    if library.isFavoriteCam(cam) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }
                    if player.loadingPath == "live:" + cam.id {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .reportsBackdrop(cam.thumbnail)
            }
            .buttonStyle(.card)
            .contextMenu {
                Button(library.isFavoriteCam(cam) ? tr("Odobrať z obľúbených") : tr("Pridať do obľúbených")) {
                    library.toggleFavoriteCam(cam)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(cam.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(cam.place).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: size.width, alignment: .leading)
        }
    }
}

struct WebcamsSection: View {
    @EnvironmentObject private var library: Library
    let catalog: WebcamCatalog
    @State private var region = "*"
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .lastTextBaseline, spacing: 30) {
                Text(tr("Webkamery")).font(.system(size: 52, weight: .bold))
                Spacer()
                TextField(tr("Hľadať kameru"), text: $query)
                    .frame(width: 520)
            }
            .padding(.horizontal, 80)
            .padding(.top, 30)

            ScrollView(.horizontal, showsIndicators: false) {
                GlassGroup(spacing: 14) {
                    HStack(spacing: 14) {
                        chip("*", tr("Všetko"))
                        chip("fav", tr("Obľúbené"))
                        ForEach(catalog.regions, id: \.self) { r in chip(r, catalog.regionTitle(r)) }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()

            let rows = visibleRows()
            if rows.isEmpty {
                Text(region == "fav"
                     ? tr("Zatiaľ nemáte obľúbené kamery. Podržte stredné tlačidlo na kamere a zvoľte Pridať do obľúbených.")
                     : tr("Žiadna kamera nezodpovedá hľadaniu."))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 80)
            }
            ForEach(rows) { row in
                ShelfRow(title: row.title) {
                    ForEach(row.cams) { WebcamTile(cam: $0) }
                }
            }
        }
    }

    private func chip(_ id: String, _ title: String) -> some View {
        Button { region = id } label: { Text(title).lineLimit(1).fixedSize() }
            .glassButton(prominent: id == region)
    }

    struct Row: Identifiable {
        let title: String
        let cams: [Webcam]
        var id: String { title }
    }

    private func visibleRows() -> [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        func match(_ cam: Webcam) -> Bool { q.isEmpty || cam.searchText.contains(q) }
        var rows: [Row] = []
        if region == "*" || region == "fav" {
            let fav = library.favoriteCams.filter(match)
            if !fav.isEmpty { rows.append(Row(title: tr("Obľúbené kamery"), cams: fav)) }
            if region == "fav" { return rows }
        }
        for g in catalog.webcamGroups where region == "*" || g.region == region {
            let cams = g.cams.filter(match)
            if !cams.isEmpty { rows.append(Row(title: g.displayTitle, cams: cams)) }
        }
        return rows
    }
}
