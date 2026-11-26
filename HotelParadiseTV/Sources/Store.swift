import Foundation
import SwiftUI

struct WatchState: Codable, Equatable {
    var position: Double
    var duration: Double

    var fraction: Double { duration > 0 ? min(1, position / duration) : 0 }
    var finished: Bool { fraction >= 0.95 }
}

@MainActor
final class Store: ObservableObject {
    let episodes: [Episode]
    let months: [MonthGroup]

    @Published private(set) var watch: [String: WatchState] = [:]
    @Published private(set) var lastID: String?
    @Published var loadingID: String?
    @Published var errorText: String?

    private let defaults = UserDefaults.standard
    private let watchKey = "watchState.v1"
    private let lastKey = "lastEpisode.v1"

    init() {
        episodes = Episode.loadBundled()
        months = MonthGroup.group(episodes)
        if let data = defaults.data(forKey: watchKey),
           let saved = try? JSONDecoder().decode([String: WatchState].self, from: data) {
            watch = saved
        }
        lastID = defaults.string(forKey: lastKey)
    }

    func state(for e: Episode) -> WatchState? { watch[e.id] }

    func next(after e: Episode) -> Episode? {
        guard let i = episodes.firstIndex(of: e), i + 1 < episodes.count else { return nil }
        return episodes[i + 1]
    }

    /// Epizóda pre tlačidlo „Pokračovať“: rozpozeraná, alebo nasledujúca po dopozeranej.
    var continueEpisode: Episode? {
        guard let id = lastID, let e = episodes.first(where: { $0.id == id }) else { return nil }
        if let s = watch[id], s.finished { return next(after: e) }
        return e
    }

    func record(_ e: Episode, position: Double, duration: Double) {
        guard duration.isFinite, duration > 0, position.isFinite else { return }
        watch[e.id] = WatchState(position: position, duration: duration)
        lastID = e.id
        persist()
    }

    func markFinished(_ e: Episode) {
        let d = watch[e.id]?.duration ?? 1
        watch[e.id] = WatchState(position: d, duration: d)
        lastID = e.id
        persist()
    }

    func resetProgress(_ e: Episode) {
        watch[e.id] = nil
        persist()
    }

    func startPosition(for e: Episode) -> Double {
        guard let s = watch[e.id], !s.finished, s.position > 10 else { return 0 }
        return s.position - 5
    }

    func play(_ e: Episode) {
        guard loadingID == nil else { return }
        loadingID = e.id
        Task {
            let url = await Resolver.streamURL(for: e)
            loadingID = nil
            guard let url else {
                errorText = "Video sa nepodarilo načítať. Skontrolujte pripojenie k internetu."
                return
            }
            PlayerPresenter.present(episode: e, url: url, store: self)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(watch) { defaults.set(data, forKey: watchKey) }
        defaults.set(lastID, forKey: lastKey)
    }
}
