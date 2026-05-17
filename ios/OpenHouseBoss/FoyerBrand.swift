import SwiftUI

// ============================================================
// Foyer brand mark + animated loading view
// ============================================================
//
// Two pieces of shared brand UI used across iPad and iPhone:
//
//   FoyerBrandMark — the twin-houses image set, sized for whatever container
//   FoyerLoadingView — animated brand mark used everywhere we'd previously
//     have shown a generic ProgressView (loading sessions, fetching
//     transcripts, waiting on the pipeline, etc.). Pulses scale + opacity
//     so the user gets a "working" signal that stays on-brand with the
//     current logo automatically.

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

// Animated loading view — pulses the brand mark with a gentle breath
// (scale + opacity). Driven by TimelineView so it animates continuously
// without stale `@State` on view-recreation. Kept resolution-independent
// so the same loader works at every call site (small badges → big hero).
struct FoyerLoadingView: View {
    var size: CGFloat = 80
    var cornerRadius: CGFloat = 12

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // 1.4s breath cycle, smoothed via sin so the motion eases in
            // and out instead of snapping at the endpoints.
            let phase = sin(t * (2 * .pi / 1.4))
            let scale = 0.94 + 0.06 * (phase + 1) / 2
            let opacity = 0.72 + 0.28 * (phase + 1) / 2

            ZStack {
                // Soft teal glow that breathes with the mark — gives the
                // loader some warmth on the dark background.
                Circle()
                    .fill(FoyerTheme.gold.opacity(0.18 * opacity))
                    .frame(width: size * 1.05, height: size * 1.05)
                    .blur(radius: size * 0.18)

                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .scaleEffect(scale)
                    .opacity(opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
