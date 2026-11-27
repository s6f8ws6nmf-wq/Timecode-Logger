import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.40, green: 0.78, blue: 1.0)
    static let tileSize = CGSize(width: 400, height: 225)
    static let posterGradient = LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
}

// MARK: - Liquid Glass (tvOS 26) so záložným materiálom pre staršie systémy

extension View {
    /// Sklenený panel.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 36, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(tvOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }

    /// Sklenená kapsula (štítky, odznaky).
    @ViewBuilder
    func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(tvOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
        #else
        self.background(.ultraThinMaterial, in: Capsule())
        #endif
    }

    /// Sklenené tlačidlo (prominent = farebné hlavné tlačidlo).
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(tvOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            self.buttonStyle(.bordered)
        }
        #else
        self.buttonStyle(.bordered)
        #endif
    }
}

/// Zoskupenie sklenených prvkov (na tvOS 26 sa navzájom „roztekajú“).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(tvOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Pozadie podľa práve vybranej položky (ako v aplikácii Apple TV)

@MainActor
final class Backdrop: ObservableObject {
    @Published var urls: [URL] = []
    func show(_ urls: [URL]) {
        guard !urls.isEmpty, urls != self.urls else { return }
        self.urls = urls
    }
}

struct BackdropView: View {
    @EnvironmentObject private var backdrop: Backdrop

    var body: some View {
        ZStack {
            Color.black
            RemoteImage(urls: backdrop.urls, placeholder: false)
                .blur(radius: 40)
                .opacity(0.55)
                .scaleEffect(1.15)
                .clipped()
                .animation(.easeInOut(duration: 0.6), value: backdrop.urls)
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.75), .black],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Keď je prvok vybraný (zameraný), nastaví pozadie obrazovky.
private struct BackdropReporter: ViewModifier {
    @Environment(\.isFocused) private var focused
    @EnvironmentObject private var backdrop: Backdrop
    let urls: [URL]

    func body(content: Content) -> some View {
        content.onChange(of: focused) { _, now in
            if now { backdrop.show(urls) }
        }
    }
}

extension View {
    func reportsBackdrop(_ urls: [URL]) -> some View { modifier(BackdropReporter(urls: urls)) }
}

// MARK: - Obrázky (cez vlastnú session, aby prešli firewallom stránky)

actor ImageStore {
    static let shared = ImageStore()
    private var cache: [URL: UIImage] = [:]
    private var missing = Set<URL>()
    private var order: [URL] = []

    func image(for url: URL) async -> UIImage? {
        if let img = cache[url] { return img }
        if missing.contains(url) { return nil }
        guard let data = try? await Net.data(url, referer: Net.base.absoluteString + "/"),
              let img = UIImage(data: data) else {
            missing.insert(url)
            return nil
        }
        cache[url] = img
        order.append(url)
        if order.count > 400 { cache[order.removeFirst()] = nil }
        return img
    }

    /// Prvý obrázok zo zoznamu, ktorý existuje.
    func firstImage(_ urls: [URL]) async -> UIImage? {
        for u in urls {
            if let img = await image(for: u) { return img }
        }
        return nil
    }
}

struct RemoteImage: View {
    let urls: [URL]
    var placeholder = true
    @State private var image: UIImage?

    var body: some View {
        // Color.clear určí veľkosť (presne ponúknutý priestor); obrázok sa len prekryje a oreže,
        // takže „scaledToFill“ nikdy nerozšíri rozloženie za okraj obrazovky.
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .transition(.opacity)
                } else if placeholder {
                    ZStack {
                        LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "play.tv")
                            .font(.system(size: 54, weight: .light))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }
            .clipped()
            .task(id: urls) {
                let img = await ImageStore.shared.firstImage(urls)
                withAnimation(.easeOut(duration: 0.25)) { image = img }
            }
    }
}

// MARK: - Stavy načítania

enum LoadState<T> {
    case loading
    case loaded(T)
    case failed(String)
}

struct LoadingView: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 64)).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(tr("Skúsiť znova"), action: retry).glassButton()
        }
        .padding(60)
        .glassPanel()
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

struct SourceBadge: View {
    let source: VideoSource
    var body: some View {
        if !source.name.isEmpty {
            Label(source.name, systemImage: source.playable ? (source == .youtube ? "play.rectangle" : "play.fill") : "lock.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassCapsule()
                .foregroundStyle(source.playable ? .primary : .secondary)
        }
    }
}

// MARK: - Odznaky na dlaždiciach (logo stanice, typ obsahu)

enum ChannelName {
    /// Čitateľný názov stanice z názvu súboru loga („joj_play.png“ → „JOJ Play“).
    static func from(logo: String?) -> String? {
        guard let logo, !logo.isEmpty else { return nil }
        let stem = logo.lowercased().components(separatedBy: ".").first ?? logo
        let map: [(String, String)] = [
            ("joj_play", "JOJ Play"), ("joj_krimi", "JOJ Krimi"), ("jojplus", "JOJ Plus"), ("joj", "JOJ"),
            ("dajto", "Dajto"), ("wau", "WAU"), ("markiza", "Markíza"), ("doma", "Doma"),
            ("nova", "Nova"), ("stvr", "STVR"), ("rtvs", "RTVS"), ("jednotka", "Jednotka"), ("dvojka", "Dvojka"),
            ("lux", "TV Lux"), ("prima", "Prima"), ("ct", "ČT"), ("ta3", "TA3"), ("yt", "YouTube"), ("ocko", "Óčko")
        ]
        for (k, v) in map where stem.hasPrefix(k) { return v }
        return stem.uppercased()
    }
}

/// Logo televízie – malá matne biela kapsula; bez obrázka len decentný názov.
struct ChannelBadge: View {
    let logo: String?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 22)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.92), in: Capsule())
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            } else if let name = ChannelName.from(logo: logo) {
                Text(name.uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassCapsule()
            }
        }
        .transition(.opacity)
        .task(id: logo) {
            guard let logo, let u = Net.url("/images/tv/logo/" + logo) else { return }
            let img = await ImageStore.shared.image(for: u)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}

/// Typ obsahu – malý sklenený kruh s bielym symbolom.
struct KindBadge: View {
    let kind: ContentKind

    var body: some View {
        Image(systemName: kind.icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .glassPanel(cornerRadius: 20)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .accessibilityLabel(kind.label)
    }
}

/// Odznaky v rohoch dlaždice.
struct TileBadges: View {
    var logo: String?
    var kind: ContentKind?

    var body: some View {
        HStack(alignment: .top) {
            ChannelBadge(logo: logo)
            Spacer(minLength: 8)
            if let kind { KindBadge(kind: kind) }
        }
        .padding(14)
    }
}
