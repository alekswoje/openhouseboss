import SwiftUI

// Pre-session setup — type the property address, then start recording.
// The address is stashed in SessionStore so the upload call carries it.
struct SetupView: View {
    @State private var address: String = ""
    @State private var goLive = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    backRow
                    header
                    addressField
                    helper
                    Spacer().frame(height: 160)
                }
            }

            beginButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $goLive) { LiveView() }
        .onAppear { focused = true }
    }

    private var backRow: some View {
        HStack {
            Button { dismiss() } label: {
                Text("← Sessions")
                    .font(.system(size: 11, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(FoyerTheme.gold)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "New session")
            Text("Where are you hosting?")
                .foyerDisplay(30)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Address")
            TextField("", text: $address,
                      prompt: Text("412 W 78th St · Apt 4-A").foregroundStyle(FoyerTheme.textMuted))
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(FoyerTheme.borderStrong).frame(height: 1)
                }
            Text("Optional — used to label this session in your history.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textDim)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private var helper: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "How it works")
            VStack(alignment: .leading, spacing: 8) {
                helperRow("01", "Begin recording — keep your phone in pocket.")
                helperRow("02", "Talk naturally with each guest who walks in.")
                helperRow("03", "End session — we transcribe, identify each speaker, and draft a personalized follow-up.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
    }

    private func helperRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num)
                .font(.system(size: 11, design: .monospaced)).tracking(1.4)
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.cream)
                .lineSpacing(2)
        }
    }

    private var beginButton: some View {
        Button {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            SessionStore.shared.pendingAddress = trimmed.isEmpty ? nil : trimmed
            goLive = true
        } label: {
            HStack(spacing: 10) {
                Circle().fill(Color.black).frame(width: 10, height: 10)
                Text("Begin recording")
            }
        }
        .buttonStyle(FoyerPrimaryButton())
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }
}

// Flow layout — wraps children left-to-right onto multiple lines. Used for
// signal-chip rows where the count varies.
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
