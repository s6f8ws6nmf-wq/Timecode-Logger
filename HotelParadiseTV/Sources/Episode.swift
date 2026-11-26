import Foundation

struct Episode: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let date: String      // yyyy-MM-dd
    let embed: String     // media.joj.sk/embed/<embed>
    let page: String      // stránka na tv-archiv.sk
    let mp4: String       // záložná priama adresa (zistená pri zostavení)
    let poster: String?

    var airDate: Date? { Episode.isoFormatter.date(from: date) }

    var dateText: String {
        guard let d = airDate else { return date }
        return Episode.displayFormatter.string(from: d)
    }

    var monthKey: String { String(date.prefix(7)) }

    var posterURL: URL? { poster.flatMap(URL.init(string:)) }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sk_SK")
        f.dateFormat = "EEEE d. M. yyyy"
        return f
    }()

    static func loadBundled() -> [Episode] {
        guard let url = Bundle.main.url(forResource: "episodes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Episode].self, from: data) else { return [] }
        return list.sorted { $0.date < $1.date }
    }
}

struct MonthGroup: Identifiable {
    let id: String
    let name: String
    let episodes: [Episode]

    private static let names = ["Január", "Február", "Marec", "Apríl", "Máj", "Jún",
                                "Júl", "August", "September", "Október", "November", "December"]

    static func group(_ episodes: [Episode]) -> [MonthGroup] {
        let dict = Dictionary(grouping: episodes, by: \.monthKey)
        return dict.keys.sorted().map { key in
            let parts = key.split(separator: "-")
            let month = parts.count == 2 ? Int(parts[1]) ?? 1 : 1
            let year = parts.first.map(String.init) ?? ""
            return MonthGroup(id: key, name: "\(names[max(0, min(11, month - 1))]) \(year)", episodes: dict[key] ?? [])
        }
    }
}
