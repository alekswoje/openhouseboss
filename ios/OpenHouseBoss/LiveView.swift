import SwiftUI

// Live recording — real AVAudioRecorder driving a real elapsed timer + waveform.
// End session uploads the m4a to the backend via SessionStore and pushes the
// summary screen, which polls until results are ready.
struct LiveView: View {
    @State private var recorder = AudioRecorder()
    @State private var permissionDenied = false
    @State private var goSummary = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    statusRow
                    title
                    waveform
                    capturedHint
                    Spacer().frame(height: 160)
                }
            }

            controls
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $goSummary) { SummaryView() }
        .task {
            // Auto-start recording when the screen appears (Setup → Live is
            // already a deliberate action; no extra tap needed here).
            guard !recorder.isRecording else { return }
            let granted = await recorder.requestPermission()
            if granted {
                do { try recorder.startRecording() }
                catch { /* surfaced via toolbar state if we add it */ }
            } else {
                permissionDenied = true
            }
        }
        .alert("Microphone access needed", isPresented: $permissionDenied) {
            Button("OK") { dismiss() }
        } message: {
            Text("Enable microphone access in Settings to record audio.")
        }
    }

    private var statusRow: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(FoyerTheme.terracotta).frame(width: 8, height: 8)
                    .shadow(color: FoyerTheme.terracotta, radius: 6)
                Text(recorder.isRecording ? "LIVE" : "STARTING")
                    .font(.system(size: 11, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(FoyerTheme.terracotta)
            }
            Spacer()
            Text(timeString)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "412 W 78th — Apt 4-A")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Listening")
                    .foyerDisplay(26).foregroundStyle(FoyerTheme.cream)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var waveform: some View {
        // Drive from the recorder's rolling level window. Older samples on
        // the left fade slightly; the rightmost = "now".
        let bars = recorder.levels
        return VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { i, level in
                    let h = max(4, CGFloat(level) * 88)
                    let isNow = i >= bars.count - 6
                    Rectangle()
                        .fill(isNow ? FoyerTheme.terracotta : FoyerTheme.gold)
                        .opacity(isNow ? 0.95 : 0.30 + Double(level) * 0.6)
                        .frame(width: 3, height: h)
                }
            }
            .frame(height: 88)
            HStack {
                Text("LIVE")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(FoyerTheme.textMuted)
                Spacer()
                Text("● NOW")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(FoyerTheme.terracotta)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.top, 12)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var capturedHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Captured guests")
            Text("Speakers will be identified after you end the session.")
                .font(.system(size: 13)).foregroundStyle(FoyerTheme.textDim)
                .padding(.vertical, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: { Text("Cancel") }
                .buttonStyle(FoyerGhostButton())
                .frame(maxWidth: .infinity)
            Button(action: endSession) { Text("End session") }
                .font(.system(size: 13, weight: .semibold)).tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .padding(.vertical, 16).padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .background(FoyerTheme.terracotta, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private func endSession() {
        guard let url = recorder.stopRecording() else { return }
        SessionStore.shared.uploadAndProcess(audioURL: url)
        goSummary = true
    }

    private var timeString: String {
        let total = Int(recorder.elapsed)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

#Preview { NavigationStack { LiveView() } }
