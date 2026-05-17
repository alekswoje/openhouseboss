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
    @State private var saving = false
    @State private var saveError: String?

    @State private var editing = false
    @State private var draft: SessionReport?

    @State private var showSendSheet = false
    @State private var showRegenerateConfirm = false
    @State private var showHomeownerSheet = false

    @State private var pdfData: Data?
    @State private var showShare = false
    @State private var exportingPdf = false

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
                    BackBar(crumbs: ["Sessions", "Report"], onBack: { back() })
                    header
                    content
                    Spacer().frame(height: 160)
                }
                .padding(.top, 8)
            }

            if report != nil && !editing {
                actionBar
            } else if editing {
                editActionBar
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
        .alert("Regenerate report?", isPresented: $showRegenerateConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Regenerate", role: .destructive) {
                Task { await generate(force: true) }
            }
        } message: {
            Text("This will replace your edits with a fresh Claude-generated report.")
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
        if loading {
            loadingCard("Loading report")
        } else if generating {
            loadingCard("Generating report — Claude is reading the room. ~15-25s.")
        } else if let err = loadError ?? generateError {
            errorCard(err)
        } else if let r = report {
            if editing, let d = draft {
                editingBody(d)
            } else {
                renderedBody(r)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSurface(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Nothing yet", color: FoyerTheme.gold)
                    Text("Generate an open house report for the homeowner.")
                        .font(.system(size: 16))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineSpacing(3)
                    Text("Claude reads the session transcript and your per-visitor notes, then drafts a one-page report: turnout, recurring themes, price reaction, standout visitors, and recommended next steps. You can edit before sending.")
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.creamDim)
                        .lineSpacing(3)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button { Task { await generate(force: false) } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Generate report")
                }
            }
            .buttonStyle(FoyerPrimaryButton())
            .disabled(effectiveSessionId == nil || effectiveStatus != "ready")

            if effectiveStatus == "processing" {
                Text("Waiting on the session to finish processing.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textMuted)
            } else if effectiveStatus == "error" {
                Text("This session errored out — nothing to report on.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textMuted)
            } else if effectiveSessionId == nil {
                Text("No active session.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
        }
        .padding(.horizontal, 20)
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

    // MARK: – Edit mode

    @ViewBuilder
    private func editingBody(_ d: SessionReport) -> some View {
        let binding = Binding<SessionReport>(
            get: { draft ?? d },
            set: { draft = $0 }
        )
        VStack(alignment: .leading, spacing: 14) {
            editField(title: "Headline", text: binding.headline, height: 80)
            editList(title: "TL;DR bullets", items: binding.tldr)
            editField(title: "Traffic summary", text: binding.trafficSummary, height: 90)
            editThemes(title: "Highlights", themes: binding.highlights)
            editThemes(title: "Concerns + objections", themes: binding.concerns)
            editField(title: "Price signal", text: binding.priceSignal, height: 90)
            editStandouts(visitors: binding.standoutVisitors)
            editField(title: "My take", text: binding.agentTake, height: 120)
            editList(title: "Recommended next steps", items: binding.nextSteps)
            if let err = saveError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.terracotta)
            }
        }
        .padding(.horizontal, 20)
    }

    private func editField(title: String, text: Binding<String>, height: CGFloat) -> some View {
        GlassSurface(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: title, color: FoyerTheme.gold)
                TextEditor(text: text)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: height)
                    .background(FoyerTheme.bgElev.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editList(title: String, items: Binding<[String]>) -> some View {
        GlassSurface(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: title, color: FoyerTheme.gold)
                    Spacer()
                    Button {
                        items.wrappedValue.append("")
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                }
                ForEach(items.wrappedValue.indices, id: \.self) { idx in
                    HStack(alignment: .top, spacing: 8) {
                        TextField("Bullet", text: items[idx], axis: .vertical)
                            .font(.system(size: 13))
                            .foregroundStyle(FoyerTheme.cream)
                            .padding(8)
                            .background(FoyerTheme.bgElev.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 6))
                        Button {
                            items.wrappedValue.remove(at: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(FoyerTheme.terracotta.opacity(0.7))
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editThemes(title: String, themes: Binding<[ReportTheme]>) -> some View {
        GlassSurface(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: title, color: FoyerTheme.gold)
                    Spacer()
                    Button {
                        themes.wrappedValue.append(ReportTheme(
                            title: "New theme", frequency: 0, summary: "", quotes: []
                        ))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                }
                ForEach(themes.wrappedValue.indices, id: \.self) { idx in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Title", text: themes[idx].title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FoyerTheme.cream)
                            Spacer()
                            Stepper(
                                "\(themes[idx].frequency.wrappedValue) visitors",
                                value: themes[idx].frequency,
                                in: 0...50
                            )
                            .labelsHidden()
                            Text("\(themes[idx].frequency.wrappedValue) ppl")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(FoyerTheme.textMuted)
                            Button {
                                themes.wrappedValue.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(FoyerTheme.terracotta.opacity(0.7))
                            }
                        }
                        TextField("Summary", text: themes[idx].summary, axis: .vertical)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.creamDim)
                    }
                    .padding(10)
                    .background(FoyerTheme.bgElev.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editStandouts(visitors: Binding<[ReportStandoutVisitor]>) -> some View {
        GlassSurface(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Standout visitors", color: FoyerTheme.gold)
                    Spacer()
                    Button {
                        visitors.wrappedValue.append(ReportStandoutVisitor(
                            label: "New visitor", score: 0, summary: "", followUpStatus: ""
                        ))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                }
                ForEach(visitors.wrappedValue.indices, id: \.self) { idx in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Label", text: visitors[idx].label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FoyerTheme.cream)
                            Spacer()
                            Stepper(
                                "\(visitors[idx].score.wrappedValue)",
                                value: visitors[idx].score,
                                in: 0...100,
                                step: 5
                            )
                            .labelsHidden()
                            Text("\(visitors[idx].score.wrappedValue)/100")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(FoyerTheme.textMuted)
                            Button {
                                visitors.wrappedValue.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(FoyerTheme.terracotta.opacity(0.7))
                            }
                        }
                        TextField("Summary", text: visitors[idx].summary, axis: .vertical)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.creamDim)
                        TextField("Follow-up status", text: visitors[idx].followUpStatus)
                            .font(.system(size: 12))
                            .italic()
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                    .padding(10)
                    .background(FoyerTheme.bgElev.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: – Action bars

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { startEditing() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Edit").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(FoyerTheme.cream)
                .background(FoyerTheme.bgElev, in: Capsule())
                .overlay(Capsule().stroke(FoyerTheme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button { exportPdf() } label: {
                HStack(spacing: 6) {
                    if exportingPdf {
                        ProgressView().scaleEffect(0.7).tint(FoyerTheme.cream)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("PDF").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(FoyerTheme.cream)
                .background(FoyerTheme.bgElev, in: Capsule())
                .overlay(Capsule().stroke(FoyerTheme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(exportingPdf)

            Spacer()

            Button { showSendSheet = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Send to homeowner")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .foregroundStyle(FoyerTheme.inkOnGold)
                .background(FoyerTheme.gold, in: Capsule())
                .shadow(color: FoyerTheme.gold.opacity(0.4), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private var editActionBar: some View {
        HStack(spacing: 10) {
            Button { cancelEditing() } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .foregroundStyle(FoyerTheme.creamDim)
                    .background(FoyerTheme.bgElev, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { showRegenerateConfirm = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Regenerate").font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(FoyerTheme.creamDim)
                .background(FoyerTheme.bgElev.opacity(0.6), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button { Task { await saveEdits() } } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView().scaleEffect(0.7).tint(FoyerTheme.inkOnGold)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(saving ? "Saving" : "Save edits")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .foregroundStyle(FoyerTheme.inkOnGold)
                .background(FoyerTheme.gold, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saving)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
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

    private func startEditing() {
        draft = report
        editing = true
    }

    private func cancelEditing() {
        draft = nil
        editing = false
        saveError = nil
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
        } catch {
            loadError = error.localizedDescription
        }
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
            editing = false
            draft = nil
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

    private func saveEdits() async {
        guard let sid = effectiveSessionId, let d = draft else { return }
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            let envelope = try await APIClient.shared.updateReport(sessionId: sid, report: d)
            report = envelope.report
            reportMeta = envelope.reportMeta
            editing = false
            draft = nil
        } catch {
            saveError = error.localizedDescription
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
