import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.20),
                                    Color(red: 0.02, green: 0.05, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    ForEach(store.months) { month in
                        MonthRow(month: month)
                    }
                    Text("Zdroj: tv-archiv.sk · prehrávač TV JOJ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 80)
                        .padding(.bottom, 40)
                }
            }

            if store.loadingID != nil {
                ProgressView("Načítavam video…")
                    .padding(40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .alert("Chyba", isPresented: Binding(get: { store.errorText != nil },
                                             set: { if !$0 { store.errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorText ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 50) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hotel Paradise")
                    .font(.system(size: 76, weight: .heavy))
                Text("TV JOJ · 2012 · \(store.episodes.count) epizód")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let e = store.continueEpisode {
                Button {
                    store.play(e)
                } label: {
                    Label(store.state(for: e) == nil ? "Prehrať \(e.title)" : "Pokračovať: \(e.title)",
                          systemImage: "play.fill")
                }
            } else if let first = store.episodes.first {
                Button {
                    store.play(first)
                } label: {
                    Label("Prehrať od začiatku", systemImage: "play.fill")
                }
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
    }
}

private struct MonthRow: View {
    let month: MonthGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(month.name)
                .font(.title3.weight(.bold))
                .padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(month.episodes) { ep in
                        EpisodeCard(episode: ep)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 36)
            }
        }
    }
}

private struct EpisodeCard: View {
    @EnvironmentObject private var store: Store
    let episode: Episode

    private let size = CGSize(width: 400, height: 225)

    var body: some View {
        let state = store.state(for: episode)
        VStack(alignment: .leading, spacing: 14) {
            Button {
                store.play(episode)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: episode.posterURL) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            placeholder
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()

                    if let state, state.fraction > 0.01, !state.finished {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.5))
                                Rectangle().fill(Color.orange)
                                    .frame(width: geo.size.width * state.fraction)
                            }
                        }
                        .frame(height: 8)
                    }

                    if state?.finished == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white, .green)
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

                    if store.loadingID == episode.id {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            .buttonStyle(.card)
            .contextMenu {
                Button("Prehrať od začiatku") {
                    store.resetProgress(episode)
                    store.play(episode)
                }
                if state != nil {
                    Button("Označiť ako nepozreté", role: .destructive) {
                        store.resetProgress(episode)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(episode.subtitle.isEmpty ? episode.dateText : "\(episode.subtitle) · \(episode.dateText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: size.width, alignment: .leading)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 70))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
