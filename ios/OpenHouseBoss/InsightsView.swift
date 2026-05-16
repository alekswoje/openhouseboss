import SwiftUI
import Charts

// Insights — cross-session stats dashboard. Where the agent figures out
// which day of the week, what hour, and which listings actually convert.
// Backend (backend/stats.py) does all the aggregation server-side; this
// view just renders.
struct InsightsView: View {
    @State private var period: InsightsPeriod = .month
    @State private var insights: AgentInsights = .empty
    @State private var loading = true
    @State private var loadError: String?

    @Environment(\.horizontalSizeClass) private var hSize
    private var isCompact: Bool { hSize == .compact }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                periodPicker
                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if insights.sessionCount == 0 {
                    emptyState
                } else {
                    kpiGrid
                    bestTimesCard
                    dayOfWeekChart
                    hourOfDayChart
                    recentSessionsList
                }
                Spacer().frame(height: 60)
            }
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isCompact ? 16 : 44)
            .padding(.top, isCompact ? 18 : 36)
            .padding(.bottom, isCompact ? 32 : 120)
        }
        .refreshable { await load() }
        .background(Color.black)
        .task { await load() }
        .onChange(of: period) { _, _ in
            Task { await load() }
        }
    }

    // MARK: – Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INSIGHTS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(FoyerTheme.gold)
            Text("Your open-house numbers")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(-0.5)
            Text("Data is gold. Every session you record makes these sharper.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
        }
    }

    private var periodPicker: some View {
        // Segmented control across the four windows. Each tap re-fetches.
        Picker("Period", selection: $period) {
            ForEach(InsightsPeriod.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    // KPI tiles — the headline numbers at the top. Two rows on iPad
    // (compact = single column).
    private var kpiGrid: some View {
        let cols = isCompact
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 12) {
            kpiTile(value: "\(insights.sessionCount)",
                    label: "OPEN HOUSES",
                    sub: insights.sessionCount == 1 ? "session" : "sessions")
            kpiTile(value: "\(insights.visitorCount)",
                    label: "VISITORS",
                    sub: "avg \(String(format: "%.1f", insights.avgVisitorsPerSession)) / session")
            kpiTile(value: "\(insights.hotVisitorCount)",
                    label: "HOT LEADS",
                    sub: "score 70+",
                    tone: insights.hotVisitorCount > 0 ? .gold : .neutral)
            kpiTile(value: String(format: "%.0f", insights.avgScore),
                    label: "AVG SCORE",
                    sub: "/100 interest")
            kpiTile(value: "\(insights.reportsSentCount)",
                    label: "REPORTS SENT",
                    sub: insights.sessionCount == 0
                         ? "—"
                         : "\(Int(insights.reportSendRate * 100))% of sessions")
            kpiTile(value: String(format: "%.0f", insights.avgDurationMin),
                    label: "AVG LENGTH",
                    sub: "minutes")
        }
    }

    private enum KPITone { case neutral, gold }
    private func kpiTile(value: String, label: String, sub: String, tone: KPITone = .neutral) -> some View {
        let valueColor: Color = tone == .gold ? FoyerTheme.gold : FoyerTheme.cream
        return VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(valueColor)
                .tracking(-0.5)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textMuted)
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(FoyerTheme.creamDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(FoyerTheme.hairline, lineWidth: 0.5)
        )
    }

    // Best day + best hour — the "actionable" callouts. Pull from the
    // backend's pre-computed best_day_of_week / best_hour_of_day so we
    // don't re-derive on the client.
    @ViewBuilder
    private var bestTimesCard: some View {
        if insights.bestDayOfWeek != nil || insights.bestHourOfDay != nil {
            HStack(spacing: 14) {
                if let dow = insights.bestDayOfWeek,
                   let row = insights.byDayOfWeek.first(where: { $0.dayOfWeek == dow }) {
                    bestCallout(
                        eyebrow: "BEST DAY",
                        big: row.label,
                        detail: "\(row.visitors) visitor\(row.visitors == 1 ? "" : "s") across \(row.sessions) session\(row.sessions == 1 ? "" : "s")"
                    )
                }
                if let hour = insights.bestHourOfDay,
                   let row = insights.byHourOfDay.first(where: { $0.hourOfDay == hour }) {
                    bestCallout(
                        eyebrow: "BEST HOUR",
                        big: localHourLabel(utcHour: hour),
                        detail: "\(row.visitors) visitor\(row.visitors == 1 ? "" : "s") across \(row.sessions) session\(row.sessions == 1 ? "" : "s")"
                    )
                }
            }
        }
    }

    private func bestCallout(eyebrow: String, big: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.gold)
            Text(big)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(-0.4)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(FoyerTheme.creamDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [FoyerTheme.gold.opacity(0.18), FoyerTheme.gold.opacity(0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(FoyerTheme.gold.opacity(0.35), lineWidth: 0.5)
        )
    }

    // Day-of-week chart — fills in missing days as zero so the bar
    // chart always reads as a full week (not just the buckets with
    // recorded sessions).
    private var dayOfWeekChart: some View {
        let filled = (0..<7).map { dow -> InsightsDayOfWeek in
            insights.byDayOfWeek.first(where: { $0.dayOfWeek == dow })
                ?? InsightsDayOfWeek(dayOfWeek: dow, sessions: 0, visitors: 0, hot: 0, avgScore: 0)
        }
        return VStack(alignment: .leading, spacing: 10) {
            chartHeader("VISITORS BY DAY OF WEEK")
            Chart {
                ForEach(filled) { row in
                    BarMark(
                        x: .value("Day", row.label),
                        y: .value("Visitors", row.visitors)
                    )
                    .foregroundStyle(FoyerTheme.gold)
                    .annotation(position: .top) {
                        if row.visitors > 0 {
                            Text("\(row.visitors)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(FoyerTheme.creamDim)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(FoyerTheme.creamDim)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(FoyerTheme.hairline)
                    AxisValueLabel().foregroundStyle(FoyerTheme.textMuted)
                }
            }
            .frame(height: 200)
        }
        .padding(16)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // Hour-of-day chart — sparse data is common (most sessions cluster
    // in the early afternoon) so we only render hours that actually
    // have sessions, not the full 24.
    private var hourOfDayChart: some View {
        let rows = insights.byHourOfDay
        return VStack(alignment: .leading, spacing: 10) {
            chartHeader("VISITORS BY HOUR")
            if rows.isEmpty {
                Text("Not enough data yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
                    .padding(.vertical, 20)
            } else {
                Chart {
                    ForEach(rows) { row in
                        BarMark(
                            x: .value("Hour", localHourLabel(utcHour: row.hourOfDay)),
                            y: .value("Visitors", row.visitors)
                        )
                        .foregroundStyle(FoyerTheme.sage)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(FoyerTheme.creamDim)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(FoyerTheme.hairline)
                        AxisValueLabel().foregroundStyle(FoyerTheme.textMuted)
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(16)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // Recent sessions — last 20, with the actionable bits inline so the
    // agent can see at a glance which ones converted (hot leads + report
    // sent) without opening each session detail.
    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            chartHeader("RECENT SESSIONS")
            VStack(spacing: 8) {
                ForEach(insights.recentSessions) { row in
                    recentRow(row)
                }
            }
        }
    }

    private func recentRow(_ row: InsightsSessionRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.address ?? "Open house")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                Text(rowSubtitle(row))
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            Spacer()
            // Hot pill — gives the agent an instant scan signal for
            // sessions that produced real prospects.
            if row.hotVisitorCount > 0 {
                Text("\(row.hotVisitorCount) HOT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(FoyerTheme.gold, in: Capsule())
            }
            if row.reportSent {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.sage)
            }
        }
        .padding(12)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func rowSubtitle(_ row: InsightsSessionRow) -> String {
        var bits: [String] = []
        if let iso = row.createdAt, let when = parseIso(iso) {
            bits.append(when.formatted(date: .abbreviated, time: .shortened))
        }
        bits.append("\(row.visitorCountTotal) visitor\(row.visitorCountTotal == 1 ? "" : "s")")
        if row.durationMin > 0 { bits.append("\(row.durationMin) min") }
        bits.append("avg \(Int(row.avgVisitorScore))")
        return bits.joined(separator: " · ")
    }

    private func chartHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(FoyerTheme.gold)
    }

    // MARK: – States

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(FoyerTheme.gold).scaleEffect(0.9)
            Text("Loading insights…")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COULDN'T LOAD")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.terracotta)
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.cream)
            Button { Task { await load() } } label: {
                Text("Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(white: 0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
            Text("Record a few open houses and your numbers will show up here — best days, hottest hours, and which listings convert.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: – Actions

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            insights = try await APIClient.shared.getInsights(period: period)
        } catch {
            loadError = error.localizedDescription
        }
    }

    // Backend stores hour_of_day in UTC (Python's datetime.hour). For
    // display we shift to the device's local timezone so "best hour =
    // 13" reads as the agent's actual 1pm, not UTC 1pm.
    private func localHourLabel(utcHour: Int) -> String {
        var comps = DateComponents()
        comps.hour = utcHour
        comps.timeZone = TimeZone(identifier: "UTC")
        let cal = Calendar.current
        guard let date = cal.date(from: comps) else { return "\(utcHour)" }
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"
        fmt.timeZone = .current
        return fmt.string(from: date)
    }

    private func parseIso(_ s: String) -> Date? {
        ISO8601DateFormatter.fractionalSeconds.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }
}
