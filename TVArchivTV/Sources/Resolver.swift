import Foundation

enum Playback {
    case stream(URL, headers: [String: String])
    case youtube(String)
    case unavailable(String)
}

/// Prevedie stránku epizódy na tv-archiv.sk na priamy stream (HLS/MP4), ktorý vie prehrať Apple TV.
/// tv-archiv.sk video nehostí – vkladá oficiálne prehrávače televízií, z ktorých adresu zistíme tu.
enum Resolver {
    static func resolve(path: String) async -> Playback {
        let html: String
        do {
            html = try await Net.page(path)
        } catch {
            return .unavailable(error.localizedDescription)
        }

        if let yt = youTubeID(in: html, path: path) { return .youtube(yt) }

        var segment = html
        if let r = html.range(of: "id=\"tab_a_1\"") {
            segment = String(html[r.lowerBound...].prefix(8000))
        }
        var targets: [String] = []
        targets += HTML.all("<iframe[^>]*\\ssrc=\"([^\"]+)\"", in: segment).map { $0[1] }
        targets += HTML.all("window\\.open\\('([^']+)'", in: segment).map { $0[1] }
        targets += HTML.all("<(?:video|source)[^>]*\\ssrc=\"([^\"]+)\"", in: segment).map { $0[1] }
        targets = targets.filter { !$0.contains("our-ai.com") && !$0.contains("googletag") && !$0.isEmpty }

        if targets.isEmpty {
            if let direct = findStream(in: segment) { return .stream(direct, headers: [:]) }
            return .unavailable("Na stránke epizódy sa nenašlo video.")
        }

        var lastReason = "Video sa nepodarilo načítať."
        for t in targets {
            guard let url = Net.url(t) else { continue }
            switch await resolveTarget(url, depth: 0) {
            case .unavailable(let reason): lastReason = reason
            case let other: return other
            }
        }
        return .unavailable(lastReason)
    }

    // MARK: - Jednotlivé zdroje

    static func resolveTarget(_ url: URL, depth: Int) async -> Playback {
        let host = url.host?.lowercased() ?? ""
        let s = url.absoluteString
        let lower = s.lowercased()

        if lower.contains(".m3u8") || lower.hasSuffix(".mp4") { return .stream(url, headers: [:]) }

        if let id = youTubeID(fromURL: s) { return .youtube(id) }

        if ["iprima.cz", "voyo.", "netflix.", "hbomax.", "max.com", "disneyplus.", "skyshowtime."].contains(where: { host.contains($0) }) {
            return .unavailable("Tento zdroj (\(host)) vyžaduje predplatné alebo DRM a na Apple TV sa v tejto aplikácii prehrať nedá.")
        }

        do {
            if host.contains("media.joj.sk") { return try await joj(url) }
            if host.contains("stvr.sk") || host.contains("rtvs.sk") { return try await stvr(url) }
            if host.contains("ceskatelevize.cz") { return try await ceskaTelevize(url) }
            if host.hasPrefix("media.cms.") { return try await cmsEmbed(url) }
            if host.contains("markiza.sk") || host.contains("nova.cz") || host.contains("joj.sk") {
                return try await pageWithEmbed(url, depth: depth)
            }
            return try await generic(url, depth: depth)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// TV JOJ: `var src = { "hls": "…m3u8", "mp4": ["…"] }`
    static func joj(_ url: URL) async throws -> Playback {
        let html = try await Net.text(url, referer: "https://www.tv-archiv.sk/")
        let headers = ["Referer": "https://media.joj.sk/"]
        for key in ["hls", "mp4"] {
            if let v = HTML.first("\"\(key)\"\\s*:\\s*\\[\\s*\"([^\"]+)\"", in: html)
                ?? HTML.first("\"\(key)\"\\s*:\\s*\"([^\"]+)\"", in: html),
               let u = URL(string: HTML.unescapeJS(v)) {
                return .stream(u, headers: headers)
            }
        }
        if let any = findStream(in: html) { return .stream(any, headers: headers) }
        if html.lowercased().contains("not available") || html.contains("nie je dostupn") {
            return .unavailable("Video TV JOJ nie je dostupné (licencia alebo krajina).")
        }
        return .unavailable("Video TV JOJ už nie je dostupné.")
    }

    /// STVR (RTVS): /embed/archive/<relácia>/<id> → /json/archive5f.json?id=<id>
    static func stvr(_ url: URL) async throws -> Playback {
        var id = HTML.first("/embed/(?:archive|video)/\\d+/(\\d+)", in: url.absoluteString)
        if id == nil {
            let html = try await Net.text(url)
            id = HTML.first("/embed/(?:archive|video)/\\d+/(\\d+)", in: html)
                ?? HTML.first("archive5f\\.json\\?id=(\\d+)", in: html)
        }
        guard let id, let api = URL(string: "https://www.stvr.sk/json/archive5f.json?id=\(id)") else {
            return .unavailable("Video STVR sa nenašlo.")
        }
        let data = try await Net.data(api, referer: url.absoluteString)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let clip = obj?["clip"] as? [String: Any]
        let sources = clip?["sources"] as? [[String: Any]] ?? []
        let hls = sources.first { ($0["type"] as? String ?? "").contains("mpegurl") } ?? sources.first
        if let src = hls?["src"] as? String, let u = URL(string: src) {
            return .stream(u, headers: ["Referer": "https://www.stvr.sk/"])
        }
        return .unavailable("Video STVR nie je dostupné.")
    }

    /// Česká televize: ID (idec) z adresy alebo stránky → API stream-data (HLS bez DRM).
    static func ceskaTelevize(_ url: URL) async throws -> Playback {
        var idec = HTML.first("/(\\d{11,})/?(?:$|[?#])", in: url.absoluteString)
        if idec == nil {
            let html = try await Net.text(url)
            idec = HTML.first("\"idec\"\\s*:\\s*\"(\\d+)\"", in: html)
                ?? HTML.first("[?&]IDEC=([0-9A-Za-z]+)", in: html)
        }
        guard let idec else { return .unavailable("Video ČT sa nenašlo.") }
        let api = "https://api.ceskatelevize.cz/video/v1/playlist-vod/v1/stream-data/media/external/\(idec)?canPlayDrm=false&streamType=hls&quality=web&maxQualityCount=5"
        guard let apiURL = URL(string: api) else { return .unavailable("Video ČT sa nenašlo.") }
        let data = try await Net.data(apiURL, referer: "https://www.ceskatelevize.cz/")
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let streams = obj?["streams"] as? [[String: Any]],
           let s = streams.first?["url"] as? String, let u = URL(string: s) {
            return .stream(u, headers: [:])
        }
        return .unavailable("Video ČT nie je dostupné (možno je obmedzené na Česko).")
    }

    /// Markíza / Nova: prehrávač media.cms.<televízia>/embed/<id> obsahuje HLS v konfigurácii.
    static func cmsEmbed(_ url: URL) async throws -> Playback {
        let html = try await Net.text(url, referer: "https://\(url.host ?? "")/")
        if html.contains("not available in your country") {
            return .unavailable("Video je dostupné len na Slovensku / v Česku (licencia).")
        }
        let headers = ["Referer": "https://\(url.host ?? "")/"]
        if let u = findStream(in: html) { return .stream(u, headers: headers) }
        if html.lowercased().contains("drm") || html.contains("voyo") {
            return .unavailable("Toto video je chránené (Voyo / DRM) a na Apple TV sa prehrať nedá.")
        }
        return .unavailable("Video sa v prehrávači nenašlo.")
    }

    /// Stránka televízie, ktorá vkladá prehrávač cez iframe.
    static func pageWithEmbed(_ url: URL, depth: Int) async throws -> Playback {
        let html = try await Net.text(url, referer: "https://www.tv-archiv.sk/")
        if html.contains("<title>Just a moment...</title>") {
            return .unavailable("Stránka \(url.host ?? "") dočasne blokuje automatické načítanie (Cloudflare).")
        }
        if let embed = HTML.first("(https?:)?//(media\\.cms\\.[a-z.]+/embed/[A-Za-z0-9_-]+[^\"'\\s<]*)", in: html, group: 2),
           let u = URL(string: "https://" + HTML.decodeEntities(embed)) {
            return try await cmsEmbed(u)
        }
        if let embed = HTML.first("(https?:)?//(media\\.joj\\.sk/embed/[A-Za-z0-9_-]+)", in: html, group: 2),
           let u = URL(string: "https://" + embed) {
            return try await joj(u)
        }
        return try await generic(url, depth: depth, html: html)
    }

    /// Ľubovoľná stránka: priamy stream v HTML, inak vnorený iframe (max. 2 úrovne).
    static func generic(_ url: URL, depth: Int, html: String? = nil) async throws -> Playback {
        let page: String
        if let html { page = html } else { page = try await Net.text(url, referer: "https://www.tv-archiv.sk/") }
        if let u = findStream(in: page, relativeTo: url) { return .stream(u, headers: ["Referer": url.absoluteString]) }
        if let id = youTubeID(fromURL: page) { return .youtube(id) }
        if depth < 2 {
            for m in HTML.all("<iframe[^>]*\\ssrc=\"([^\"]+)\"", in: page).prefix(3) {
                guard let u = Net.url(m[1], relativeTo: url) else { continue }
                let r = await resolveTarget(u, depth: depth + 1)
                if case .unavailable = r { continue }
                return r
            }
        }
        return .unavailable("Zdroj \(url.host ?? "") sa na Apple TV prehrať nedá.")
    }

    // MARK: - Pomôcky

    static func findStream(in html: String, relativeTo: URL? = nil) -> URL? {
        let patterns = [
            "(https?:(?:\\\\?/){2}[^\"'\\s<>]+?\\.m3u8[^\"'\\s<>\\\\]*)",
            "(https?:(?:\\\\?/){2}[^\"'\\s<>]+?\\.mp4(?:\\?[^\"'\\s<>\\\\]*)?)"
        ]
        for p in patterns {
            for m in HTML.all(p, in: html) {
                let s = HTML.unescapeJS(m[1])
                if s.contains("{") || s.contains("ads") && s.contains("vast") { continue }
                if let u = URL(string: s) { return u }
            }
        }
        return nil
    }

    static func youTubeID(fromURL s: String) -> String? {
        HTML.first("(?:youtube(?:-nocookie)?\\.com/(?:embed/|watch\\?v=|v/)|youtu\\.be/)([A-Za-z0-9_-]{11})", in: s)
    }

    /// Stránky „…/reel“: zoznam YouTube videí `{id: '…', url: '/cesta', …}`.
    static func youTubeID(in html: String, path: String) -> String? {
        guard html.contains("youtube-player") || path.hasSuffix("/reel") else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: path)
        return HTML.first("\\{\\s*id:\\s*'([A-Za-z0-9_-]{11})'[^}]*url:\\s*'\(escaped)'", in: html)
            ?? HTML.first("\\{\\s*id:\\s*'([A-Za-z0-9_-]{11})'", in: html)
            ?? youTubeID(fromURL: html)
    }
}
