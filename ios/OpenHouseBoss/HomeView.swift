import SwiftUI

// Sessions home — real list pulled from the backend. Empty state when none
// exist; tap a row to reopen it in SummaryView; "+" starts a new one.
struct SessionsView: View {
    @State private var store = SessionStore.shared
    @State private var goToSetup = false
    @State private var goToPast = false
    @State private var openedPastId: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    statsRow
                    sessionsContent
                    Spacer().frame(height: 120)
                }
            }

            glassTabBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Log.ui("SessionsView appeared") }
        .task {
            Log.ui("SessionsView.task fired refreshSessions")
            await store.refreshSessions()
        }
        .navigationDestination(isPresented: $goToSetup) { SetupView() }
        .navigationDestination(isPresented: $goToPast) {
            if let id = openedPastId {
                SummaryView(pastSessionId: id)
            }
        }
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
            Button {
                store.reset()
                goToSetup = true
            } label: {
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
            stat(value: "\(store.pastSessions.count)", label: "Open houses")
            stat(value: "\(totalGuests)", label: "Guests met")
            stat(value: "\(readyCount)", label: "Drafts ready")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).foyerDisplay(28).foregroundStyle(FoyerTheme.cream)
            Eyebrow(text: label, color: FoyerTheme.gold)
        }
    }

    @ViewBuilder
    private var sessionsContent: some View {
        if let err = store.listError {
            errorState(err)
        } else if store.pastSessions.isEmpty && !store.listLoading {
            emptyState
        } else {
            sessionList
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "No sessions yet")
            Text("Tap + to start your first open house. We'll record, transcribe, identify each guest, and draft a follow-up.")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Can't reach the backend", color: FoyerTheme.terracotta)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.cream)
            Text("Make sure the server is running at \(Config.backendURL.absoluteString).")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FoyerTheme.terracottaSoft, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FoyerTheme.terracotta, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Recent")
            ForEach(Array(store.pastSessions.enumerated()), id: \.element.id) { idx, s in
                Button {
                    openedPastId = s.id
                    goToPast = true
                } label: {
                    sessionRow(s)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if idx < store.pastSessions.count - 1 { Hairline() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func sessionRow(_ s: SessionSummary) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(s.displayTitle)
                    .font(.system(size: 16))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(formatDate(s.createdDate))
                        .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                    statusChip(s.status)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                if s.visitorCount > 0 {
                    Text("\(s.visitorCount)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                    Text("GUESTS")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        switch status {
        case "ready":
            Text("READY")
                .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                .foregroundStyle(FoyerTheme.sage)
        case "processing":
            HStack(spacing: 4) {
                Circle().fill(FoyerTheme.gold).frame(width: 5, height: 5)
                Text("PROCESSING")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(FoyerTheme.gold)
            }
        case "error":
            Text("ERROR")
                .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                .foregroundStyle(FoyerTheme.terracotta)
        default:
            EmptyView()
        }
    }

    private func formatDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d · h:mm a"
        return f.string(from: d).uppercased()
    }

    private var totalGuests: Int {
        store.pastSessions.reduce(0) { $0 + $1.visitorCount }
    }
    private var readyCount: Int {
        store.pastSessions.filter { $0.status == "ready" }.count
    }

    // Solid background — `.ultraThinMaterial` continuously re-blurs the
    // content underneath on every scroll frame, which was the main cause of
    // home-screen scroll lag on real devices.
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
        .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(FoyerTheme.borderStrong, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
    }
}

#Preview { NavigationStack { SessionsView() } }
