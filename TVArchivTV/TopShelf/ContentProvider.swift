import Foundation
import TVServices

/// „Pokračovať v pozeraní“ na hornej lište Apple TV (ako Netflix).
/// Údaje zapisuje hlavná aplikácia do zdieľaného App Group kontajnera (TopShelf/items.json + obrázky).
final class ContentProvider: TVTopShelfContentProvider {
    static let appGroup = "group.local.tvarchiv.player"

    struct Entry: Decodable {
        let path: String
        let title: String
        let showTitle: String
        let progress: Double
        let image: String?
    }

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else {
            completionHandler(nil)
            return
        }
        let dir = container.appendingPathComponent("TopShelf", isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("items.json")),
              let entries = try? JSONDecoder().decode([Entry].self, from: data), !entries.isEmpty else {
            completionHandler(nil)
            return
        }

        let items: [TVTopShelfSectionedItem] = entries.prefix(12).map { e in
            let item = TVTopShelfSectionedItem(identifier: e.path)
            item.title = e.showTitle.isEmpty ? e.title : "\(e.showTitle) – \(e.title)"
            item.imageShape = .hdtv
            if let img = e.image {
                let url = dir.appendingPathComponent(img)
                item.setImageURL(url, for: .screenScale1x)
                item.setImageURL(url, for: .screenScale2x)
            }
            if e.progress > 0.01 && e.progress < 0.97 { item.playbackProgress = e.progress }
            var comps = URLComponents()
            comps.scheme = "tvarchiv"
            comps.host = "play"
            comps.queryItems = [URLQueryItem(name: "path", value: e.path)]
            if let u = comps.url {
                item.playAction = TVTopShelfAction(url: u)
                item.displayAction = TVTopShelfAction(url: u)
            }
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Pokračovať v pozeraní"
        completionHandler(TVTopShelfSectionedContent(sections: [section]))
    }
}
