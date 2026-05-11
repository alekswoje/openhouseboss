import SwiftUI

// iPad landscape — the agent surface running on the open-house iPad.
// Side rail + main content; tabs swap between Home, Kiosk form, Live, Leads.
struct IPadAgentApp: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home, listings, sessions, leads, templates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "Home"
            case .listings: return "Listings"
            case .sessions: return "Sessions"
            case .leads: return "Leads"
            case .templates: return "Templates"
            }
        }
        var systemImage: String {
            switch self {
            case .home: return "house"
            case .listings: return "rectangle.grid.2x2"
            case .sessions: return "circle.dashed.inset.filled"
            case .leads: return "person.2"
            case .templates: return "doc.text"
            }
        }
    }

    @State private var tab: Tab = .home

    var body: some View {
        HStack(spacing: 0) {
            sideRail
            Group {
                switch tab {
                case .home:      IPadHome { tab = .sessions }
                case .listings:  IPadHome { tab = .sessions } // collapse — only one listing today
                case .sessions:  IPadSessionLeads()
                case .leads:     IPadSessionLeads()
                case .templates: IPadKioskForm()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FoyerTheme.bgDeep.ignoresSafeArea())
    }

    private var sideRail: some View {
        VStack(spacing: 22) {
            // Crest mark
            Text("F")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 38, height: 38)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(FoyerTheme.gold, lineWidth: 1))
                .padding(.top, 6)

            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 6) {
                        Image(systemName: t.systemImage)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(tab == t ? FoyerTheme.gold : FoyerTheme.hairline, lineWidth: 1)
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(tab == t ? FoyerTheme.goldSoft : Color.clear)
                            )
                        Text(t.title.uppercased())
                            .font(.system(size: 8, design: .monospaced)).tracking(1.4)
                    }
                    .foregroundStyle(tab == t ? FoyerTheme.gold : FoyerTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            Spacer()

            // Profile avatar
            Text("JH")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 32, height: 32)
                .background(FoyerTheme.bgElev2, in: Circle())
                .overlay(Circle().stroke(FoyerTheme.border, lineWidth: 1))
                .padding(.bottom, 8)
        }
        .frame(width: 88)
        .padding(.vertical, 18)
        .overlay(alignment: .trailing) {
            Rectangle().fill(FoyerTheme.hairline).frame(width: 1)
        }
    }
}

// ─── iPad Home — greeting + Launch sign-in / Quick record + listing + sessions table.
struct IPadHome: View {
    var onLaunchKiosk: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                topBar
                heroRow
                listingSection
                sessionsTable
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
        }
        .background(FoyerTheme.bgDeep)
    }

    private var topBar: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Rectangle().fill(FoyerTheme.gold).frame(width: 22, height: 1)
                    Text("SATURDAY · MAY 10 · 2:14 PM")
                        .font(.system(size: 11, design: .monospaced)).tracking(2)
                        .foregroundStyle(FoyerTheme.gold)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Good afternoon, ").foyerDisplay(38).foregroundStyle(FoyerTheme.cream)
                    Text("John.")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(FoyerTheme.sage).frame(width: 6, height: 6)
                Text("MLS · LIVE")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                    .foregroundStyle(FoyerTheme.sage)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(FoyerTheme.sageSoft, in: Capsule())
            .overlay(Capsule().stroke(FoyerTheme.sage, lineWidth: 1))
        }
    }

    private var heroRow: some View {
        HStack(spacing: 16) {
            // Primary — launch sign-in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Circle().fill(FoyerTheme.terracotta).frame(width: 6, height: 6)
                    Text("HOSTING NOW · 412 W 78TH ST")
                        .font(.system(size: 11, design: .monospaced)).tracking(2)
                        .foregroundStyle(FoyerTheme.terracotta)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Launch the ").foyerDisplay(36).foregroundStyle(FoyerTheme.cream)
                    Text("sign-in form")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                }
                .padding(.top, 12)
                Text("Pulls today's listing automatically from MLS · photos, price, beds rotate while guests sign in.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .padding(.top, 8)
                Spacer()
                HStack {
                    Button(action: onLaunchKiosk) {
                        HStack(spacing: 10) {
                            Text("Launch sign-in")
                            Text("→").font(.system(size: 18, weight: .medium))
                        }
                    }
                    .buttonStyle(FoyerPrimaryButton())
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            .background(
                ZStack {
                    LinearGradient(colors: [
                        Color(white: 0.094),
                        Color(white: 0.140),
                        Color(white: 0.039),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FoyerTheme.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity)

            // Secondary — quick record
            VStack(alignment: .leading) {
                Eyebrow(text: "Quick capture", color: FoyerTheme.terracotta)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Start ").foyerDisplay(28).foregroundStyle(FoyerTheme.cream)
                    Text("recording")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(FoyerTheme.terracotta)
                }
                Text("No sign-in — just listen. Foyer pulls names + leads from the conversation.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
                    .padding(.top, 6)
                Spacer()
                HStack(spacing: 14) {
                    Circle().fill(FoyerTheme.terracotta).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(FoyerTheme.terracottaSoft, lineWidth: 4))
                    Text("Tap to record")
                        .font(.system(size: 12.5, weight: .medium))
                        .tracking(0.6).textCase(.uppercase)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.terracotta, lineWidth: 1))
                .foregroundStyle(FoyerTheme.terracotta)
            }
            .padding(26)
            .frame(maxWidth: 320, maxHeight: .infinity)
            .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FoyerTheme.hairline, lineWidth: 1))
        }
        .frame(minHeight: 200)
    }

    private var listingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Your open house · pulled from MLS")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Hosting today ").foyerDisplay(22).foregroundStyle(FoyerTheme.cream)
                        Text("2–4 PM")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                }
                Spacer()
                Text("All listings →")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
            }
            HStack(alignment: .top, spacing: 12) {
                propertyCard
                    .frame(maxWidth: .infinity)
                addOpenHouseButton
                    .frame(width: 280)
            }
        }
    }

    private var propertyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [
                    Color(white: 0.140),
                    Color(white: 0.039),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 100)
                HStack(spacing: 6) {
                    Circle().fill(FoyerTheme.terracotta).frame(width: 5, height: 5)
                    Text("HOSTING")
                        .font(.system(size: 9, design: .monospaced)).tracking(2)
                }
                .foregroundStyle(FoyerTheme.terracotta)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(red: 0.039, green: 0.055, blue: 0.075, opacity: 0.7))
                .overlay(Rectangle().stroke(FoyerTheme.terracotta, lineWidth: 1))
                .padding(10)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("412 W 78th St").foyerDisplay(18).foregroundStyle(FoyerTheme.cream)
                Text("UPPER WEST SIDE · 3 / 2.5 / 1,840")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(FoyerTheme.textMuted)
                HStack(alignment: .firstTextBaseline) {
                    Text("$1,295,000")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                    Spacer()
                    Text("TODAY · 2–4 PM")
                        .font(.system(size: 9.5, design: .monospaced)).tracking(1.0)
                        .foregroundStyle(FoyerTheme.textDim)
                }
                Hairline().padding(.top, 4)
                HStack {
                    Text("6 SIGNED IN")
                        .font(.system(size: 9.5, design: .monospaced)).tracking(1.0)
                        .foregroundStyle(FoyerTheme.sage)
                    Spacer()
                    Text("Launch →")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FoyerTheme.gold, lineWidth: 1))
    }

    private var addOpenHouseButton: some View {
        VStack(spacing: 10) {
            Text("+")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 44, height: 44)
                .background(FoyerTheme.goldSoft, in: Circle())
                .overlay(Circle().stroke(FoyerTheme.gold, lineWidth: 1))
            Text("Add an open house")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
            Text("PASTE MLS # · OR SEARCH ADDRESS")
                .font(.system(size: 9.5, design: .monospaced)).tracking(1.0)
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(FoyerTheme.borderStrong)
        )
    }

    private var sessionsTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Recordings & leads")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("8 follow-ups")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(FoyerTheme.terracotta)
                        Text(" ready to send").foyerDisplay(18).foregroundStyle(FoyerTheme.cream)
                    }
                }
                Spacer()
                Text("All sessions →")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
            }
            VStack(spacing: 0) {
                ForEach(Array(sessionRows.enumerated()), id: \.element.address) { idx, s in
                    sessionRow(s)
                        .overlay(alignment: .top) { if idx > 0 { Hairline() } }
                }
            }
            .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FoyerTheme.hairline, lineWidth: 1))
        }
    }

    private struct SessionRow {
        let address, when, duration: String
        let leads, hot, ready, sent: Int
    }
    private let sessionRows: [SessionRow] = [
        .init(address: "301 E 79th St",       when: "YESTERDAY · 3:14 PM", duration: "54 min", leads: 8,  hot: 2, ready: 5, sent: 1),
        .init(address: "212 W End Ave · #6F", when: "THU · 5:02 PM",       duration: "38 min", leads: 4,  hot: 1, ready: 3, sent: 0),
        .init(address: "88 Greenwich St",     when: "WED · 1:22 PM",       duration: "1 h 12", leads: 11, hot: 4, ready: 0, sent: 11),
    ]

    private func sessionRow(_ s: SessionRow) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.address).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                Text(s.when)
                    .font(.system(size: 9.5, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .frame(maxWidth: 260, alignment: .leading)

            Text(s.duration)
                .font(.system(size: 11, design: .monospaced)).tracking(0.8)
                .foregroundStyle(FoyerTheme.textDim)
                .frame(maxWidth: 80, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(s.leads)")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                Text("LEADS")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .frame(width: 80, alignment: .leading)

            HStack(spacing: 6) {
                if s.hot > 0 { TagPill(kind: .buyer, text: "\(s.hot) HOT") }
                if s.ready > 0 { TagPill(kind: .seller, text: "\(s.ready) READY") }
                if s.sent > 0 { TagPill(kind: .browser, text: "\(s.sent) SENT") }
            }
            .frame(maxWidth: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    Rectangle().fill(FoyerTheme.sage)
                        .frame(width: progressBarWidth(s.sent, total: s.leads))
                    Rectangle().fill(FoyerTheme.gold)
                        .frame(width: progressBarWidth(s.ready, total: s.leads))
                    Rectangle().fill(FoyerTheme.terracotta)
                        .frame(width: progressBarWidth(s.hot, total: s.leads))
                    Spacer(minLength: 0)
                }
                .frame(height: 3)
                .background(FoyerTheme.hairline)
                Text("\(s.sent)/\(s.leads) FOLLOW-UPS SENT")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Open →")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FoyerTheme.gold)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func progressBarWidth(_ value: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(value) / CGFloat(total) * 220
    }
}

// ─── iPad kiosk form — guest sign-in surface
struct IPadKioskForm: View {
    @State private var first = "Sarah"
    @State private var last = "Chen"
    @State private var email = "sarah.chen@gmail.com"
    @State private var phone = "(212) 555-0101"
    @State private var intent = "buying"
    @State private var agent = "no"

    var body: some View {
        HStack(spacing: 0) {
            // LEFT — property hero
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(FoyerTheme.gold).frame(width: 5, height: 5)
                        Text("ACTIVE LISTING · MLS 4072281")
                            .font(.system(size: 10, design: .monospaced)).tracking(2)
                    }
                    .foregroundStyle(FoyerTheme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(red: 0.039, green: 0.055, blue: 0.075, opacity: 0.6), in: Capsule())
                    .overlay(Capsule().stroke(FoyerTheme.gold, lineWidth: 1))
                    Spacer()
                    Text("PHOTO 1 / 14")
                        .font(.system(size: 10, design: .monospaced)).tracking(2)
                        .foregroundStyle(FoyerTheme.creamDim)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Rectangle().fill(FoyerTheme.gold).frame(width: 22, height: 1)
                        Text("OPEN HOUSE · SATURDAY, MAY 10 · 2 — 4 PM")
                            .font(.system(size: 11, design: .monospaced)).tracking(2)
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text("412 W 78th Street").foyerDisplay(56).foregroundStyle(FoyerTheme.cream)
                    Text("Upper West Side, NY")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)

                    HStack(alignment: .firstTextBaseline) {
                        Text("$1,295,000")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("3 BED · 2.5 BA · 1,840 SQ FT")
                                .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                                .foregroundStyle(FoyerTheme.creamDim)
                            Text("HOSTED BY JOHN HALLORAN")
                                .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                                .foregroundStyle(FoyerTheme.sage)
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(0..<14, id: \.self) { d in
                            Rectangle()
                                .fill(d == 0 ? FoyerTheme.gold : FoyerTheme.cream.opacity(0.22))
                                .frame(width: 22, height: 2)
                        }
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [
                    Color(white: 0.094),
                    Color(white: 0.140),
                    Color(white: 0.039),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )

            // RIGHT — form
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Crest(size: 16)
                    Spacer()
                    Text("STEP 1 / 1")
                        .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Rectangle().fill(FoyerTheme.gold).frame(width: 22, height: 1)
                        Text("WELCOME IN")
                            .font(.system(size: 11, design: .monospaced)).tracking(2)
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("A few details, ").foyerDisplay(38).foregroundStyle(FoyerTheme.cream)
                        Text("please.")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text("Shared only with John Halloran. We verify each number and email so spam doesn't make it to your inbox either.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(FoyerTheme.textDim)
                        .padding(.top, 4)
                }
                .padding(.top, 22)

                VStack(spacing: 18) {
                    HStack(spacing: 22) {
                        underInput(label: "First name", value: $first)
                        underInput(label: "Last name", value: $last)
                    }
                    underInput(label: "Email", value: $email, verified: true, hint: "MX confirmed · Gmail · checked just now")
                    underInput(label: "Mobile phone", value: $phone, verified: true, hint: "T-Mobile · NY · mobile · live carrier check")

                    chooser(label: "What brings you in?", value: $intent, options: [
                        ("buying", "I'm looking to buy"),
                        ("curious", "Just curious"),
                        ("selling", "Sell my own place"),
                    ])
                    chooser(label: "Working with an agent?", value: $agent, options: [
                        ("yes", "Yes"),
                        ("no", "Not yet"),
                    ])
                }
                .padding(.top, 22)

                Spacer()
                HStack(alignment: .center) {
                    Text("CONSENT TO AMBIENT RECORDING\nAUTO-DELETED IN 30 DAYS · v 2.1")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                    Spacer()
                    Button {} label: {
                        HStack(spacing: 12) {
                            Text("Begin tour")
                            Text("→").font(.system(size: 20, weight: .medium))
                        }
                    }
                    .buttonStyle(FoyerPrimaryButton())
                    .fixedSize()
                }
            }
            .padding(38)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(FoyerTheme.bgDeep)
        }
    }

    private func underInput(label: String, value: Binding<String>, verified: Bool = false, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: label)
                Spacer()
                if verified {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 9))
                        Text("VERIFIED")
                            .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                    }
                    .foregroundStyle(FoyerTheme.sage)
                }
            }
            TextField("", text: value)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(verified ? FoyerTheme.sage : FoyerTheme.borderStrong)
                        .frame(height: 1)
                }
            if let hint {
                Text(hint)
                    .font(.system(size: 10, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(verified ? FoyerTheme.sage : FoyerTheme.textMuted)
            }
        }
    }

    private func chooser(label: String, value: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: label)
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { (v, l) in
                    Button { value.wrappedValue = v } label: {
                        Text(l).font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(value.wrappedValue == v ? FoyerTheme.gold : FoyerTheme.creamDim)
                            .background(value.wrappedValue == v ? FoyerTheme.goldSoft : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(value.wrappedValue == v ? FoyerTheme.gold : FoyerTheme.hairline, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// ─── iPad session leads — left rail of leads + visitor detail + drafted follow-up
struct IPadSessionLeads: View {
    @State private var activeId: Int = 1

    private var visitor: SampleVisitor {
        SampleData.visitors.first(where: { $0.id == activeId }) ?? SampleData.visitors[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            leadsList
                .frame(width: 320)
                .background(FoyerTheme.bgDeep)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(FoyerTheme.hairline).frame(width: 1)
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    visitorHeader
                    summarySection
                    draftedSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FoyerTheme.bgDeep)
        }
    }

    private var leadsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Session · 412 W 78th St")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Sat May 10 · ").foyerDisplay(22).foregroundStyle(FoyerTheme.cream)
                    Text("3 leads")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                }
                Text("18 MIN · 1,420 WORDS · 4 SPEAKERS")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .padding(.horizontal, 24).padding(.vertical, 24)
            .overlay(alignment: .bottom) { Hairline() }

            ForEach(SampleData.visitors) { v in
                leadRow(v)
                    .background(activeId == v.id ? FoyerTheme.goldSoft : Color.clear)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(activeId == v.id ? FoyerTheme.gold : Color.clear).frame(width: 2)
                    }
                    .overlay(alignment: .bottom) { Hairline() }
                    .onTapGesture { activeId = v.id }
            }
            Spacer()
            Button {} label: { Text("Send all 3 follow-ups →") }
                .buttonStyle(FoyerGhostButton())
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Hairline() }
        }
    }

    private func leadRow(_ v: SampleVisitor) -> some View {
        HStack(spacing: 12) {
            Text(v.name.split(separator: " ").map { String($0.prefix(1)) }.joined())
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 36, height: 36)
                .background(FoyerTheme.bgElev2, in: Circle())
                .overlay(Circle().stroke(FoyerTheme.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(v.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                HStack(spacing: 8) {
                    if let kind = TagPill.Kind(v.tag) { TagPill(kind: kind, text: v.tag) }
                    Text(v.signedAt.uppercased())
                        .font(.system(size: 9.5, design: .monospaced)).tracking(1.0)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
            }
            Spacer()
            Text("\(v.score)")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(v.score >= 80 ? FoyerTheme.gold : v.score >= 50 ? FoyerTheme.cream : FoyerTheme.textMuted)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var visitorHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Visitor · auto-summarized")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(visitor.name).foyerDisplay(32).foregroundStyle(FoyerTheme.cream)
                    Text(" · ")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                    Text("\(visitor.score)/100")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(visitor.score >= 80 ? FoyerTheme.gold : FoyerTheme.cream)
                }
                Text("\(visitor.email.uppercased()) · \(visitor.phone) · SIGNED \(visitor.signedAt.uppercased())")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            Spacer()
            if let kind = TagPill.Kind(visitor.tag) { TagPill(kind: kind, text: visitor.tag) }
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "What we heard")
            Text(visitor.summary)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(5)
            FlowLayout(spacing: 6) {
                ForEach(visitor.signals, id: \.self) { s in
                    Text(s)
                        .font(.system(size: 10, design: .monospaced)).tracking(1.0)
                        .foregroundStyle(FoyerTheme.gold)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(FoyerTheme.goldSoft)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(FoyerTheme.borderStrong, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 20)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var draftedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: "Drafted follow-ups · \(templateLabel) template")
                Spacer()
                HStack(spacing: 6) {
                    Text("EMAIL")
                        .font(.system(size: 9.5, design: .monospaced)).tracking(1.0)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(FoyerTheme.goldSoft)
                        .foregroundStyle(FoyerTheme.gold)
                        .overlay(Rectangle().stroke(FoyerTheme.gold, lineWidth: 1))
                    Text("SMS")
                        .font(.system(size: 9.5, design: .monospaced)).tracking(1.0)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(FoyerTheme.textDim)
                        .overlay(Rectangle().stroke(FoyerTheme.hairline, lineWidth: 1))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TO   ").font(.system(size: 10, design: .monospaced)).tracking(1.0)
                            .foregroundStyle(FoyerTheme.textMuted)
                        + Text(visitor.email).font(.system(size: 10, design: .monospaced)).tracking(1.0)
                            .foregroundStyle(FoyerTheme.cream)
                        Text("SUBJ ").font(.system(size: 10, design: .monospaced)).tracking(1.0)
                            .foregroundStyle(FoyerTheme.textMuted)
                        + Text(subjectLine).font(.system(size: 10, design: .monospaced)).tracking(1.0)
                            .foregroundStyle(FoyerTheme.cream)
                    }
                    Spacer()
                    Text("✓ MATCHES \"WARM BUYER · UWS\" TEMPLATE")
                        .font(.system(size: 9.5, design: .monospaced)).tracking(1.0)
                        .foregroundStyle(FoyerTheme.sage)
                }
                Hairline()
                Text(visitor.followUp)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .lineSpacing(5)
                    .padding(.top, 4)
            }
            .padding(22)
            .background(FoyerTheme.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(FoyerTheme.hairline, lineWidth: 1))

            HStack {
                HStack(spacing: 8) {
                    ghostMini("Regenerate")
                    ghostMini("Edit")
                    ghostMini("Change template")
                }
                Spacer()
                Button {} label: {
                    HStack(spacing: 10) {
                        Text("Send email + SMS")
                        Text("→").font(.system(size: 16, weight: .medium))
                    }
                }
                .buttonStyle(FoyerPrimaryButton())
                .fixedSize()
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
    }

    private func ghostMini(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(FoyerTheme.cream)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(FoyerTheme.borderStrong, lineWidth: 1))
    }

    private var subjectLine: String {
        switch visitor.tag {
        case "buyer":   return "412 W 78th — private showing options?"
        case "seller":  return "Comp analysis on your Riverside place"
        default:        return "412 W 78th — light updates only, no pressure"
        }
    }
    private var templateLabel: String {
        if visitor.tag == "browser" { return "low-touch" }
        return visitor.score >= 80 ? "warm-lead" : "standard"
    }
}

#Preview { IPadAgentApp() }
