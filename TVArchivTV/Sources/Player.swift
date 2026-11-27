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

/// Posun zvuku voči obrazu (v sekundách), pamätá sa pre každú reláciu.
enum AudioSync {
    static func saved(for showPath: String) -> Double {
        UserDefaults.standard.double(forKey: "avsync." + showPath)
    }

    static func save(_ value: Double, for showPath: String) {
        UserDefaults.standard.set(value, forKey: "avsync." + showPath)
    }
}

final class VideoPlayerController: AVPlayerViewController {
    private let item: VideoItem
    private weak var library: Library?
    private var timeObserver: Any?
    private var lastSaved: Double = -10
    private var pictureMode: PictureMode = .original

    // Synchronizácia zvuku: pri posune ≠ 0 hrá obraz hlavný prehrávač (stlmený)
    // a zvuk druhý prehrávač, posunutý o audioOffset sekúnd (kladné = zvuk neskôr).
    private var streamURL: URL?
    private var streamHeaders: [String: String] = [:]
    private var audioOffset: Double = 0
    private var audioPlayer: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var jumpObserver: NSObjectProtocol?
    private var driftTimer: Timer?

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
        streamURL = url
        streamHeaders = allHeaders
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
        audioOffset = AudioSync.saved(for: item.showPath)
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.resyncAudio() } }
        }
        jumpObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.timeJumpedNotification,
                                                              object: playerItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resyncAudio() }
        }
        configureAudioSync()
        player.play()
    }

    private func applyPictureMode() {
        videoGravity = pictureMode.gravity
        rebuildMenus()
    }

    private func rebuildMenus() {
        transportBarCustomMenuItems = [pictureMenu(), audioSyncMenu()]
    }

    // MARK: - Synchronizácia zvuku a obrazu

    private func configureAudioSync() {
        guard let player else { return }
        if abs(audioOffset) < 0.001 {
            stopAudioPlayer()
            player.isMuted = false
            return
        }
        if audioPlayer == nil, let url = streamURL {
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": streamHeaders])
            let item = AVPlayerItem(asset: asset)
            item.preferredPeakBitRate = 1 // pri HLS stačí najnižšia kvalita – berieme z nej len zvuk
            let a = AVPlayer(playerItem: item)
            a.automaticallyWaitsToMinimizeStalling = false
            audioPlayer = a
            driftTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkDrift() }
            }
        }
        player.isMuted = true
        resyncAudio()
    }

    private func stopAudioPlayer() {
        driftTimer?.invalidate()
        driftTimer = nil
        audioPlayer?.pause()
        audioPlayer = nil
    }

    /// Nastaví zvukový prehrávač na čas obrazu mínus posun a spustí ho v rovnakom okamihu.
    private func resyncAudio() {
        guard let player, let audio = audioPlayer else { return }
        let playing = player.timeControlStatus == .playing
        let lead = 0.25
        let videoNow = player.currentTime().seconds
        guard videoNow.isFinite else { return }
        if !playing {
            audio.pause()
            let t = max(0, videoNow - audioOffset)
            audio.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        let rate = player.rate > 0 ? player.rate : 1
        let target = videoNow + lead * Double(rate) - audioOffset
        if target < 0 {
            // zvuk má začať až neskôr, než je začiatok záznamu
            audio.pause()
            audio.seek(to: .zero)
            DispatchQueue.main.asyncAfter(deadline: .now() + (-target)) { [weak self] in
                MainActor.assumeIsolated { self?.resyncAudio() }
            }
            return
        }
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(seconds: lead, preferredTimescale: 1_000_000))
        audio.setRate(rate, time: CMTime(seconds: target, preferredTimescale: 600), atHostTime: host)
    }

    private func checkDrift() {
        guard let player, let audio = audioPlayer, player.timeControlStatus == .playing else { return }
        let expected = player.currentTime().seconds - audioOffset
        let actual = audio.currentTime().seconds
        guard expected.isFinite, actual.isFinite else { return }
        if audio.timeControlStatus != .playing || abs(actual - expected) > 0.06 {
            resyncAudio()
        }
    }

    private func setAudioOffset(_ value: Double) {
        audioOffset = (value * 1000).rounded() / 1000
        AudioSync.save(audioOffset, for: item.showPath)
        configureAudioSync()
        rebuildMenus()
    }

    private func audioSyncMenu() -> UIMenu {
        let ms = Int((audioOffset * 1000).rounded())
        let current = ms == 0 ? "bez posunu" : (ms > 0 ? "zvuk neskôr o \(ms) ms" : "zvuk skôr o \(-ms) ms")
        let step: [UIMenuElement] = [
            UIAction(title: "Posunúť zvuk neskôr (+50 ms)", subtitle: "keď zvuk predbieha obraz",
                     image: UIImage(systemName: "plus.circle")) { [weak self] _ in
                guard let self else { return }
                self.setAudioOffset(self.audioOffset + 0.05)
            },
            UIAction(title: "Posunúť zvuk skôr (−50 ms)", subtitle: "keď zvuk mešká za obrazom",
                     image: UIImage(systemName: "minus.circle")) { [weak self] _ in
                guard let self else { return }
                self.setAudioOffset(self.audioOffset - 0.05)
            }
        ]
        let presets: [UIMenuElement] = [-1.0, -0.5, -0.3, -0.2, -0.1, 0, 0.1, 0.2, 0.3, 0.5, 1.0].map { v in
            let vms = Int((v * 1000).rounded())
            let title = vms == 0 ? "Bez posunu" : (vms > 0 ? "Zvuk neskôr o \(vms) ms" : "Zvuk skôr o \(-vms) ms")
            return UIAction(title: title, state: vms == ms ? .on : .off) { [weak self] _ in self?.setAudioOffset(v) }
        }
        return UIMenu(title: "Synchronizácia zvuku", subtitle: current, image: UIImage(systemName: "timer"), children: [
            UIMenu(title: "", options: .displayInline, children: step),
            UIMenu(title: "Predvoľby", image: UIImage(systemName: "list.bullet"), children: presets)
        ])
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
        return UIMenu(title: "Obraz", subtitle: pictureMode.title, image: UIImage(systemName: "aspectratio"),
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
            library?.refreshTopShelf()
            player?.pause()
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            timeObserver = nil
            statusObservation = nil
            if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver) }
            jumpObserver = nil
            stopAudioPlayer()
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
