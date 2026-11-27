import Foundation
import TVServices

/// Horná lišta Apple TV (Top Shelf):
/// 1. „Pokračovať v pozeraní“ – z histórie hlavnej aplikácie (zdieľaný App Group kontajner),
/// 2. „Najnovšie epizódy“ – doplnok si ich sám načíta z tv-archiv.sk (max. 5 s),
/// 3. „TV Archív“ – pevné dlaždice z balíka doplnku (fungujú vždy, aj bez siete a App Group).
final class ContentProvider: TVTopShelfContentProvider {
    static let appGroup = "group.local.tvarchiv.player"

    struct Entry: Decodable {
        let path: String
        let title: String
        let showTitle: String
        let progress: Double
        let image: String?
        let remoteImage: String?
    }

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task {
            var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []
            var notes: [String] = []

            if let history = Self.historySection() {
                sections.append(history)
                notes.append("história: \(history.items.count)")
            } else {
                notes.append(Self.groupDefaults == nil ? "App Group nedostupná" : "história prázdna")
            }

            if let latest = await Self.withTimeout(5, { await Self.latestSection() }) {
                sections.append(latest)
                notes.append("najnovšie: \(latest.items.count)")
            } else {
                notes.append("najnovšie: nenačítané")
            }

            sections.append(Self.staticSection())
            Self.writeStatus(notes.joined(separator: ", "))
            completionHandler(TVTopShelfSectionedContent(sections: sections))
        }
    }

    // MARK: - Sekcie

    private static func historySection() -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let dir = container.appendingPathComponent("TopShelf", isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("items.json")),
              let entries = try? JSONDecoder().decode([Entry].self, from: data), !entries.isEmpty else { return nil }
        let items = entries.prefix(12).map { e -> TVTopShelfSectionedItem in
            var image: URL?
            if let f = e.image, FileManager.default.fileExists(atPath: dir.appendingPathComponent(f).path) {
                image = dir.appendingPathComponent(f)
            } else if let r = e.remoteImage {
                image = URL(string: r)
            }
            return makeItem(id: e.path,
                            title: e.showTitle.isEmpty ? e.title : "\(e.showTitle) – \(e.title)",
                            image: image, progress: e.progress, link: playLink(e.path))
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = tr("Pokračovať v pozeraní")
        return section
    }

    private static func latestSection() async -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        guard let feed = try? await Site.home(), !feed.hero.isEmpty else { return nil }
        let items = feed.hero.prefix(16).map { h -> TVTopShelfSectionedItem in
            // JPEG (movies_merged) má prednosť – WebP nemusí Top Shelf zobraziť
            let image = h.artwork.first ?? h.image.flatMap { Net.url(HTML.unescapeJS($0)) }
            let title = h.video.showTitle.isEmpty ? h.video.title : "\(h.video.showTitle) – \(h.video.title)"
            return makeItem(id: h.video.path, title: title, image: image, progress: nil, link: playLink(h.video.path))
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = tr("Najnovšie videá")
        return section
    }

    private static func staticSection() -> TVTopShelfItemCollection<TVTopShelfSectionedItem> {
        let bundle = Bundle(for: ContentProvider.self)
        let tiles: [(String, String, String)] = [
            ("tab-live", tr("Live"), "shelf-live"),
            ("tab-shows", tr("Relácie"), "shelf-shows"),
            ("tab-search", tr("Hľadať"), "shelf-search"),
            ("tab-settings", tr("Nastavenia"), "shelf-settings")
        ]
        let items = tiles.map { id, title, img -> TVTopShelfSectionedItem in
            makeItem(id: id, title: title,
                     image: bundle.url(forResource: img, withExtension: "png"),
                     progress: nil,
                     link: URL(string: "tvarchiv://tab/\(id.replacingOccurrences(of: "tab-", with: ""))"))
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "TV Archív"
        return section
    }

    // MARK: - Pomôcky

    private static func makeItem(id: String, title: String, image: URL?, progress: Double?, link: URL?) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: id)
        item.title = title
        item.imageShape = .hdtv
        if let image {
            item.setImageURL(image, for: .screenScale1x)
            item.setImageURL(image, for: .screenScale2x)
        }
        if let progress, progress > 0.01, progress < 0.97 { item.playbackProgress = progress }
        if let link {
            item.playAction = TVTopShelfAction(url: link)
            item.displayAction = TVTopShelfAction(url: link)
        }
        return item
    }

    private static func playLink(_ path: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "tvarchiv"
        comps.host = "play"
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        return comps.url
    }

    private static func withTimeout<T>(_ seconds: Double, _ op: @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await op() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static var groupDefaults: UserDefaults? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) == nil
            ? nil : UserDefaults(suiteName: appGroup)
    }

    /// Stav posledného behu (aplikácia ho ukáže v Nastaveniach, ak funguje App Group).
    private static func writeStatus(_ text: String) {
        groupDefaults?.set(["date": Date(), "text": text], forKey: "topshelf.status")
    }
}
