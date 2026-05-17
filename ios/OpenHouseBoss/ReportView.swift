import SwiftUI
import UIKit
import WebKit

// Open House Report — homeowner-facing report generated from a session.
// Lives on its own screen (pushed via router on iPhone, presented as a
// sheet on iPad from the session detail). The view's job is the
// agent-facing review/edit/send flow; the actual generation is a backend
// Claude call (pipeline/report.py), and the emailed HTML is rendered
// server-side (backend serves /sessions/{id}/report.html).
struct ReportView: View {
    // nil = use SessionStore.shared.session?.id (fresh, just-recorded
    // session). Otherwise the explicit session id passed in by the
    // pastSession route.
    let sessionId: String?

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var store = SessionStore.shared

    @State private var report: SessionReport?
    @State private var reportMeta: ReportMeta?
    @State private var resolvedSession: Session?
    @State private var homeownerEmail: String = ""
    @State private var homeownerName: String = ""

    @State private var loading = true
    @State private var loadError: String?
    @State private var generating = false
    @State private var generateError: String?

    // AI-refine state — agents tell Claude what's wrong in plain
    // English ("tighten the agent take"); Haiku rewrites and we swap
    // the saved report. Replaces the old per-section TextEditor flow:
    // homeowner-facing reports need consistent voice + Fair Housing
    // guarantees, which manual editing in tiny fields couldn't enforce.
    @State private var showRefineSheet = false
    @State private var refining = false
    @State private var refineError: String?

    // Tracks whether we've already auto-kicked generation in this view
    // instance. Without it, .task firing after an iOS scene re-attach
    // would spin a second generate while one was already in flight.
    @State private var autoStartAttempted = false

    @State private var showSendSheet = false
    @State private var showRegenerateConfirm = false
    @State private var showHomeownerSheet = false

    @State private var pdfData: Data?
    @State private var showShare = false
    @State private var exportingPdf = false

    // Public share link — minted on first tap of "Share link", revoked
    // via the trash button in the share sheet. Drives the badge that
    // appears in the action bar once a link exists.
    @State private var share: ReportShare?
    @State private var creatingShare = false
    @State private var shareError: String?
    @State private var showShareLink = false
    @State private var showRevokeConfirm = false

    private var effectiveSessionId: String? {
        sessionId ?? store.session?.id
    }

    // Past sessions aren't held in `store.session` (that slot is for the
    // active recording), so reads must prefer the explicitly-loaded
    // session. Without this, the Generate-report button reads the live
    // session's status (often nil for past-session navigation) and stays
    // silently disabled.
    private var effectiveStatus: String? {
        resolvedSession?.status ?? store.session?.status
    }

    private var effectiveAddress: String? {
        resolvedSession?.address ?? store.session?.address
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: .gold)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Sessions", "Report"], onBack: { back() }) {
                        // AI refine button — top-right, small. Only visible
                        // once a report exists (refining nothing is a no-op).
                        // Per the agent's spec: no manual edit, only AI-driven.
                        if report != nil {
                            Button { showRefineSheet = true } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("EDIT WITH AI")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .tracking(1.4)
                                }
                                .foregroundStyle(FoyerTheme.gold)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(FoyerTheme.bgElev, in: Capsule())
                                .overlay(Capsule().stroke(FoyerTheme.gold.opacity(0.4), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    header
                    content
                    Spacer().frame(height: 200)
                }
                .padding(.top, 8)
            }

            if report != nil {
                VStack(spacing: 0) {
                    if let share {
                        shareBadge(share)
                            .padding(.bottom, 6)
                    }
                    actionBar
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(isPresented: $showSendSheet) {
            if let sid = effectiveSessionId, let r = report {
                SendReportSheet(
                    sessionId: sid,
                    report: r,
                    initialEmail: homeownerEmail,
                    initialName: homeownerName,
                    onSent: { meta in
                        reportMeta = meta
                        showSendSheet = false
                    },
                    onHomeownerUpdate: { email, name in
                        homeownerEmail = email
                        homeownerName = name
                    }
                )
            }
        }
        .sheet(isPresented: $showHomeownerSheet) {
            if let sid = effectiveSessionId {
                HomeownerSheet(
                    sessionId: sid,
                    initialEmail: homeownerEmail,
                    initialName: homeownerName,
                    onSaved: { email, name in
                        homeownerEmail = email
                        homeownerName = name
                        showHomeownerSheet = false
                    }
                )
            }
        }
        .sheet(isPresented: $showShare) {
            if let data = pdfData {
                ShareSheet(items: [PDFShareItem(
                    data: data,
                    filename: pdfFilename
                )])
            }
        }
        .sheet(isPresented: $showShareLink) {
            if let share {
                ShareSheet(items: [
                    URL(string: share.url) ?? share.url as Any,
                    "Open house report — \(report?.address ?? effectiveAddress ?? "")",
                ])
            }
        }
        .alert("Revoke share link?", isPresented: $showRevokeConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                Task { await revokeShareLink() }
            }
        } message: {
            Text("The current public link will stop working immediately. You can mint a new one later.")
        }
        .alert("Regenerate report?", isPresented: $showRegenerateConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Regenerate", role: .destructive) {
                Task { await generate(force: true) }
            }
        } message: {
            Text("This will replace the current report with a fresh Claude-generated one.")
        }
        .sheet(isPresented: $showRefineSheet) {
            AIRefineSheet(
                refining: refining,
                error: refineError,
                onSubmit: { instruction in
                    Task { await refineWithAI(instruction: instruction) }
                },
                onRegenerate: {
                    showRefineSheet = false
                    showRegenerateConfirm = true
                }
            )
        }
    }

    // MARK: – Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "OPEN HOUSE REPORT", color: FoyerTheme.gold)
            Text(report?.address.isEmpty == false ? report!.address :
                 (effectiveAddress ?? "Open house"))
                .foyerDisplay(32)
                .foregroundStyle(FoyerTheme.cream)
            if let r = report, !r.dateLabel.isEmpty {
                Text(metaLine(for: r))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(FoyerTheme.textMuted)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private func metaLine(for r: SessionReport) -> String {
        var parts: [String] = []
        if !r.dateLabel.isEmpty { parts.append(r.dateLabel) }
        if r.durationMinutes > 0 { parts.append("\(r.durationMinutes) min") }
        if r.visitorCount > 0 {
            parts.append("\(r.visitorCount) visitor\(r.visitorCount == 1 ? "" : "s")")
        }
        // Weather chip — only when we have a real Open-Meteo reading
        // (geocoded to the property, not city-level).
        if !r.weatherLabel.isEmpty {
            parts.append(r.weatherLabel)
        }
        return parts.joined(separator: " · ").uppercased()
    }

    @ViewBuilder
    private var content: some View {
        if loading && report == nil {
            // Initial fetch — keep this terse; usually <1s before we
            // either show the report or transition to the generating
            // animation.
            HStack(spacing: 10) {
                ProgressView().tint(FoyerTheme.gold).scaleEffect(0.9)
                Text("Loading…")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else if let err = loadError ?? generateError {
            errorCard(err)
        } else if let r = report {
            if refining {
                // Overlay the refine loader on TOP of the report so
                // the agent sees what's being rewritten, not a blank
                // screen. Cheaper visual + keeps the spatial context.
                ZStack {
                    renderedBody(r).opacity(0.35)
                    GeneratingAnimation(kind: .refining)
                        .padding(.top, 60)
                }
            } else {
                renderedBody(r)
            }
        } else if generating {
            // No report yet → big centered staged loader. Auto-triggered
            // from load() on first open so the agent never has to tap
            // a "Generate" button.
            GeneratingAnimation(kind: .generating)
                .padding(.top, 40)
        } else {
            // Fallbacks — only visible when the session isn't ready
            // enough to generate against. Most agents will skip this
            // entirely because auto-start fires the moment status flips.
            preGenerateFallback
        }
    }

    @ViewBuilder
    private var preGenerateFallback: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSurface(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: fallbackEyebrow, color: FoyerTheme.gold)
                    Text(fallbackTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineSpacing(3)
                    Text(fallbackSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.creamDim)
                        .lineSpacing(3)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
    }

    private var fallbackEyebrow: String {
        switch effectiveStatus {
        case "processing": return "Still processing"
        case "error":      return "Session error"
        default:           return "No session"
        }
    }
    private var fallbackTitle: String {
        switch effectiveStatus {
        case "processing": return "We'll start the report the moment processing finishes."
        case "error":      return "This session errored out — nothing to report on."
        default:           return "Open a session to generate its report."
        }
    }
    private var fallbackSubtitle: String {
        switch effectiveStatus {
        case "processing": return "Reports start automatically once transcription and visitor analysis land."
        case "error":      return "Try re-analyzing the recording from the Summary screen."
        default:           return "Reports are generated from a recorded session."
        }
    }

    // MARK: – Read-only render

    @ViewBuilder
    private func renderedBody(_ r: SessionReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            tldrCard(r)
            sectionCard(title: "Traffic") {
                Text(r.trafficSummary)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .lineSpacing(3)
            }
            sectionCard(title: "Highlights") {
                themeList(r.highlights, fallback: "Nothing recurred across visitors this session.")
            }
            sectionCard(title: "Concerns + objections") {
                themeList(r.concerns, fallback: "No recurring concerns surfaced.")
            }
            sectionCard(title: "Price signal") {
                Text(r.priceSignal)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .lineSpacing(3)
            }
            sectionCard(title: "Standout visitors") {
                standoutList(r.standoutVisitors)
            }
            sectionCard(title: "My take") {
                Text(r.agentTake)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineSpacing(4)
            }
            sectionCard(title: "Recommended next steps") {
                bulletList(r.nextSteps, fallback: "—")
            }
            if let meta = reportMeta {
                metaFooter(meta)
            }
        }
        .padding(.horizontal, 20)
    }

    private func tldrCard(_ r: SessionReport) -> some View {
        GlassSurface(cornerRadius: 18, strong: true) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "TL;DR", color: FoyerTheme.gold)
                Text(r.headline)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineSpacing(4)
                if !r.tldr.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(r.tldr, id: \.self) { b in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(FoyerTheme.gold)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 7)
                                Text(b)
                                    .font(.system(size: 13))
                                    .foregroundStyle(FoyerTheme.creamDim)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FoyerTheme.gold.opacity(0.40), lineWidth: 1)
        )
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        GlassSurface(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: title, color: FoyerTheme.gold)
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func themeList(_ themes: [ReportTheme], fallback: String) -> some View {
        if themes.isEmpty {
            Text(fallback)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .italic()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(themes) { t in themeRow(t) }
            }
        }
    }

    private func themeRow(_ t: ReportTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(t.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                if t.frequency >= 2 {
                    Text("\(t.frequency) visitors")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
            }
            Text(t.summary)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(3)
            ForEach(t.quotes) { q in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\u{201C}\(q.quote)\u{201D}")
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(FoyerTheme.cream)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(FoyerTheme.gold)
                                .frame(width: 2)
                        }
                    if !q.attribution.isEmpty {
                        Text("— \(q.attribution)")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.textMuted)
                            .padding(.leading, 14)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func standoutList(_ visitors: [ReportStandoutVisitor]) -> some View {
        if visitors.isEmpty {
            Text("No standouts this session.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .italic()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(visitors) { v in standoutRow(v) }
            }
        }
    }

    private func standoutRow(_ v: ReportStandoutVisitor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(v.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Spacer()
                Text("\(v.score)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(scoreColor(v.score))
                Text("/100")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            Text(v.summary)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(3)
            if !v.followUpStatus.isEmpty {
                Text(v.followUpStatus)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(FoyerTheme.textMuted)
            }
        }
        .padding(12)
        .background(FoyerTheme.bgElev.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 70...:   return FoyerTheme.sage
        case 40..<70: return FoyerTheme.gold
        default:      return FoyerTheme.textMuted
        }
    }

    @ViewBuilder
    private func bulletList(_ items: [String], fallback: String) -> some View {
        if items.isEmpty {
            Text(fallback)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(FoyerTheme.gold)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .lineSpacing(3)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metaFooter(_ meta: ReportMeta) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sentAt = meta.sentAt, let to = meta.sentTo {
                Text("SENT \(relativeAgo(sentAt)) · \(to)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FoyerTheme.sage)
            }
            if meta.edited {
                Text("CUSTOM · EDITED BY YOU")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
        }
        .padding(.top, 4)
    }


    // MARK: – Action bar
    //
    // Layout:
    //   ┌──────────────────────────────────────────────┐
    //   │  [SHARED · VIEWED 5 TIMES]   ← optional badge │
    //   │  [🔗 Link]  [⤴ PDF]          ← secondary row  │
    //   │  [  ✉ Send to homeowner  ]   ← primary, big   │
    //   └──────────────────────────────────────────────┘
    // Backed by a soft material so the report scrolls underneath without
    // visually disappearing. Edit-with-AI lives in the BackBar trailing
    // slot per the agent's spec — out of the way until you need it.

    private var actionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Link — when a share exists, gold-tinted so the agent
                // sees there's a live link; tap re-opens the iOS share
                // sheet. Long-press for copy / open / revoke.
                Button {
                    Task { await tapShareLink() }
                } label: {
                    HStack(spacing: 6) {
                        if creatingShare {
                            ProgressView().scaleEffect(0.7).tint(FoyerTheme.cream)
                        } else {
                            Image(systemName: share == nil ? "link" : "link.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(share == nil ? "Share link" : "Open link")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(share == nil ? FoyerTheme.cream : FoyerTheme.inkOnGold)
                    .background(
                        share == nil
                            ? AnyShapeStyle(FoyerTheme.bgElev)
                            : AnyShapeStyle(LinearGradient(
                                colors: [FoyerTheme.gold, FoyerTheme.gold.opacity(0.82)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                              )),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(
                        share == nil ? FoyerTheme.border : FoyerTheme.gold.opacity(0.6),
                        lineWidth: 0.5
                    ))
                }
                .buttonStyle(.plain)
                .disabled(creatingShare)
                .contextMenu {
                    if share != nil {
                        Button("Copy link") { copyShareURL() }
                        Button("Open link") { openShareURL() }
                        Button("Revoke link", role: .destructive) {
                            showRevokeConfirm = true
                        }
                    }
                }

                // PDF — single icon button, secondary, keeps the row
                // balanced without competing for attention.
                Button { exportPdf() } label: {
                    HStack(spacing: 5) {
                        if exportingPdf {
                            ProgressView().scaleEffect(0.7).tint(FoyerTheme.cream)
                        } else {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text("PDF").font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .foregroundStyle(FoyerTheme.cream)
                    .background(FoyerTheme.bgElev, in: Capsule())
                    .overlay(Capsule().stroke(FoyerTheme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(exportingPdf)
            }

            // Big primary Send. Full-width, gold, soft glow — the
            // headline action on the screen. Single tap opens the
            // send sheet pre-filled with the homeowner's email.
            Button { showSendSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Send to homeowner")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(FoyerTheme.inkOnGold)
                .background(
                    LinearGradient(
                        colors: [FoyerTheme.gold, FoyerTheme.gold.opacity(0.88)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: FoyerTheme.gold.opacity(0.45), radius: 18, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 28)
        .background(
            // Soft fade-into-canvas so the scrolling report doesn't
            // poke harshly through the action bar. Material on iOS 17
            // does the heavy lifting; the gradient hides the seam.
            LinearGradient(
                colors: [FoyerTheme.bgDeep.opacity(0), FoyerTheme.bgDeep.opacity(0.9), FoyerTheme.bgDeep],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // Floating badge above the action bar — "SHARED · viewed 5 times"
    // with a tap target that opens the share sheet (so re-sharing or
    // copying the link is one tap, not two). Long-press → context menu
    // for revoke / copy / open.
    private func shareBadge(_ s: ReportShare) -> some View {
        Button {
            showShareLink = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                Text(badgeLabel(for: s))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(FoyerTheme.creamDim)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(FoyerTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy link") { copyShareURL() }
            Button("Open link") { openShareURL() }
            Button("Revoke link", role: .destructive) {
                showRevokeConfirm = true
            }
        }
        .padding(.horizontal, 20)
    }

    private func badgeLabel(for s: ReportShare) -> String {
        switch s.viewCount {
        case 0:  return "SHARED · NOT YET VIEWED"
        case 1:  return "SHARED · VIEWED ONCE"
        default: return "SHARED · VIEWED \(s.viewCount) TIMES"
        }
    }

    // MARK: – Shared cards

    private func loadingCard(_ label: String) -> some View {
        GlassSurface(cornerRadius: 14) {
            HStack(spacing: 12) {
                ProgressView().tint(FoyerTheme.gold).scaleEffect(0.9)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSurface(cornerRadius: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Couldn't load report", color: FoyerTheme.terracotta)
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineSpacing(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { Task { await load() } } label: {
                Text("Retry")
            }
            .buttonStyle(FoyerGhostButton())
        }
        .padding(.horizontal, 20)
    }

    // MARK: – Actions

    private func back() {
        if !router.path.isEmpty {
            router.pop()
        } else {
            dismiss()
        }
    }

    private func load() async {
        guard let sid = effectiveSessionId else {
            loading = false
            return
        }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            // Prime homeowner email/name + status from the session — we
            // keep these local for the Send sheet's default recipient and
            // for the empty-state Generate button's enabled check (past
            // sessions aren't in store.session, so the button would
            // otherwise stay silently disabled).
            if let s = try? await APIClient.shared.getSession(id: sid) {
                resolvedSession = s
                homeownerEmail = s.homeownerEmail ?? ""
                homeownerName = s.homeownerName ?? ""
            }
            if let envelope = try await APIClient.shared.getReport(sessionId: sid) {
                report = envelope.report
                reportMeta = envelope.reportMeta
            } else {
                report = nil
                reportMeta = nil
            }
            // Pull share state alongside the report so the badge +
            // "Shared" button label render correctly on first paint.
            // 404 just leaves share nil (not-shared is the default).
            share = try? await APIClient.shared.getReportShare(sessionId: sid)
        } catch {
            loadError = error.localizedDescription
        }
        // Auto-start: if the session is ready and there's no cached
        // report yet, fire generation immediately. Saves a click from
        // the agent's flow — they tap the gold "Open house report" card
        // and the report just starts building. autoStartAttempted
        // guards against a re-entrancy double-fire if .task replays.
        if !autoStartAttempted
            && report == nil
            && loadError == nil
            && generating == false
            && effectiveStatus == "ready"
            && effectiveSessionId != nil {
            autoStartAttempted = true
            await generate(force: false)
        }
    }

    private func tapShareLink() async {
        guard let sid = effectiveSessionId else { return }
        creatingShare = true
        shareError = nil
        defer { creatingShare = false }
        do {
            // First-time creation lazily mints the token; subsequent
            // taps return the existing one. Either way, end state is
            // the same: share is non-nil + share sheet opens.
            let s = try await APIClient.shared.createReportShare(sessionId: sid)
            share = s
            showShareLink = true
        } catch let err {
            shareError = err.localizedDescription
        }
    }

    private func revokeShareLink() async {
        guard let sid = effectiveSessionId else { return }
        do {
            try await APIClient.shared.revokeReportShare(sessionId: sid)
            share = nil
        } catch {
            shareError = error.localizedDescription
        }
    }

    private func copyShareURL() {
        guard let url = share?.url else { return }
        UIPasteboard.general.string = url
    }

    private func openShareURL() {
        guard let url = share?.url, let u = URL(string: url) else { return }
        UIApplication.shared.open(u)
    }

    private func generate(force: Bool) async {
        guard let sid = effectiveSessionId else { return }
        generating = true
        generateError = nil
        defer { generating = false }
        // Geocode + push lat/lon to the backend BEFORE kicking off the
        // Claude report — so the report's metadata stamping sees the
        // weather block. The geocode is ~1s (Apple) + Open-Meteo is ~1s,
        // adding ~2s to the total generate time (Claude is the slow
        // path at ~15s anyway). Best-effort: any failure here just
        // means the report renders without a weather chip.
        let addressToGeocode = effectiveAddress
            ?? report?.address
            ?? ""
        await enrichWeatherIfPossible(sessionId: sid, address: addressToGeocode)
        do {
            let envelope = try await APIClient.shared.generateReport(sessionId: sid)
            report = envelope.report
            reportMeta = envelope.reportMeta
        } catch {
            generateError = error.localizedDescription
        }
    }

    private func enrichWeatherIfPossible(sessionId: String, address: String) async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let coord = await Geocoder.coordinate(forAddress: trimmed) else { return }
        _ = try? await APIClient.shared.setSessionCoordinate(
            sessionId: sessionId,
            latitude: coord.latitude,
            longitude: coord.longitude
        )
    }

    private func refineWithAI(instruction: String) async {
        guard let sid = effectiveSessionId else { return }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        refining = true
        refineError = nil
        defer { refining = false }
        do {
            let envelope = try await APIClient.shared.refineReport(
                sessionId: sid, instruction: trimmed
            )
            report = envelope.report
            reportMeta = envelope.reportMeta
            showRefineSheet = false
        } catch let err {
            refineError = err.localizedDescription
        }
    }

    private func exportPdf() {
        guard let sid = effectiveSessionId else { return }
        exportingPdf = true
        let urlReq = APIClient.shared.reportHtmlRequest(sessionId: sid)
        ReportPDFRenderer.render(request: urlReq) { data in
            DispatchQueue.main.async {
                exportingPdf = false
                if let data {
                    pdfData = data
                    showShare = true
                }
            }
        }
    }

    private var pdfFilename: String {
        let raw = (report?.address.isEmpty == false ? report!.address
                   : (effectiveAddress ?? "open-house"))
        let safe = raw
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_")).inverted)
            .joined()
            .lowercased()
        return "open-house-report-\(safe).pdf"
    }

    private func relativeAgo(_ iso: String) -> String {
        let parser = ISO8601DateFormatter.fractionalSeconds
        guard let d = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return ""
        }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: – Generating animation
//
// Shown two ways:
//   .generating — first-open auto-start. Centered, big stage label,
//                 brand-gold pulse, takes 10-20s for Sonnet.
//   .refining   — overlays the existing report at lower opacity while
//                 Haiku rewrites (~2-4s). Smaller, tighter copy.
//
// Stages cycle every ~3.5s so the agent always sees motion (Claude's
// total latency is well above a single-stage attention span). Tasks
// re-spawn on view appear; cancel themselves on disappear.

private struct GeneratingAnimation: View {
    enum Kind { case generating, refining }
    let kind: Kind

    private static let generateStages = [
        "Reading the room…",
        "Spotting recurring themes…",
        "Drafting your take…",
        "Polishing the headline…",
        "Almost there…",
    ]
    private static let refineStages = [
        "Reading your request…",
        "Rewriting the report…",
        "Almost done…",
    ]

    private var stages: [String] {
        kind == .refining ? Self.refineStages : Self.generateStages
    }
    private var subtitle: String {
        kind == .refining
            ? "Haiku is editing the report — usually 2-4 seconds."
            : "Claude is reading the session and writing the report. Usually 15-25 seconds."
    }
    private var titleSize: CGFloat { kind == .refining ? 22 : 28 }
    private var orbSize: CGFloat { kind == .refining ? 14 : 22 }

    @State private var stageIndex = 0
    @State private var pulse = false
    @State private var bloom = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                // Soft gold bloom that grows as the animation runs.
                // Anchored behind the orb so the loader has visual mass.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                FoyerTheme.gold.opacity(0.35),
                                FoyerTheme.gold.opacity(0.08),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: bloom ? 140 : 60
                        )
                    )
                    .frame(width: 240, height: 240)
                    .blur(radius: 10)
                    .opacity(bloom ? 1 : 0.5)

                // Pulsing gold orb — the brand's heartbeat at the
                // center of the loader. Scale + glow tied to the same
                // value so the motion reads as one breath.
                Circle()
                    .fill(FoyerTheme.gold)
                    .frame(width: orbSize, height: orbSize)
                    .shadow(color: FoyerTheme.gold.opacity(0.7),
                            radius: pulse ? 22 : 10, y: 0)
                    .scaleEffect(pulse ? 1.35 : 0.85)
                    .opacity(pulse ? 0.7 : 1.0)
            }
            .frame(height: 200)

            // Cycling stage label. Each transition is a slide+fade so
            // the text exchange reads as deliberate progress, not a
            // glitch.
            ZStack {
                ForEach(Array(stages.enumerated()), id: \.offset) { idx, stage in
                    if idx == stageIndex {
                        Text(stage)
                            .font(.system(size: titleSize, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                            .tracking(-0.3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal:   .move(edge: .top).combined(with: .opacity)
                            ))
                    }
                }
            }
            .frame(minHeight: 36)
            .animation(.easeInOut(duration: 0.45), value: stageIndex)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .onAppear { startMotion() }
    }

    private func startMotion() {
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
            pulse = true
        }
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            bloom = true
        }
        // Drive the stage cycle from a detached Task so we don't
        // block the main run loop. Bails out cleanly when the view
        // disappears (Task.isCancelled handled via try? sleep).
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                if Task.isCancelled { return }
                stageIndex = (stageIndex + 1) % stages.count
            }
        }
    }
}

// MARK: – AI Refine sheet
//
// Replaces the old per-section TextEditor flow per the agent's spec.
// Agent describes what's wrong in plain English; Haiku rewrites the
// whole report preserving everything they didn't touch.

private struct AIRefineSheet: View {
    let refining: Bool
    let error: String?
    var onSubmit: (String) -> Void
    var onRegenerate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var instruction: String = ""
    @FocusState private var focused: Bool

    // Quick-pick chips for common refinements — saves typing, primes
    // the agent on what the model can actually do well. Tapping one
    // pastes into the editor so it's still editable before submit.
    private let presets: [String] = [
        "Tighten the agent take",
        "Make the headline punchier",
        "Soften the concerns",
        "Drop the standout visitors section",
        "Lengthen the next steps",
        "Less salesy, more honest",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if instruction.isEmpty {
                            Text("Tell me what's wrong. \"Tighten the agent take,\" \"add a note about price,\" \"sound less salesy.\"")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8).padding(.leading, 4)
                        }
                        TextEditor(text: $instruction)
                            .frame(minHeight: 120)
                            .focused($focused)
                    }
                } header: {
                    Text("What should change?")
                } footer: {
                    Text("Haiku rewrites the report based on your instruction — usually 2-4 seconds. Fields you don't mention stay exactly as they are.")
                }
                Section("Quick edits") {
                    ForEach(presets, id: \.self) { p in
                        Button { instruction = p } label: {
                            HStack {
                                Text(p)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button(role: .destructive) {
                        onRegenerate()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Regenerate from scratch")
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Throws away the current report and starts over with a fresh Claude generation.")
                }
            }
            .navigationTitle("Edit with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSubmit(instruction)
                    } label: {
                        HStack(spacing: 4) {
                            if refining { ProgressView().scaleEffect(0.7) }
                            Text(refining ? "Rewriting…" : "Rewrite")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(refining || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: – Send sheet

private struct SendReportSheet: View {
    let sessionId: String
    let report: SessionReport
    let initialEmail: String
    let initialName: String
    var onSent: (ReportMeta) -> Void
    var onHomeownerUpdate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var to: String
    @State private var name: String
    @State private var subject: String
    @State private var greeting: String
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false

    init(
        sessionId: String,
        report: SessionReport,
        initialEmail: String,
        initialName: String,
        onSent: @escaping (ReportMeta) -> Void,
        onHomeownerUpdate: @escaping (String, String) -> Void
    ) {
        self.sessionId = sessionId
        self.report = report
        self.initialEmail = initialEmail
        self.initialName = initialName
        self.onSent = onSent
        self.onHomeownerUpdate = onHomeownerUpdate
        _to = State(initialValue: initialEmail)
        _name = State(initialValue: initialName)
        _subject = State(initialValue: "Open House Report — \(report.address)")
        let greet = initialName.isEmpty
            ? "Hi — here's the recap from your open house."
            : "Hi \(initialName.split(separator: " ").first.map(String.init) ?? initialName) — here's the recap from your open house."
        _greeting = State(initialValue: greet)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("Email", text: $to)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Homeowner name (optional)", text: $name)
                        .textContentType(.name)
                }
                Section("Subject") {
                    TextField("Subject", text: $subject)
                }
                Section("Greeting (optional — appears above the report)") {
                    TextEditor(text: $greeting)
                        .frame(minHeight: 88)
                }
                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if sending {
                                ProgressView()
                            } else if sent {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(sent ? "Sent!" : (sending ? "Sending…" : "Send report"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(sending || sent || to.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Send report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func send() async {
        sending = true
        error = nil
        defer { sending = false }
        let toClean = to.trimmingCharacters(in: .whitespaces)
        let nameClean = name.trimmingCharacters(in: .whitespaces)
        // Save homeowner email back to the session before sending so the
        // next session opening already has it filled in.
        if toClean != initialEmail || nameClean != initialName {
            do {
                try await APIClient.shared.setHomeowner(
                    sessionId: sessionId,
                    email: toClean,
                    name: nameClean
                )
                onHomeownerUpdate(toClean, nameClean)
            } catch {
                // Don't block the send — homeowner persist is a side
                // effect, not the user's primary intent.
            }
        }
        do {
            let result = try await APIClient.shared.sendReport(
                sessionId: sessionId,
                to: toClean,
                subject: subject,
                greeting: greeting.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if let meta = result.reportMeta {
                onSent(meta)
            }
            sent = true
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch APIClient.SendEmailError.gmailNotConnected {
            error = "Gmail isn't connected. Open Profile → Connect Gmail and try again."
        } catch let err {
            error = err.localizedDescription
        }
    }
}

// MARK: – Homeowner sheet

private struct HomeownerSheet: View {
    let sessionId: String
    let initialEmail: String
    let initialName: String
    var onSaved: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var name: String
    @State private var saving = false
    @State private var error: String?

    init(
        sessionId: String,
        initialEmail: String,
        initialName: String,
        onSaved: @escaping (String, String) -> Void
    ) {
        self.sessionId = sessionId
        self.initialEmail = initialEmail
        self.initialName = initialName
        self.onSaved = onSaved
        _email = State(initialValue: initialEmail)
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Homeowner") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Name (optional)", text: $name)
                        .textContentType(.name)
                }
                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if saving { ProgressView() }
                            Text(saving ? "Saving…" : "Save")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(saving)
                }
            }
            .navigationTitle("Homeowner contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await APIClient.shared.setHomeowner(
                sessionId: sessionId,
                email: email.trimmingCharacters(in: .whitespaces),
                name: name.trimmingCharacters(in: .whitespaces)
            )
            onSaved(email, name)
        } catch let err {
            error = err.localizedDescription
        }
    }
}

// MARK: – PDF rendering via WKWebView

// WKWebView is the cleanest way to turn the backend's HTML report into a
// nicely-formatted PDF locally. We load the authenticated /report.html
// request, wait for didFinish, then call createPDF(...) which uses the
// system's print-style rendering pipeline (= Apple-grade typography
// instead of a third-party PDF library).
//
// The renderer holds a strong reference to itself until the PDF lands so
// the WKWebView isn't deallocated mid-load — without that, you get a
// silent nil callback in the wild on slow networks.
final class ReportPDFRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let completion: (Data?) -> Void
    private var selfRef: ReportPDFRenderer?

    static func render(request: URLRequest, completion: @escaping (Data?) -> Void) {
        let cfg = WKWebViewConfiguration()
        // 8.5" x 11" at 72dpi roughly — gives the PDF reasonable
        // proportions. createPDF respects the content's natural width.
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let wv = WKWebView(frame: bounds, configuration: cfg)
        let renderer = ReportPDFRenderer(webView: wv, completion: completion)
        wv.navigationDelegate = renderer
        renderer.selfRef = renderer
        wv.load(request)
    }

    private init(webView: WKWebView, completion: @escaping (Data?) -> Void) {
        self.webView = webView
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Tiny delay to let webfonts & background images settle before
        // snapshotting. createPDF without this occasionally captures a
        // blank frame on the first paint cycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let cfg = WKPDFConfiguration()
            self.webView.createPDF(configuration: cfg) { result in
                switch result {
                case .success(let data): self.completion(data)
                case .failure:           self.completion(nil)
                }
                self.selfRef = nil  // release the self-reference
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion(nil)
        selfRef = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completion(nil)
        selfRef = nil
    }
}

// MARK: – Share sheet bridge

// UIActivityViewController wrapped for SwiftUI. ShareLink would be
// nicer but doesn't easily handle in-memory PDF Data + custom filename
// in the way receivers expect (Mail attaches it correctly; AirDrop
// uses the filename for the receiver-side name).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// Custom UIActivityItemSource so the receiver sees a real filename
// ("open-house-report-1936-17th.pdf") instead of a generic
// "Activity.pdf". Mail and Files honor this; AirDrop too.
final class PDFShareItem: NSObject, UIActivityItemSource {
    let data: Data
    let filename: String

    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        data
    }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // Write to a temp file so receivers attach with the right name.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return url
    }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        filename
    }
}
