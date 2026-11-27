import SwiftUI

/// Karta Obľúbené: obľúbené relácie a webkamery.
struct FavoritesView: View {
    @EnvironmentObject private var library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageTitle(text: tr("Obľúbené")).padding(.horizontal, 80)

                if library.favorites.isEmpty && library.favoriteCams.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "star").font(.system(size: 70))
                        Text(tr("Zatiaľ nemáte nič v obľúbených."))
                            .font(.headline)
                        Text(tr("Reláciu pridáte tlačidlom ☆ Obľúbené na jej stránke, webkameru podržaním stredného tlačidla."))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                    .glassPanel()
                    .padding(.horizontal, 80)
                }

                if !library.favorites.isEmpty {
                    Text(tr("Obľúbené relácie")).font(.title3.weight(.bold)).padding(.horizontal, 80)
                    ShowGrid(shows: library.favorites)
                        .padding(.horizontal, 80)
                }

                if !library.favoriteCams.isEmpty {
                    ShelfRow(title: tr("Obľúbené webkamery")) {
                        ForEach(library.favoriteCams) { WebcamTile(cam: $0) }
                    }
                }
            }
            .padding(.bottom, 80)
        }
    }
}
