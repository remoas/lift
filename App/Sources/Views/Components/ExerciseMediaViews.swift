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

/// Exercise detail header: start → end crossfade for stills, a muted loop for video.
struct ExerciseMediaHeader: View {
    let media: ExerciseMedia
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEnd = false
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            switch media {
            case .stills(let start, let end):
                ZStack {
                    still(start)
                    still(end).opacity(showEnd ? 1 : 0)
                }
                .task {
                    guard !reduceMotion else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(0.9))
                        withAnimation(.easeInOut(duration: 0.5)) { showEnd.toggle() }
                    }
                }
            case .hold(let file):
                still(file)
            case .video(let file):
                VideoPlayer(player: player)
                    .disabled(true)
                    .onAppear { startVideo(file) }
                    .onDisappear { player?.pause() }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Size.mediaHeight)
        .background(Theme.Colors.bgSunken)
        .clipShape(.continuous(Theme.Radius.banner))
        .accessibilityLabel("Demonstration")
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
        guard player == nil, let url = MediaStore.url(file) else { player?.play(); return }
        let item = AVPlayerItem(url: url)
        let q = AVQueuePlayer()
        q.isMuted = true
        looper = AVPlayerLooper(player: q, templateItem: item)
        player = q
        if !reduceMotion { q.play() }
    }
}
