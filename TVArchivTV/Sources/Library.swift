import Foundation
import SwiftUI
import UIKit

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { item.path }
    var item: VideoItem
    var position: Double
    var duration: Double
    var date: Date

    var fraction: Double { duration > 0 ? min(1, position / duration) : 0 }
    var finished: Bool { fraction >= 0.95 }
}

/// Uložené údaje: história pozerania (s pozíciou) a obľúbené relácie.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var favorites: [ShowCard] = []
    @Published private(set) var favoriteCams: [Webcam] = []

    private let defaults = UserDefaults.standard
    private let historyKey = "history.v1"
    private let favoritesKey = "favorites.v1"
    private let favoriteCamsKey = "favoriteCams.v1"

    init() {
        if let d = defaults.data(forKey: historyKey), let h = try? JSONDecoder().decode([HistoryEntry].self, from: d) {
            history = h
        }
        if let d = defaults.data(forKey: favoritesKey), let f = try? JSONDecoder().decode([ShowCard].self, from: d) {
            favorites = f
        }
        if let d = defaults.data(forKey: favoriteCamsKey), let f = try? JSONDecoder().decode([Webcam].self, from: d) {
            favoriteCams = f
        }
    }

    func entry(for path: String) -> HistoryEntry? { history.first { $0.item.path == path } }

    func isFavoriteCam(_ cam: Webcam) -> Bool { favoriteCams.contains { $0.id == cam.id } }

    func toggleFavoriteCam(_ cam: Webcam) {
        if isFavoriteCam(cam) {
            favoriteCams.removeAll { $0.id == cam.id }
        } else {
            favoriteCams.insert(cam, at: 0)
        }
        if let d = try? JSONEncoder().encode(favoriteCams) { defaults.set(d, forKey: favoriteCamsKey) }
    }

    func record(_ item: VideoItem, position: Double, duration: Double) {
        // živé vysielanie a webkamery sa do histórie nezapisujú
        guard !item.path.hasPrefix("live:") else { return }
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        history.removeAll { $0.item.path == item.path }
        history.insert(HistoryEntry(item: item, position: position, duration: duration, date: Date()), at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        save()
    }

    func startPosition(for path: String) -> Double {
        guard let e = entry(for: path), !e.finished, e.position > 15 else { return 0 }
        return e.position - 5
    }

    func remove(_ path: String) {
        history.removeAll { $0.item.path == path }
        save()
        refreshTopShelf()
    }

    func clearHistory() {
        history = []
        save()
        refreshTopShelf()
    }

    func isFavorite(_ path: String) -> Bool { favorites.contains { $0.path == path } }

    func toggleFavorite(_ show: ShowCard) {
        if isFavorite(show.path) {
            favorites.removeAll { $0.path == show.path }
        } else {
            favorites.insert(show, at: 0)
        }
        if let d = try? JSONEncoder().encode(favorites) { defaults.set(d, forKey: favoritesKey) }
    }

    private var lastShelfUpdate = Date.distantPast

    private func save() {
        if let d = try? JSONEncoder().encode(history) { defaults.set(d, forKey: historyKey) }
        // Top Shelf netreba obnovovať pri každom zázname pozície
        if Date().timeIntervalSince(lastShelfUpdate) > 30 { refreshTopShelf() }
    }

    func refreshTopShelf() {
        lastShelfUpdate = Date()
        TopShelfStore.update(history: history)
    }

    /// Spustenie videa z Top Shelf (tvarchiv://play?path=/relacia/epizoda).
    func item(forDeepLink url: URL) -> VideoItem? {
        guard url.scheme == "tvarchiv",
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "path" })?.value else { return nil }
        if let e = entry(for: path) { return e.item }
        return VideoItem(path: path, title: "", showTitle: "", source: .other)
    }
}

/// Spúšťanie prehrávania: zistí stream a otvorí natívny prehrávač.
@MainActor
final class PlayerCenter: ObservableObject {
    @Published var loadingPath: String?
    @Published var message: String?

    let library: Library

    init(library: Library) { self.library = library }

    func play(_ item: VideoItem, fromStart: Bool = false) {
        guard loadingPath == nil else { return }
        if !item.source.playable {
            message = trf("%@ vyžaduje predplatné alebo DRM a na Apple TV sa prehrať nedá.", item.source.name)
            return
        }
        loadingPath = item.path
        Task {
            let result = await Resolver.resolve(path: item.path)
            loadingPath = nil
            switch result {
            case let .stream(url, headers):
                let start = fromStart ? 0 : library.startPosition(for: item.path)
                PlayerPresenter.present(item: item, url: url, headers: headers, start: start, library: library)
            case .youtube(let id):
                openYouTube(id)
            case .unavailable(let reason):
                message = reason
            }
        }
    }

    /// Živý stream (TV stanica alebo webkamera) – bez histórie a pokračovania.
    func playLive(id: String, title: String, subtitle: String,
                  resolve: @escaping () async -> (url: URL, headers: [String: String], now: String?)?) {
        guard loadingPath == nil else { return }
        loadingPath = "live:" + id
        Task {
            let r = await resolve()
            loadingPath = nil
            guard let r else {
                message = tr("Živý prenos sa nepodarilo spustiť. Môže byť dostupný len v určitej krajine alebo je práve mimo vysielania.")
                return
            }
            let item = VideoItem(path: "live:" + id, title: r.now.map { "\(title) – \($0)" } ?? title,
                                 showTitle: subtitle, source: .other)
            PlayerPresenter.present(item: item, url: r.url, headers: r.headers, start: 0, library: library)
        }
    }

    func playWebcam(_ cam: Webcam) {
        if let y = cam.youtube {
            openYouTube(y)
        } else if let h = cam.hls, let u = URL(string: h) {
            playLive(id: cam.id, title: cam.name, subtitle: cam.place) { (u, [:], nil) }
        }
    }

    func openYouTube(_ id: String) {
        let candidates = ["youtube://www.youtube.com/watch?v=\(id)", "youtube://watch/\(id)"]
        func attempt(_ i: Int) {
            guard i < candidates.count, let u = URL(string: candidates[i]) else {
                message = trf("Toto video je na YouTube. Nainštalujte si aplikáciu YouTube na Apple TV (ID videa: %@).", id)
                return
            }
            UIApplication.shared.open(u, options: [:]) { ok in
                if !ok { Task { @MainActor in attempt(i + 1) } }
            }
        }
        attempt(0)
    }
}
