import SwiftUI

// Live recording — v2 editorial. Centerpiece is a cinematic voice animation:
// a pulsing mic surrounded by concentric rings that react to actual input
// level, plus a smooth mirrored waveform underneath. Real AVAudioRecorder
// drives both.
struct LiveView: View {
    @Environment(AppRouter.self) private var router
    @State private var recorder = AudioRecorder()
    @State private var permissionDenied = false
    @State private var paused = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: .live)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Sessions", currentAddress], onBack: { router.pop() }) {
                        StatusPill(
                            text: recorder.isRecording ? "LIVE \(timeString)" : "STARTING",
                            tone: .live,
                            pulsing: recorder.isRecording
                        )
                    }
                    title
                    voiceVisualizer
                    capturedHint
                    Spacer().frame(height: 200)
                }
                .padding(.top, 8)
            }

            controls
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !recorder.isRecording else { return }
            let granted = await recorder.requestPermission()
            if granted {
                do { try recorder.startRecording() }
                catch { /* surface via UI if needed */ }
            } else {
                permissionDenied = true
            }
        }
        .alert("Microphone access needed", isPresented: $permissionDenied) {
            Button("OK") { router.pop() }
        } message: {
            Text("Enable microphone access in Settings to record audio.")
        }
    }

    private var currentAddress: String {
        SessionStore.shared.pendingAddress ?? "Open house"
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Listening")
                .foyerDisplay(32)
                .foregroundStyle(FoyerTheme.cream)
            Text("WE'LL IDENTIFY EACH SPEAKER AT THE END")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // The cinematic voice animation. Three layers:
    //   1. Concentric pulse rings that scale with the rolling input level.
    //   2. A glowing brass mic in the center with a slow ambient pulse.
    //   3. A symmetric waveform below, smoothly interpolated each frame.
    private var voiceVisualizer: some View {
        GlassSurface(cornerRadius: 24, strong: true) {
            VStack(spacing: 22) {
                HStack {
                    Eyebrow(text: paused ? "Paused" : "Speaking now", color: FoyerTheme.terracotta)
                    Spacer()
                    Text(timeString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FoyerTheme.cream)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)

                MicOrb(level: rmsLevel, recording: recorder.isRecording && !paused)
                    .frame(height: 160)

                SmoothWaveform(levels: recorder.levels,
                               accent: FoyerTheme.terracotta,
                               trail: FoyerTheme.gold)
                    .frame(height: 56)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    // Rolling RMS of the live level window — used to drive the ring scale.
    private var rmsLevel: CGFloat {
        let recent = recorder.levels.suffix(8)
        let avg = recent.reduce(0, +) / Float(max(recent.count, 1))
        return CGFloat(min(1, max(0, avg)))
    }

    private var capturedHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Captured guests")
            Text("Speakers will be identified after you end the session — we separate voices and tag each guest.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                paused.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(paused ? "Resume" : "Pause")
                }
            }
            .buttonStyle(FoyerGhostButton())
            .frame(maxWidth: .infinity)

            Button(action: endSession) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 10, height: 10)
                    Text("End session")
                }
            }
            .buttonStyle(FoyerDangerButton())
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private func endSession() {
        guard let url = recorder.stopRecording() else { return }
        SessionStore.shared.uploadAndProcess(audioURL: url)
        // Replace the back-stack so Summary becomes the only screen on top
        // of HomeShell — pressing Back from Summary goes straight home,
        // not back to the (now-stopped) Live recording.
        router.endSessionShowSummary()
    }

    private var timeString: String {
        let total = Int(recorder.elapsed)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: – Voice visualizer pieces

// MicOrb — a glowing brass disc with concentric pulse rings whose scale and
// opacity respond to the live input level. The whole thing breathes on a
// 1.4s pulse even at zero input so the screen never feels frozen.
private struct MicOrb: View {
    var level: CGFloat
    var recording: Bool

    var body: some View {
        ZStack {
            // Soft ambient halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [FoyerTheme.terracotta.opacity(0.30), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 100
                    )
                )
                .scaleEffect(1 + level * 0.18)
                .animation(.easeOut(duration: 0.15), value: level)

            // Three concentric pulse rings, level-aware
            PulseRing(color: FoyerTheme.terracotta, delay: 0.0)
                .frame(width: 120, height: 120)
                .opacity(recording ? 0.85 : 0.30)
            PulseRing(color: FoyerTheme.terracotta, delay: 0.7)
                .frame(width: 120, height: 120)
                .opacity(recording ? 0.60 : 0.20)
            PulseRing(color: FoyerTheme.gold, delay: 1.4)
                .frame(width: 120, height: 120)
                .opacity(recording ? 0.45 : 0.15)

            // Level-driven outer ring that grows immediately with audio
            Circle()
                .stroke(FoyerTheme.terracotta.opacity(0.8), lineWidth: 1.5)
                .frame(width: 100 + level * 60, height: 100 + level * 60)
                .opacity(level * 0.9 + 0.15)
                .animation(.easeOut(duration: 0.18), value: level)

            // Mic disc
            Circle()
                .fill(
                    LinearGradient(
                        colors: [FoyerTheme.goldBright, FoyerTheme.goldDeep],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 78, height: 78)
                .shadow(color: FoyerTheme.gold.opacity(0.6), radius: 22, x: 0, y: 8)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                        .blendMode(.overlay)
                )

            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(FoyerTheme.inkOnGold)
        }
    }
}

// SmoothWaveform — symmetric bars driven by the recorder's rolling level
// window. Each bar smoothly interpolates toward its target so the motion
// looks cinematic instead of stepping like a 6 Hz meter. The newest samples
// (right edge) glow in terracotta; older samples fade through brass.
private struct SmoothWaveform: View {
    var levels: [Float]
    var accent: Color
    var trail: Color

    // Animated mirror of `levels`. Updated via .onChange so SwiftUI can
    // tween between frames rather than snapping.
    @State private var animated: [CGFloat] = []

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let barCount = min(count, 56)
            let spacing: CGFloat = 2.5
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let width = max(2, (geo.size.width - totalSpacing) / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let value = level(at: i, barCount: barCount)
                    let isNow = i >= barCount - 6
                    Capsule()
                        .fill(isNow ? accent : trail)
                        .opacity(isNow ? min(1, 0.55 + Double(value) * 0.6)
                                       : 0.35 + Double(value) * 0.5)
                        .frame(
                            width: width,
                            height: max(3, value * (geo.size.height - 4))
                        )
                        .shadow(color: isNow ? accent.opacity(0.6) : .clear,
                                radius: isNow ? 6 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { syncAnimated() }
        .onChange(of: levels) { _, _ in
            withAnimation(.easeOut(duration: 0.18)) {
                syncAnimated()
            }
        }
    }

    private func level(at index: Int, barCount: Int) -> CGFloat {
        // Use the trailing `barCount` samples from `animated`.
        let count = animated.count
        guard count > 0 else { return 0 }
        let offset = max(0, count - barCount)
        let idx = min(count - 1, offset + index)
        return animated[idx]
    }

    private func syncAnimated() {
        let mapped = levels.map { CGFloat($0) }
        if animated.count != mapped.count {
            animated = mapped
        } else {
            // Element-wise smooth interpolation toward target — the
            // withAnimation modifier in .onChange handles the tween.
            animated = zip(animated, mapped).map { current, target in
                current + (target - current) * 0.85
            }
        }
    }
}

#Preview { NavigationStack { LiveView() } }
