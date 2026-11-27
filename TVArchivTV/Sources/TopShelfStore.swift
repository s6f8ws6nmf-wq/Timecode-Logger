import Foundation
import TVServices
import UIKit

/// Zapisuje naposledy pozerané videá pre Top Shelf (doplnok ContentProvider ich zobrazí na hornej lište Apple TV).
enum TopShelfStore {
    static let appGroup = "group.local.tvarchiv.player"

    private struct Entry: Encodable {
        let path: String
        let title: String
        let showTitle: String
        let progress: Double
        let image: String?
        let remoteImage: String?
    }

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("TopShelf", isDirectory: true)
    }

    static func update(history: [HistoryEntry]) {
        guard let dir = directory else { return }
        let recent = Array(history.prefix(12))
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var entries: [Entry] = []
            var keep = Set<String>(["items.json"])
            for h in recent {
                let name = fileName(for: h.item.showPath)
                let file = dir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: file.path) {
                    await download(h.item.artwork, to: file)
                }
                let hasImage = FileManager.default.fileExists(atPath: file.path)
                if hasImage { keep.insert(name) }
                entries.append(Entry(path: h.item.path, title: h.item.title, showTitle: h.item.showTitle,
                                     progress: h.fraction, image: hasImage ? name : nil,
                                     remoteImage: h.item.artwork.last?.absoluteString))
            }
            if let data = try? JSONEncoder().encode(entries) {
                try? data.write(to: dir.appendingPathComponent("items.json"), options: .atomic)
            }
            // staré obrázky preč
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for f in files where !keep.contains(f) {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
                }
            }
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    private static func fileName(for showPath: String) -> String {
        let safe = showPath.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return "img\(safe).jpg"
    }

    private static func download(_ urls: [URL], to file: URL) async {
        for u in urls {
            guard let data = try? await Net.data(u, referer: Net.base.absoluteString + "/"),
                  let image = UIImage(data: data) else { continue }
            // Top Shelf má pomer 16:9 – orežeme na stred
            let size = CGSize(width: 800, height: 450)
            let renderer = UIGraphicsImageRenderer(size: size)
            let out = renderer.image { _ in
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let w = image.size.width * scale, h = image.size.height * scale
                image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            }
            if let jpg = out.jpegData(compressionQuality: 0.85) {
                try? jpg.write(to: file, options: .atomic)
                return
            }
        }
    }
}
