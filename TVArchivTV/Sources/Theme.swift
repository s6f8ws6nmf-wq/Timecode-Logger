import SwiftUI
import UIKit

enum Theme {
    static let gold = Color(red: 118 / 255, green: 105 / 255, blue: 70 / 255)
    static let blue = Color(red: 26 / 255, green: 95 / 255, blue: 180 / 255)
    static let ink = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
    static let background = LinearGradient(colors: [Color(white: 0.99), Color(red: 0.94, green: 0.93, blue: 0.90)],
                                            startPoint: .top, endPoint: .bottom)

    /// Písmo Playfair Display SC (ako logo stránky), so záložným systémovým písmom.
    static func serif(_ size: CGFloat, bold: Bool = true) -> Font {
        let name = bold ? "PlayfairDisplaySC-Bold" : "PlayfairDisplaySC-Regular"
        if UIFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: bold ? .bold : .regular, design: .serif)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.serif(44))
            .foregroundStyle(Theme.gold)
    }
}

struct SourceBadge: View {
    let source: VideoSource
    var body: some View {
        if !source.name.isEmpty {
            Text(source.name)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(source.playable ? Theme.blue.opacity(0.15) : Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(source.playable ? Theme.blue : .gray)
        }
    }
}

// MARK: - Obrázky (cez vlastnú session, aby prešli firewallom stránky)

actor ImageStore {
    static let shared = ImageStore()
    private var cache: [URL: UIImage] = [:]
    private var order: [URL] = []

    func image(for url: URL) async -> UIImage? {
        if let img = cache[url] { return img }
        guard let data = try? await Net.data(url, referer: Net.base.absoluteString + "/"),
              let img = UIImage(data: data) else { return nil }
        cache[url] = img
        order.append(url)
        if order.count > 300 { cache[order.removeFirst()] = nil }
        return img
    }
}

struct RemoteImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.92), Color(white: 0.82)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "play.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Theme.blue.opacity(0.35))
            }
        }
        .task(id: url) {
            image = nil
            if let url { image = await ImageStore.shared.image(for: url) }
        }
    }
}

// MARK: - Spoločné stavy načítania

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
        VStack(spacing: 24) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 60)).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center)
            Button("Skúsiť znova", action: retry)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}
