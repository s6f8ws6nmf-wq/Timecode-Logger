import AVKit
import UIKit

final class VideoPlayerController: AVPlayerViewController {
    private let item: VideoItem
    private weak var library: Library?
    private var timeObserver: Any?
    private var lastSaved: Double = -10

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
        if start > 0 { player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
        player.play()
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
