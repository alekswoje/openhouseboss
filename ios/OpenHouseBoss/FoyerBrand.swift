import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// ============================================================
// Foyer brand mark + animated loading view
// ============================================================
//
// Two pieces of shared brand UI used across iPad and iPhone:
//
//   FoyerBrandMark — the glowing-F image set, sized for whatever container
//   FoyerLoadingView — the animated GIF used everywhere we'd previously have
//     shown a generic ProgressView (loading sessions, fetching transcripts,
//     waiting on the pipeline, etc.). SwiftUI's Image doesn't animate GIFs
//     on its own — we decode frames + their per-frame delays with ImageIO
//     and step through them on a TimelineView.

struct FoyerBrandMark: View {
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 8

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: – Animated GIF loader

// Cached GIF frames so we don't re-decode the file on every view appearance.
// Keyed by bundle resource name so future loaders (different animations)
// can share the same plumbing.
private enum GifCache {
    static var frames: [String: GifFrames] = [:]
}

struct GifFrames {
    let images: [UIImage]
    let delays: [TimeInterval]  // seconds per frame
    let totalDuration: TimeInterval
}

private func loadGifFrames(named name: String) -> GifFrames? {
    if let cached = GifCache.frames[name] { return cached }
    guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil)
    else { return nil }
    let count = CGImageSourceGetCount(source)
    guard count > 0 else { return nil }
    var images: [UIImage] = []
    var delays: [TimeInterval] = []
    images.reserveCapacity(count)
    delays.reserveCapacity(count)
    for i in 0..<count {
        guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
        images.append(UIImage(cgImage: cg))
        delays.append(gifFrameDelay(source: source, index: i))
    }
    let frames = GifFrames(
        images: images,
        delays: delays,
        totalDuration: delays.reduce(0, +)
    )
    GifCache.frames[name] = frames
    return frames
}

private func gifFrameDelay(source: CGImageSource, index: Int) -> TimeInterval {
    // GIF spec: unspecified/zero delays should render at ~10fps. Match what
    // browsers do so the animation matches the source's intended feel.
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any],
          let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    else { return 0.1 }
    let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double
    let clamped = gifProps[kCGImagePropertyGIFDelayTime] as? Double
    let delay = unclamped ?? clamped ?? 0.1
    return delay < 0.011 ? 0.1 : delay
}

// Animated loading view — drops the brand-mark GIF in a fixed frame and
// steps through frames using TimelineView. The frame timing follows the
// GIF's own per-frame delays rather than assuming a constant FPS so the
// motion feels right.
struct FoyerLoadingView: View {
    var size: CGFloat = 80
    var cornerRadius: CGFloat = 12

    private let frames: GifFrames? = loadGifFrames(named: "foyer-loading")
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if let frames, !frames.images.isEmpty, frames.totalDuration > 0 {
                TimelineView(.animation) { context in
                    Image(uiImage: frames.images[index(at: context.date, frames: frames)])
                        .resizable()
                        .scaledToFit()
                }
            } else {
                // Bundle missing the GIF (unlikely in shipped builds) — fall
                // back to a tinted spinner so the user still gets a "working"
                // signal instead of a blank rectangle.
                ProgressView().tint(FoyerTheme.gold)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func index(at now: Date, frames: GifFrames) -> Int {
        let elapsed = now.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: frames.totalDuration)
        var acc: TimeInterval = 0
        for (i, d) in frames.delays.enumerated() {
            acc += d
            if elapsed < acc { return i }
        }
        return frames.images.count - 1
    }
}
