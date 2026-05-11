import SwiftUI

// Pre-session setup — confirm listing, attach offer, choose source, begin recording.
// Mirrors ScreenSetup in the design.
struct SetupView: View {
    @State private var goLive = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    propertyCard
                    offerCard
                    sourcesSection
                    Spacer().frame(height: 160)
                }
            }

            beginButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $goLive) { LiveView() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "New session · auto-pulled from MLS")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Today's ").foyerDisplay(34).foregroundStyle(FoyerTheme.cream)
                Text("open house")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var propertyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: "Property")
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(FoyerTheme.sage).frame(width: 5, height: 5)
                    Text("MLS · 4072281")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(FoyerTheme.sage)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("412 W 78th St").foyerDisplay(22).foregroundStyle(FoyerTheme.cream)
            }
            Text("Apartment 4-A")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(FoyerTheme.gold)

            FlowLayout(spacing: 6) {
                ForEach(["3 BR", "2.5 BA", "1,840 sf", "$1.295M", "Reno 2024", "Doorman"], id: \.self) {
                    chip($0)
                }
            }
            .padding(.top, 4)

            Hairline().padding(.top, 8)
            HStack {
                Text("SAT MAY 10 · 2 — 4 PM")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(FoyerTheme.textMuted)
                Spacer()
                Text("Change →")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var offerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Active offer · attached to session")
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("$2,500 ").foyerDisplay(16).foregroundStyle(FoyerTheme.cream)
                        Text("buyer rebate")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text("AUTO-INCLUDED IN EVERY FOLLOW-UP")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                Spacer()
                Text("EDIT →")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(FoyerTheme.gold)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(FoyerTheme.goldSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.borderStrong, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Sources")
            sourceRow(letter: "C", title: "Compass iPad sign-in", sub: "CONNECTED", live: true)
            sourceRow(letter: nil, title: "iPhone microphone", sub: "ON-DEVICE · ENCRYPTED", live: false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func sourceRow(letter: String?, title: String, sub: String, live: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let letter {
                    Text(letter)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                        .frame(width: 28, height: 28)
                        .background(FoyerTheme.goldSoft, in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 14))
                        .foregroundStyle(FoyerTheme.creamDim)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(FoyerTheme.cream)
                Text(sub).font(.system(size: 9, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            Spacer()
            if live { Circle().fill(FoyerTheme.sage).frame(width: 6, height: 6) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.hairline, lineWidth: 0.5))
    }

    private var beginButton: some View {
        VStack(spacing: 10) {
            Button { goLive = true } label: {
                HStack(spacing: 10) {
                    Circle().fill(Color.black)
                        .frame(width: 10, height: 10)
                    Text("Begin recording")
                }
            }
            .buttonStyle(FoyerPrimaryButton())

            Text("SAT MAY 10 · 2:00 PM")
                .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private func chip(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 10, design: .monospaced)).tracking(0.8)
            .foregroundStyle(FoyerTheme.creamDim)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.borderStrong, lineWidth: 0.5))
    }
}

// Flow layout — wraps children left-to-right onto multiple lines. Used for
// stat / tag chip rows where the count varies.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = arrange(subviews: subviews, width: width)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placements = arrange(subviews: subviews, width: bounds.width).placements
        for (i, p) in placements.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (height: CGFloat, placements: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var placements: [CGPoint] = []
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            placements.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (y + rowHeight, placements)
    }
}

#Preview { NavigationStack { SetupView() } }
