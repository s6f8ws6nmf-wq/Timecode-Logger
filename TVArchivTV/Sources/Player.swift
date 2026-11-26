import AVKit
import UIKit

/// Režim obrazu – na roztiahnutie videa, ktoré je „stlačené“ na 4:3.
enum PictureMode: String, CaseIterable {
    case original, stretch, fill

    var title: String {
        switch self {
        case .original: return "Pôvodný pomer strán"
        case .stretch: return "Roztiahnuť na 16:9"
        case .fill: return "Vyplniť obrazovku (orezať)"
        }
    }

    var icon: String {
        switch self {
        case .original: return "rectangle"
        case .stretch: return "arrow.left.and.right.square"
        case .fill: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var gravity: AVLayerVideoGravity {
        switch self {
        case .original: return .resizeAspect
        case .stretch: return .resize
        case .fill: return .resizeAspectFill
        }
    }

    /// Voľba sa pamätá pre každú reláciu zvlášť (epizódy jednej relácie majú rovnaký formát).
    static func saved(for showPath: String) -> PictureMode {
        PictureMode(rawValue: UserDefaults.standard.string(forKey: "picture." + showPath) ?? "") ?? .original
    }

    static func save(_ mode: PictureMode, for showPath: String) {
        UserDefaults.standard.set(mode.rawValue, forKey: "picture." + showPath)
    }
}

final class VideoPlayerController: AVPlayerViewController {
    private let item: VideoItem
    private weak var library: Library?
    private var timeObserver: Any?
    private var lastSaved: Double = -10
    private var pictureMode: PictureMode = .original

    init(item: VideoItem, library: Library) {
        self.item = item
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func load(url: URL, headers: [String: String], start: Double) {
        var allHeaders = headers
        allHeaders["User-Agent"] = Net.userAgent
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": allHeaders])
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.externalMetadata = metadata()
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        pictureMode = PictureMode.saved(for: item.showPath)
        applyPictureMode()
        if start > 0 { player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
        player.play()
    }

    private func applyPictureMode() {
        videoGravity = pictureMode.gravity
        transportBarCustomMenuItems = [pictureMenu()]
    }

    /// Menu „Obraz“ v lište prehrávača (potiahnutím nadol / tlačidlom v lište).
    private func pictureMenu() -> UIMenu {
        let actions = PictureMode.allCases.map { mode in
            UIAction(title: mode.title, image: UIImage(systemName: mode.icon),
                     state: mode == pictureMode ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.pictureMode = mode
                PictureMode.save(mode, for: self.item.showPath)
                self.applyPictureMode()
            }
        }
        return UIMenu(title: "Obraz", image: UIImage(systemName: "aspectratio"),
                      options: .singleSelection, children: actions)
    }

    private func saveProgress(force: Bool = false) {
        guard let current = player?.currentItem else { return }
        let pos = current.currentTime().seconds
        let dur = current.duration.seconds
        guard pos.isFinite, force || abs(pos - lastSaved) >= 4 else { return }
        lastSaved = pos
        library?.record(item, position: pos, duration: dur)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            saveProgress(force: true)
            player?.pause()
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            timeObserver = nil
        }
    }

    private func metadata() -> [AVMetadataItem] {
        func meta(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m.copy() as! AVMetadataItem
        }
        let show = item.showTitle.isEmpty ? "TV-archív" : item.showTitle
        return [
            meta(.commonIdentifierTitle, item.title),
            meta(.iTunesMetadataTrackSubTitle, show),
            meta(.commonIdentifierDescription, [show, item.source.name].filter { !$0.isEmpty }.joined(separator: " · "))
        ]
    }
}

enum PlayerPresenter {
    @MainActor
    static func present(item: VideoItem, url: URL, headers: [String: String], start: Double, library: Library) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let vc = VideoPlayerController(item: item, library: library)
        vc.modalPresentationStyle = .fullScreen
        top.present(vc, animated: true) {
            vc.load(url: url, headers: headers, start: start)
        }
    }
}
