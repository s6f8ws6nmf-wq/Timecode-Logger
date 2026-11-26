import AVKit
import UIKit

final class EpisodePlayerController: AVPlayerViewController {
    private(set) var episode: Episode
    private weak var store: Store?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastSaved: Double = 0

    init(episode: Episode, store: Store) {
        self.episode = episode
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func load(url: URL, start: Double) {
        let item = AVPlayerItem(url: url)
        item.externalMetadata = metadata(for: episode)
        if player == nil {
            player = AVPlayer(playerItem: item)
            addObservers()
        } else {
            player?.replaceCurrentItem(with: item)
        }
        if start > 0 {
            player?.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        player?.play()
    }

    private func addObservers() {
        guard let player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: nil, queue: .main) { [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, item != nil, item === self.player?.currentItem else { return }
                self.playNext()
            }
        }
    }

    private func saveProgress() {
        guard let item = player?.currentItem else { return }
        let pos = item.currentTime().seconds
        let dur = item.duration.seconds
        guard pos.isFinite, abs(pos - lastSaved) >= 1 else { return }
        lastSaved = pos
        store?.record(episode, position: pos, duration: dur)
    }

    private func playNext() {
        guard let store else { return }
        store.markFinished(episode)
        guard let next = store.next(after: episode) else {
            dismiss(animated: true)
            return
        }
        episode = next
        lastSaved = 0
        Task { @MainActor in
            guard let url = await Resolver.streamURL(for: next) else {
                self.dismiss(animated: true)
                return
            }
            self.load(url: url, start: 0)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            saveProgress()
            player?.pause()
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            timeObserver = nil
            endObserver = nil
        }
    }

    private func metadata(for e: Episode) -> [AVMetadataItem] {
        func item(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m.copy() as! AVMetadataItem
        }
        var desc = e.dateText
        if !e.subtitle.isEmpty { desc = "\(e.subtitle) · \(desc)" }
        return [
            item(.commonIdentifierTitle, "Hotel Paradise – \(e.title)"),
            item(.iTunesMetadataTrackSubTitle, desc),
            item(.commonIdentifierDescription, "TV JOJ · \(desc)")
        ]
    }
}

enum PlayerPresenter {
    @MainActor
    static func present(episode: Episode, url: URL, store: Store) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        let vc = EpisodePlayerController(episode: episode, store: store)
        vc.modalPresentationStyle = .fullScreen
        top.present(vc, animated: true) {
            vc.load(url: url, start: store.startPosition(for: episode))
        }
    }
}
