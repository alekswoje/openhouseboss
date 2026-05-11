import SwiftUI

// Sessions home — the agent's first screen when they open the iPhone app.
// Top stats, today's live session, this week's history. Mirrors ScreenSessions
// in web/hero-devices design.
struct SessionsView: View {
    @State private var goToRecorder = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    statsRow
                    todaySection
                    weekSection
                    Spacer().frame(height: 120)
                }
            }

            glassTabBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $goToRecorder) { SetupView() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "OpenHouseBoss", color: FoyerTheme.gold)
                Text("Sessions")
                    .foyerDisplay(34)
                    .foregroundStyle(FoyerTheme.cream)
            }
            Spacer()
            Button { goToRecorder = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 36, height: 36)
                    .background(FoyerTheme.gold, in: Circle())
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 22) {
            stat(value: "14", label: "Open houses")
            stat(value: "47", label: "Guests met")
            stat(value: "$2.4", suffix: "m", label: "In pipeline", suffixGold: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func stat(value: String, suffix: String? = nil, label: String, suffixGold: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value).foyerDisplay(28).foregroundStyle(FoyerTheme.cream)
                if let s = suffix {
                    Text(s)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(suffixGold ? FoyerTheme.gold : FoyerTheme.cream)
                }
            }
            Eyebrow(text: label, color: FoyerTheme.gold)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Today")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("412 W 78th St ").foyerDisplay(19)
                                .foregroundStyle(FoyerTheme.cream)
                            Text("Apt 4-A")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(FoyerTheme.gold)
                        }
                        Text("SAT 2:00 — 4:00 PM · LIVE NOW")
                            .font(.system(size: 10, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(FoyerTheme.terracotta)
                            .frame(width: 8, height: 8)
                            .shadow(color: FoyerTheme.terracotta, radius: 4)
                        Text("REC")
                            .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                }
                Text("3 guests · 47 minutes in")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "This week")
            ForEach(Array(weekSessions.enumerated()), id: \.element.id) { idx, s in
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.address).font(.system(size: 15))
                            .foregroundStyle(FoyerTheme.cream)
                        Text("\(s.date) · \(s.guests) GUESTS")
                            .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Text("\(s.hot)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    if idx < weekSessions.count - 1 { Hairline() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var glassTabBar: some View {
        HStack {
            ForEach(["Sessions", "Visitors", "Insights", "Profile"], id: \.self) { tab in
                Text(tab.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(tab == "Sessions" ? FoyerTheme.gold : FoyerTheme.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(FoyerTheme.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
    }

    private struct WeekRow: Identifiable {
        let id = UUID()
        let address: String
        let date: String
        let guests: Int
        let hot: Int
    }

    private var weekSessions: [WeekRow] {
        [
            .init(address: "88 Greene · Loft 6",   date: "SUN MAY 4",  guests: 5, hot: 2),
            .init(address: "21 Charles · GDN",     date: "SAT MAY 3",  guests: 4, hot: 1),
            .init(address: "300 E 79 · 12-D",      date: "SUN APR 27", guests: 7, hot: 3),
        ]
    }
}

#Preview { NavigationStack { SessionsView() } }
