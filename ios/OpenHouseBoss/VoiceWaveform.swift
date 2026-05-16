import SwiftUI

// Voice waveform — flowing sine-wave layers radiating from a glowing
// gold orb at the center. Replaces the old "vertical-bar VU meter +
// mic-icon disc" pair (MicOrb + SmoothWaveform / IPadMicOrb +
// IPadWaveform).
//
// Design goals:
//   1. No mic icon. The orb itself is the visual anchor — a gold-
//      gradient sphere with a soft outer glow.
//   2. Multiple sine layers at different amplitudes/periods/phases
//      drift across the canvas so the motion never feels like a
//      stepping VU meter.
//   3. The audio level coming off the mic gently scales the amplitude
//      so loud rooms make the waves swell — but they're never zero
//      when recording, so there's always something on screen even in
//      a silent moment.
//
// Usage:
//   VoiceWaveform(level: recorder.rms, recording: recorder.isRecording)
//       .frame(height: 220)
//
// `level` is 0…1 (RMS-ish), `recording` flips colors slightly cooler
// when false so a paused state reads as paused.
struct VoiceWaveform: View {
    /// Current mic level 0...1. Drives a subtle amplitude swell so loud
    /// rooms read as louder waves on screen.
    var level: CGFloat = 0.3
    /// When false (paused / before recording starts), drops opacity and
    /// freezes the flow so the screen looks dormant.
    var recording: Bool = true
    /// Size of the central orb. The wave layers scale around it.
    var orbSize: CGFloat = 110

    var body: some View {
        // TimelineView fires every animation frame and gives us a wall-
        // clock date so each path can derive its own phase from elapsed
        // time. No per-frame state updates needed — Path redraws are
        // cheap and Swift's compositor handles smoothing.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Audio-reactive amplitude. Floor stays low so silence reads as
            // calm (small lapping waves around the orb), but speech swells
            // the waves dramatically. The pow(level, 1.3) curve compresses
            // the bottom of the range — room ambience (norm ~0.1-0.2) stays
            // visually quiet — and lets real speech (norm 0.6+) take over.
            let shaped = pow(max(0, min(1, level)), 1.3)
            let live = recording ? max(0.12, min(1.0, 0.12 + shaped * 1.0)) : 0.08

            ZStack {
                // Radial glow behind everything — gives the orb a halo.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                FoyerTheme.gold.opacity(0.20 * live),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 260
                        )
                    )
                    .scaleEffect(1 + shaped * 0.18)
                    .animation(.easeOut(duration: 0.15), value: level)

                // Wave layers — drawn front to back, then capped with the
                // orb on top so the lines disappear "behind" it.
                ForEach(0..<waveLayers.count, id: \.self) { i in
                    WaveLayerView(layer: waveLayers[i], time: t, amplitudeScale: live)
                }

                // Central glowing orb — gradient gold, no icon.
                OrbView(size: orbSize, recording: recording, level: level)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: – Wave layer config

// One radiating sine path. The set below was hand-tuned to match the
// reference screenshot (purple → gold): a few big slow layers carrying
// the silhouette, a couple of thin fast layers filling in detail.
private struct WaveLayer {
    let amplitude: CGFloat   // px peak deviation from center line
    let period: CGFloat      // px per full sine cycle (wavelength)
    let phaseOffset: Double  // initial phase, radians
    let speed: Double        // radians/sec of phase drift (negative reverses)
    let opacity: Double      // base stroke alpha
    let lineWidth: CGFloat   // stroke thickness
}

private let waveLayers: [WaveLayer] = [
    WaveLayer(amplitude: 32, period: 200, phaseOffset: 0.0,  speed:  0.8,  opacity: 0.85, lineWidth: 1.6),
    WaveLayer(amplitude: 22, period: 150, phaseOffset: 1.1,  speed: -1.1,  opacity: 0.65, lineWidth: 1.4),
    WaveLayer(amplitude: 40, period: 280, phaseOffset: 2.0,  speed:  0.5,  opacity: 0.45, lineWidth: 1.2),
    WaveLayer(amplitude: 14, period: 110, phaseOffset: 2.8,  speed: -1.5,  opacity: 0.55, lineWidth: 1.0),
    WaveLayer(amplitude: 26, period: 220, phaseOffset: 0.6,  speed:  0.9,  opacity: 0.35, lineWidth: 1.0),
    WaveLayer(amplitude: 10, period:  80, phaseOffset: 1.7,  speed: -1.9,  opacity: 0.30, lineWidth: 0.8),
]

// MARK: – Wave path

private struct WaveLayerView: View {
    let layer: WaveLayer
    let time: TimeInterval
    let amplitudeScale: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cy = geo.size.height / 2
            let phase = layer.phaseOffset + time * layer.speed
            let amp = layer.amplitude * amplitudeScale

            Path { path in
                // Soft edge falloff — amplitude tapers near the screen
                // edges so the waves feel like they're emanating from
                // the center, not just running off the canvas.
                let steps = max(60, Int(w / 3))
                let stepSize = w / CGFloat(steps)
                for i in 0...steps {
                    let x = CGFloat(i) * stepSize
                    let distFromCenter = abs(x - w / 2) / (w / 2)
                    // Bell curve: peak at center (1.0), zero at edges.
                    let env = 1 - pow(distFromCenter, 1.6)
                    let y = cy + sin(Double(x / layer.period) * .pi * 2 + phase) * Double(amp) * Double(max(0, env))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else      { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(FoyerTheme.gold.opacity(layer.opacity), style: StrokeStyle(lineWidth: layer.lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: – Center orb

// Gold-gradient sphere with a hot highlight, a soft outer halo, and a
// gentle pulse synced to the mic level. Intentionally no mic icon —
// the orb itself reads as "voice."
private struct OrbView: View {
    var size: CGFloat
    var recording: Bool
    var level: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 1.0, opacity: 0.85),     // hot highlight
                            FoyerTheme.goldBright,
                            FoyerTheme.gold,
                            FoyerTheme.goldDeep.opacity(0.7),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 2,
                        endRadius: size * 0.65
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: FoyerTheme.gold.opacity(recording ? 0.5 + level * 0.4 : 0.25),
                        radius: 22 + level * 32, x: 0, y: 0)
                .shadow(color: FoyerTheme.gold.opacity(0.20 + level * 0.30),
                        radius: 50 + level * 50, x: 0, y: 0)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                        .blendMode(.overlay)
                )
                .scaleEffect(1 + level * 0.14)
                .animation(.easeOut(duration: 0.15), value: level)
                .opacity(recording ? 1 : 0.55)
        }
    }
}
