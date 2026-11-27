import Foundation

/// Platnosť inštalácie cez Sideloadly (bezplatné Apple ID = 7 dní).
/// Presný dátum berieme z embedded.mobileprovision, ktorý pri podpise vloží Sideloadly;
/// ak chýba, počítame 7 dní od prvého spustenia tejto zostavy.
enum InstallInfo {
    static var expiration: Date? {
        if let d = provisionExpiration { return d }
        let key = "install.firstLaunch." + build
        let ud = UserDefaults.standard
        if ud.object(forKey: key) == nil { ud.set(Date(), forKey: key) }
        guard let first = ud.object(forKey: key) as? Date else { return nil }
        return first.addingTimeInterval(7 * 24 * 3600)
    }

    static var isEstimated: Bool { provisionExpiration == nil }

    private static let provisionExpiration: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        // súbor je podpísaný (CMS) – vnútri je čistý XML plist
        let raw = String(decoding: data, as: UTF8.self)
        guard let a = raw.range(of: "<?xml"), let b = raw.range(of: "</plist>") else { return nil }
        let xml = String(raw[a.lowerBound..<b.upperBound])
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    /// Zostávajúci čas v dňoch (zaokrúhlené nahor), nil ak nevieme.
    static var daysLeft: Int? {
        guard let e = expiration else { return nil }
        let s = e.timeIntervalSinceNow
        return s <= 0 ? 0 : Int((s / 86400).rounded(.up))
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    static var buildDate: String { Bundle.main.object(forInfoDictionaryKey: "TVABuildDate") as? String ?? "–" }
    static var commit: String { Bundle.main.object(forInfoDictionaryKey: "TVACommit") as? String ?? "–" }

    /// Upozornenie zobrazíme najviac raz za deň, keď ostáva 1 deň alebo menej.
    static func warningIfNeeded() -> String? {
        guard let left = daysLeft, left <= 1 else { return nil }
        let key = "install.warned"
        let today = Calendar.current.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: key) as? Date, last >= today { return nil }
        UserDefaults.standard.set(today, forKey: key)
        return left == 0
            ? tr("Platnosť aplikácie dnes vyprší. Nainštalujte ju znovu cez Sideloadly.")
            : tr("O 1 deň bude potrebné aplikáciu nainštalovať znovu cez Sideloadly.")
    }
}
