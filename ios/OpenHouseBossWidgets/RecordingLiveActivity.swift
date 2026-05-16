import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Live Activity surface — registered with the WidgetBundle so iOS shows it
// on the Lock Screen and inside the Dynamic Island while the app is
// recording. Tapping the red "Stop" button fires StopRecordingIntent,
// which writes a sentinel the main app polls to end the recording.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(context.state.isMuted ? Color.white.opacity(0.4) : Color.red)
                            .frame(width: 9, height: 9)
                        Text(label(for: context.state.phase, muted: context.state.isMuted))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.phase == .recording {
                        HStack(spacing: 6) {
                            Button(intent: ToggleMuteIntent()) {
                                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(
                                        (context.state.isMuted ? Color.white.opacity(0.22) : Color.white.opacity(0.12)),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)

                            Button(intent: StopRecordingIntent()) {
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.white)
                                        .frame(width: 9, height: 9)
                                    Text("Stop")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.red, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("Processing")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.address.isEmpty ? "Open house" : context.attributes.address)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    timerLine(for: context.state.startedAt, phase: context.state.phase, muted: context.state.isMuted)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: compactLeadingIcon(for: context.state))
                    .foregroundStyle(context.state.isMuted ? .white : .red)
            } compactTrailing: {
                if context.state.phase == .recording {
                    Text(timerInterval(from: context.state.startedAt), style: .timer)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(maxWidth: 50)
                } else {
                    Text("…")
                        .foregroundStyle(.white)
                }
            } minimal: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "waveform")
                    .foregroundStyle(context.state.isMuted ? .white : .red)
            }
        }
    }

    // Lock Screen + always-on view. Mirrors the in-app LiveSessionBar
    // styling so the agent recognizes it: warm dark surface with a red
    // pulse, the address, the live timer, and a Stop button on the right.
    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        let muted = context.state.isMuted
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(muted ? Color.white.opacity(0.12) : Color.red.opacity(0.2))
                    .frame(width: 38, height: 38)
                Circle()
                    .fill(muted ? Color.white.opacity(0.6) : Color.red)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label(for: context.state.phase, muted: muted))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(muted ? Color.white.opacity(0.7) : Color.red)
                Text(context.attributes.address.isEmpty ? "Open house" : context.attributes.address)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                timerLine(for: context.state.startedAt, phase: context.state.phase, muted: muted)
            }
            Spacer()
            if context.state.phase == .recording {
                HStack(spacing: 8) {
                    Button(intent: ToggleMuteIntent()) {
                        HStack(spacing: 6) {
                            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(muted ? "Unmute" : "Mute")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color.white.opacity(muted ? 0.22 : 0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(intent: StopRecordingIntent()) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white)
                                .frame(width: 10, height: 10)
                            Text("Stop")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.red, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func label(for phase: RecordingActivityAttributes.ContentState.Phase, muted: Bool = false) -> String {
        if phase != .recording { return "PROCESSING" }
        return muted ? "MUTED" : "LIVE"
    }

    private func compactLeadingIcon(for state: RecordingActivityAttributes.ContentState) -> String {
        if state.phase != .recording { return "hourglass" }
        return state.isMuted ? "mic.slash.fill" : "waveform"
    }

    private func timerInterval(from start: Date) -> Date {
        // The Text(timer:) style counts forward from a Date in the past;
        // returning the start moment lets WidgetKit auto-update without
        // us pushing new content states every second.
        start
    }

    @ViewBuilder
    private func timerLine(for start: Date, phase: RecordingActivityAttributes.ContentState.Phase, muted: Bool = false) -> some View {
        if phase == .recording {
            HStack(spacing: 6) {
                Text(start, style: .timer)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                if muted {
                    Text("· mic off")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        } else {
            Text("Uploading audio…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
