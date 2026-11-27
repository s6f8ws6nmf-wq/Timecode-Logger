import Foundation

/// HTTP klient. tv-archiv.sk má firewall, ktorý odmieta požiadavky bez „prehliadačových“ hlavičiek.
enum Net {
    static let base = URL(string: "https://www.tv-archiv.sk")!
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "sk-SK,sk;q=0.9,cs;q=0.8"
        ]
        c.timeoutIntervalForRequest = 25
        c.urlCache = URLCache(memoryCapacity: 30_000_000, diskCapacity: 300_000_000)
        return URLSession(configuration: c)
    }()

    enum NetError: LocalizedError {
        case http(Int)
        case blocked
        case badURL

        var errorDescription: String? {
            switch self {
            case .http(let code): return "Server vrátil chybu \(code)."
            case .blocked: return "Stránka dočasne odmietla pripojenie. Skúste to o chvíľu znova."
            case .badURL: return "Neplatná adresa."
            }
        }
    }

    /// Absolútna URL z cesty („/relacia“), adresy bez schémy („//host/…“) alebo plnej adresy.
    static func url(_ s: String, relativeTo: URL = base) -> URL? {
        let t = HTML.decodeEntities(s.trimmingCharacters(in: .whitespacesAndNewlines))
        if t.hasPrefix("//") { return URL(string: "https:" + t) }
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            return URL(string: t) ?? URL(string: t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t)
        }
        return URL(string: t, relativeTo: relativeTo)?.absoluteURL
            ?? URL(string: t.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? t, relativeTo: relativeTo)?.absoluteURL
    }

    static func data(_ url: URL, referer: String? = nil, headers: [String: String] = [:]) async throws -> Data {
        var req = URLRequest(url: url)
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 403 || http.statusCode == 466 { throw NetError.blocked }
            throw NetError.http(http.statusCode)
        }
        return data
    }

    static func text(_ url: URL, referer: String? = nil, headers: [String: String] = [:]) async throws -> String {
        let d = try await data(url, referer: referer, headers: headers)
        let s = String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)
        if s.contains("<title>Access Forbidden</title>") { throw NetError.blocked }
        return s
    }

    static func page(_ path: String) async throws -> String {
        guard let u = url(path) else { throw NetError.badURL }
        return try await text(u, referer: base.absoluteString + "/")
    }

    static func postForm(_ path: String, fields: [(String, String)], referer: String) async throws -> Data {
        guard let u = url(path) else { throw NetError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NetError.http(http.statusCode)
        }
        return data
    }
}

/// Jednoduché pomôcky na čítanie HTML cez regulárne výrazy.
enum HTML {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        cache[pattern] = r
        return r
    }

    /// Všetky zhody; pre každú zoznam skupín (index 0 = celá zhoda).
    static func all(_ pattern: String, in s: String) -> [[String]] {
        guard let re = regex(pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    static func first(_ pattern: String, in s: String, group: Int = 1) -> String? {
        guard let re = regex(pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group, m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    static func remove(_ pattern: String, from s: String) -> String {
        guard let re = regex(pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
    }

    /// Odstráni zhody bez náhrady medzerou.
    static func strip(_ pattern: String, from s: String) -> String {
        guard let re = regex(pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
    }

    /// HTML → čistý text.
    static func text(_ html: String) -> String {
        var s = remove("<script.*?</script>", from: html)
        s = remove("<br\\s*/?>", from: s)
        s = strip("</?(?:span|b|strong|em|i|u|a|small|font|mark)\\b[^>]*>", from: s)
        s = remove("<[^>]+>", from: s)
        s = decodeEntities(s)
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named: [String: String] = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                                       "&apos;": "'", "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—",
                                       "&hellip;": "…", "&bdquo;": "„", "&ldquo;": "“", "&rdquo;": "”"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        for m in all("&#(x?)([0-9a-fA-F]+);", in: out) {
            let radix = m[1].isEmpty ? 10 : 16
            if let code = UInt32(m[2], radix: radix), let scalar = Unicode.Scalar(code) {
                out = out.replacingOccurrences(of: m[0], with: String(Character(scalar)))
            }
        }
        return out
    }

    /// Zruší JSON escapovanie lomiek a unicode (\/, &).
    static func unescapeJS(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\\/", with: "/")
        for m in all("\\\\u([0-9a-fA-F]{4})", in: out) {
            if let code = UInt32(m[1], radix: 16), let scalar = Unicode.Scalar(code) {
                out = out.replacingOccurrences(of: m[0], with: String(Character(scalar)))
            }
        }
        return decodeEntities(out)
    }
}
