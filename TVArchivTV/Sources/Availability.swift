import Foundation
import SwiftUI

/// Overovanie, či sa video naozaj dá prehrať (stream existuje a odpovedá).
/// Výsledky sa pamätajú 3 dni; naraz bežia najviac 4 overenia.
@MainActor
final class Availability: ObservableObject {
    @Published private(set) var status: [String: Bool] = [:]
    @Published private(set) var checking = Set<String>()

    private var queue: [String] = []
    private var running = 0
    private var stamps: [String: Double] = [:]
    private let key = "availability.v1"
    private let maxAge: Double = 3 * 24 * 3600

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] {
            let now = Date().timeIntervalSince1970
            for (path, v) in saved where v.count == 2 && now - v[1] < maxAge {
                status[path] = v[0] > 0.5
                stamps[path] = v[1]
            }
        }
    }

    /// Video vieme, že sa prehrať nedá (zdroj s predplatným alebo overenie zlyhalo).
    func isUnavailable(_ item: VideoItem) -> Bool {
        !item.source.playable || status[item.path] == false
    }

    func isVerified(_ item: VideoItem) -> Bool { status[item.path] == true }

    func check(_ item: VideoItem) {
        guard item.source.playable, status[item.path] == nil, !checking.contains(item.path) else { return }
        checking.insert(item.path)
        queue.append(item.path)
        pump()
    }

    private func pump() {
        while running < 4, !queue.isEmpty {
            let path = queue.removeFirst()
            running += 1
            Task {
                let ok = await Resolver.verify(path: path)
                self.status[path] = ok
                self.stamps[path] = Date().timeIntervalSince1970
                self.checking.remove(path)
                self.running -= 1
                self.save()
                self.pump()
            }
        }
    }

    // MARK: Relácie bez videí (zapamätané po otvorení detailu)

    @Published private(set) var emptyShows: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "emptyShows.v1") ?? [])

    func isEmptyShow(_ show: ShowCard) -> Bool {
        show.hasVideo == false || emptyShows.contains(show.path)
    }

    func setShow(_ path: String, empty: Bool) {
        guard emptyShows.contains(path) != empty else { return }
        if empty { emptyShows.insert(path) } else { emptyShows.remove(path) }
        UserDefaults.standard.set(Array(emptyShows), forKey: "emptyShows.v1")
    }

    func clear() {
        emptyShows = []
        UserDefaults.standard.removeObject(forKey: "emptyShows.v1")
        status = [:]
        stamps = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save() {
        var out: [String: [Double]] = [:]
        for (p, ok) in status { out[p] = [ok ? 1 : 0, stamps[p] ?? Date().timeIntervalSince1970] }
        UserDefaults.standard.set(out, forKey: key)
    }
}

enum EpisodeOrder {
    /// Dátum z názvu („… (13.03.2012)“) ako číslo yyyymmdd.
    static func dateKey(_ item: VideoItem) -> Int? {
        guard let d = item.dateText else { return nil }
        let parts = d.replacingOccurrences(of: " ", with: "").split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[2] * 10000 + parts[1] * 100 + parts[0]
    }

    /// Zoradí podľa dátumu; ak dátumy chýbajú, otočí pôvodné poradie stránky (tá je od najnovšieho).
    static func sorted(_ items: [VideoItem], oldestFirst: Bool) -> [VideoItem] {
        let keys = items.map(dateKey)
        let dated = keys.compactMap { $0 }.count
        if dated >= max(1, items.count * 8 / 10) {
            let indexed = Array(zip(items.indices, items))
            let s = indexed.sorted { a, b in
                let ka = keys[a.0] ?? (oldestFirst ? Int.max : Int.min)
                let kb = keys[b.0] ?? (oldestFirst ? Int.max : Int.min)
                if ka != kb { return oldestFirst ? ka < kb : ka > kb }
                return oldestFirst ? a.0 > b.0 : a.0 < b.0
            }
            return s.map { $0.1 }
        }
        return oldestFirst ? items.reversed() : items
    }
}

/// Zoradenie zoznamu (Iba dostupný obsah sa nastavuje v Nastaveniach).
struct FilterMenu: View {
    @AppStorage("filter.onlyAvailable") private var onlyAvailable = false
    @AppStorage("filter.oldestFirst") private var oldestFirst = false
    var shown: Int? = nil
    var total: Int? = nil

    var body: some View {
        HStack(spacing: 20) {
            Menu {
                Picker(tr("Zoradiť"), selection: $oldestFirst) {
                    Label(tr("Od najnovšieho"), systemImage: "arrow.down").tag(false)
                    Label(tr("Od najstaršieho"), systemImage: "arrow.up").tag(true)
                }
            } label: {
                Label(tr("Zoradiť"), systemImage: "arrow.up.arrow.down")
                    .lineLimit(1)
                    .fixedSize()
            }
            .menuStyle(.button)
            .glassButton(prominent: oldestFirst)

            VStack(alignment: .leading, spacing: 2) {
                Text(oldestFirst ? tr("Od najstaršieho") : tr("Od najnovšieho"))
                if onlyAvailable {
                    if let shown, let total {
                        Text(trf("Iba dostupné · %d z %d", shown, total))
                    } else {
                        Text(tr("Iba dostupné"))
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
    }
}
