import SwiftUI
import AVKit
import LiftCore

/// Loads vendored CC0 media from the app bundle (ExerciseMedia/…). Never the network.
enum MediaStore {
    private static let cache = NSCache<NSString, UIImage>()

    static func url(_ relative: String) -> URL? {
        Bundle.main.url(forResource: "ExerciseMedia/" + relative, withExtension: nil)
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
            Shape.continuous(Theme.Radius.control).fill(Theme.Colors.accentSoft)
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

/// Exercise detail header: start → end crossfade for stills, a loop for video.
/// Always muted, never taller than 4:3 or `mediaMaxHeight`, and a still under
/// Reduce Motion (videos show their first frame).
struct ExerciseMediaHeader: View {
    let media: ExerciseMedia
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEnd = false
    @State private var poster: UIImage?
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(Theme.Size.mediaMinAspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: Theme.Size.mediaMaxHeight)
        .background(Theme.Colors.bgSunken)
        .clipShape(.continuous(Theme.Radius.banner))
        .accessibilityElement()
        .accessibilityLabel("Demonstration")
        .onChange(of: reduceMotion) { _, reduce in
            if reduce { player?.pause() } else { player?.play() }
        }
    }

    @ViewBuilder private var content: some View {
        switch media {
        case .stills(let start, let end):
            ZStack {
                still(start)
                if !reduceMotion { still(end).opacity(showEnd ? 1 : 0) }
            }
            .task(id: reduceMotion) {
                showEnd = false
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(0.9))
                    withAnimation(.easeInOut(duration: 0.5)) { showEnd.toggle() }
                }
            }
        case .hold(let file):
            still(file)
        case .video(let file):
            if reduceMotion {
                Group {
                    if let poster { Image(uiImage: poster).resizable().scaledToFit() } else { Color.clear }
                }
                .task { poster = await MediaStore.thumbnail(for: media, side: 600) }
            } else {
                VideoPlayer(player: player)
                    .disabled(true)            // no controls, so it can never be unmuted
                    .onAppear { startVideo(file) }
                    .onDisappear { player?.pause() }
            }
        }
    }

    private func still(_ file: String) -> some View {
        Group {
            if let url = MediaStore.url(file), let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
    }

    private func startVideo(_ file: String) {
        if let player { player.play(); return }
        guard let url = MediaStore.url(file) else { return }
        // Ambient + mix: a silent demo never stops Ben's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        let q = AVQueuePlayer()
        q.isMuted = true
        q.preventsDisplaySleepDuringVideoPlayback = false
        q.audiovisualBackgroundPlaybackPolicy = .pauses
        looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url))
        player = q
        q.play()
    }
}
