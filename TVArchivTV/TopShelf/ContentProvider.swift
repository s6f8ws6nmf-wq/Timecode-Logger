import Foundation
import TVServices

/// Horná lišta Apple TV (Top Shelf) ako Netflix:
/// 1. „Pokračovať v pozeraní“ – z histórie hlavnej aplikácie (zdieľaný App Group kontajner),
/// 2. „Najnovšie epizódy“ – doplnok si ich sám načíta z tv-archiv.sk, takže lišta nie je nikdy prázdna.
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
            if let history = Self.historySection() { sections.append(history) }
            if let latest = await Self.latestSection() { sections.append(latest) }
            completionHandler(sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections))
        }
    }

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
            return makeItem(path: e.path,
                            title: e.showTitle.isEmpty ? e.title : "\(e.showTitle) – \(e.title)",
                            image: image,
                            progress: e.progress)
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Pokračovať v pozeraní"
        return section
    }

    private static func latestSection() async -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        guard let feed = try? await Site.home(), !feed.hero.isEmpty else { return nil }
        let items = feed.hero.prefix(16).map { h -> TVTopShelfSectionedItem in
            let image = h.image.flatMap { Net.url(HTML.unescapeJS($0)) } ?? h.artwork.first
            let title = h.video.showTitle.isEmpty ? h.video.title : "\(h.video.showTitle) – \(h.video.title)"
            return makeItem(path: h.video.path, title: title, image: image, progress: nil)
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Najnovšie epizódy"
        return section
    }

    private static func makeItem(path: String, title: String, image: URL?, progress: Double?) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: path)
        item.title = title
        item.imageShape = .hdtv
        if let image {
            item.setImageURL(image, for: .screenScale1x)
            item.setImageURL(image, for: .screenScale2x)
        }
        if let progress, progress > 0.01, progress < 0.97 { item.playbackProgress = progress }
        var comps = URLComponents()
        comps.scheme = "tvarchiv"
        comps.host = "play"
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        if let u = comps.url {
            item.playAction = TVTopShelfAction(url: u)
            item.displayAction = TVTopShelfAction(url: u)
        }
        return item
    }
}
