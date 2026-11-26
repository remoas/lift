import SwiftUI
import AVKit
import LiftCore

/// Loads vendored CC0 media from the app bundle (ExerciseMedia/…). Never the network.
enum MediaStore {
    private static let cache = NSCache<NSString, UIImage>()

    static func url(_ relative: String) -> URL? {
        Bundle.main.url(forResource: "ExerciseMedia/" + relative, withExtension: nil)
    }

    /// "video/leg-press.mp4" → "posters/leg-press-thumb.jpg" (or "-end.jpg").
    static func posterURL(_ videoFile: String, kind: String) -> URL? {
        let name = ((videoFile as NSString).lastPathComponent as NSString).deletingPathExtension
        return url("posters/\(name)-\(kind).jpg")
    }

    /// Downsampled image for lists; full images are decoded only on detail.
    static func thumbnail(for media: ExerciseMedia, side: CGFloat) async -> UIImage? {
        let key = "\(media.files.first ?? "")@\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let scale = await MainActor.run { UIScreen.main.scale }
        let size = CGSize(width: side * scale, height: side * scale)
        let image: UIImage?
        if let still = media.thumbnail, let url = url(still) {
            image = await UIImage(contentsOfFile: url.path)?.byPreparingThumbnail(ofSize: size)
        } else if case .video(let file) = media, let poster = posterURL(file, kind: "thumb") {
            // Bundled poster (frame at 1 s). The simulator's video decoder can return
            // a solid green frame from AVAssetImageGenerator, so never rely on it here.
            image = await UIImage(contentsOfFile: poster.path)?.byPreparingThumbnail(ofSize: size)
        } else if case .video(let file) = media, let url = url(file) {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = size
            image = (try? await gen.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image).map(UIImage.init(cgImage:))
        } else {
            image = nil
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// List tile: the exercise's still, or a muscle-region glyph on a tinted tile.
struct ExerciseThumb: View {
    let mediaRef: String?
    let primary: [MuscleGroup]
    var side: CGFloat = Theme.Size.thumb

    @State private var image: UIImage?

    private var media: ExerciseMedia? { mediaRef.flatMap(ExerciseMedia.init(key:)) }

    var body: some View {
        ZStack {
            RoundedRectangle.smooth(Theme.Radius.control).fill(Theme.Colors.accentSoft)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: Theme.Symbols.region(primary.first?.region))
                    .font(.system(size: side * 0.45, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.continuous(Theme.Radius.control))
        .accessibilityHidden(true)
        .task(id: mediaRef) {
            guard let media else { image = nil; return }
            image = await MediaStore.thumbnail(for: media, side: side)
        }
    }
}

/// §3.8 exercise media header (frames 24a–24e). Inset 20, radius 16, 3:2.
/// Collapses entirely with no media or after 8 s without it (AC 49–54).
struct ExerciseMediaHeader: View {
    let media: ExerciseMedia
    /// Reports whether the header is showing, so the screen can move the range control.
    var onVisibilityChange: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: Phase = .loading
    @State private var start: UIImage?
    @State private var end: UIImage?
    @State private var showEnd = false
    @State private var drag: CGFloat?
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var playing = false
    @State private var poster: UIImage?

    enum Phase: Equatable { case loading, ready, collapsed }

    private var reduceMotion: Bool {
        #if DEBUG
        if Fixtures.mediaMode == .reduceMotion { return true }
        #endif
        return systemReduceMotion
    }

    var body: some View {
        Group {
            if phase != .collapsed {
                // The 3:2 box sets the size; content can never widen it, so the
                // radius-16 clip and the Play pill stay on the media (QA 5).
                Color.clear
                    .aspectRatio(Theme.Size.mediaAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        ZStack {
                            Theme.Colors.bgSunken
                            if phase == .loading { MediaSkeleton(animated: !reduceMotion) } else { content }
                        }
                    }
                    .clipShape(.continuous(Theme.Radius.media))
                .contentShape(.continuous(Theme.Radius.media))
            }
        }
        .task(id: media) { await load() }
        .onChange(of: phase) { _, p in onVisibilityChange(p != .collapsed) }
        .onChange(of: scenePhase) { _, s in if s != .active { pause() } }
        .onDisappear { pause() }   // scrolled off-screen (List rows are lazy) or navigated away
    }

    // MARK: Loading

    private func load() async {
        phase = .loading
        #if DEBUG
        if Fixtures.mediaMode == .loading { return }        // frame 24d holds the skeleton
        #endif
        // Collapse as if there were no media after 8 s (AC 52/53).
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Theme.Size.mediaLoadTimeout))
            if !Task.isCancelled, phase == .loading { phase = .collapsed }
        }
        let ok: Bool
        switch media {
        case .stills(let a, let b):
            async let s = decode(a), e = decode(b)
            (start, end) = await (s, e)
            ok = start != nil && end != nil
        case .hold(let a):
            start = await decode(a); end = start
            ok = start != nil
        case .video(let file):
            ok = await prepareVideo(file)
        }
        timeout.cancel()
        guard phase == .loading else { return }
        withAnimation(reduceMotion ? nil : Theme.Motion.crossfade) { phase = ok ? .ready : .collapsed }
        if ok, case .video = media, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Wait for the row → detail zoom to settle (springZoom ≈ 0.5 s) before autoplay.
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, phase == .ready else { return }
            play()
        }
    }

    private func decode(_ file: String) async -> UIImage? {
        guard let url = MediaStore.url(file) else { return nil }
        return await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
    }

    /// Video-only composition: the audio track is stripped, so there is no
    /// audio and the shared audio session is never touched (AC 50).
    private func prepareVideo(_ file: String) async -> Bool {
        guard let url = MediaStore.url(file) else { return false }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration) else { return false }
        let comp = AVMutableComposition()
        guard let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? v.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)) != nil else { return false }
        v.preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        let q = AVQueuePlayer()
        q.isMuted = true
        q.preventsDisplaySleepDuringVideoPlayback = false
        q.audiovisualBackgroundPlaybackPolicy = .pauses
        looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(asset: comp))
        player = q
        // End frame for Reduce Motion (it rests on the End still): bundled poster first.
        if let url = MediaStore.posterURL(file, kind: "end"),
           let img = await Task.detached(priority: .userInitiated, operation: { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }).value {
            poster = img
            return true
        }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1200, height: 1200)
        let endTime = CMTimeSubtract(duration, CMTime(value: 1, timescale: 10))
        poster = (try? await gen.image(at: endTime).image).map(UIImage.init(cgImage:))
        return true
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch media {
        case .stills, .hold:
            stills
        case .video:
            video
        }
    }

    private var stills: some View {
        GeometryReader { geo in
            let progress: CGFloat = drag.map { min(max($0, 0), 1) } ?? (showEnd ? 1 : 0)
            ZStack(alignment: .bottom) {
                image(start)
                image(end).opacity(progress)
                if case .stills = media {
                    StillsPill(showEnd: Binding(get: { showEnd }, set: { set($0) }))
                        .padding(.bottom, 10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { set(!showEnd) }
            .gesture(DragGesture(minimumDistance: 8).onChanged { g in
                guard case .stills = media else { return }
                let base: CGFloat = showEnd ? 1 : 0
                drag = base + g.translation.width / max(geo.size.width * 0.6, 1) * (showEnd ? 1 : 1)
            }.onEnded { _ in
                let target = (drag ?? 0) >= 0.5
                withAnimation(reduceMotion ? Theme.Motion.crossfade : .snappy) { drag = nil; set(target) }
            })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Demonstration, \(showEnd ? "end" : "start") position")
    }

    private func set(_ end: Bool) {
        guard end != showEnd else { return }
        Haptics.step()
        withAnimation(Theme.Motion.crossfade) { showEnd = end }
    }

    private var video: some View {
        ZStack(alignment: .bottomLeading) {
            if let player {
                PlayerLayerView(player: player)
                    .opacity(reduceMotion && !playing ? 0 : 1)
            }
            if reduceMotion, !playing {
                image(poster)
            }
            Button(action: toggle) {
                if reduceMotion && !playing {
                    Label("Play", systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.s4)
                        .frame(minHeight: Theme.Size.hit)
                        .background(.ultraThinMaterial, in: Capsule())
                } else {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: Theme.Size.hit, height: Theme.Size.hit)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.leading, 10)
            .padding(.bottom, 10)
            .accessibilityLabel(playing ? "Pause demonstration" : "Play demonstration")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    private func image(_ img: UIImage?) -> some View {
        Group {
            if let img { Image(uiImage: img).resizable().scaledToFill() } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: Playback

    private func toggle() { playing ? pause() : play() }

    private func play() {
        guard let player else { return }
        if reduceMotion {
            // Plays the loop once, then rests on the End still.
            looper?.disableLooping()
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main) { _ in
                MainActor.assumeIsolated { withAnimation(Theme.Motion.crossfade) { playing = false } }
            }
            player.seek(to: .zero)
        }
        player.play()
        withAnimation(Theme.Motion.crossfade) { playing = true }
    }

    private func pause() {
        player?.pause()
        playing = false
    }
}

/// "Start | End" glass pill, 44 pt tall, each segment ≥ 64 pt.
private struct StillsPill: View {
    @Binding var showEnd: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            segment("Start", selected: !showEnd) { showEnd = false }
            segment("End", selected: showEnd) { showEnd = true }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(minWidth: 64, minHeight: Theme.Size.hit - 8)
                .background {
                    if selected { Capsule().fill(Theme.Colors.bgRaised).matchedGeometryEffect(id: "sel", in: ns) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Skeleton at the final 3:2 size; a soft shimmer ≤ 1.2 s per cycle, static under Reduce Motion.
private struct MediaSkeleton: View {
    let animated: Bool
    @State private var x: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Theme.Colors.bgSunken
                .overlay {
                    if animated {
                        LinearGradient(colors: [.clear, Theme.Colors.bgRaised.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: x * geo.size.width)
                    }
                }
                .clipped()
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { x = 1 }
        }
        .accessibilityLabel("Loading demonstration")
    }
}

/// AVPlayerLayer without system controls (no route/volume UI).
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.player = player
        return v
    }
    func updateUIView(_ v: LayerView, context: Context) { v.playerLayer.player = player }
}
