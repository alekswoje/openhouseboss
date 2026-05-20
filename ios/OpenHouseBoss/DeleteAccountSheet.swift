import SwiftUI

// Typed-confirmation sheet for permanent account deletion. App Store
// Guideline 5.1.1(v) requires an in-app delete flow — this is it. The
// "type DELETE to confirm" gate is the standard pattern for irreversible
// destructive actions (matches GitHub, Stripe, etc.) and is what the
// backend's DELETE /me docstring assumes is in front of every call.
//
// Used by both HomeView (iPhone profile) and IPadProfile (iPad settings).
struct DeleteAccountSheet: View {
    let onCancel: () -> Void
    let onConfirmed: () -> Void

    @State private var confirmText: String = ""
    @State private var inFlight: Bool = false
    @State private var errorMessage: String?

    private var canDelete: Bool {
        confirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
            && !inFlight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(FoyerTheme.terracotta)
                        Text("Delete your account")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(FoyerTheme.cream)
                        Text("This is permanent. We can't restore it.")
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.textMuted)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("What we'll erase")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(FoyerTheme.gold)
                        bullet("Every recorded open-house session and its audio")
                        bullet("All transcripts, leads, and follow-up drafts")
                        bullet("Your headshot, brokerage profile, and templates")
                        bullet("Your Gmail and Follow Up Boss connections")
                        bullet("Your account record — you'll be signed out everywhere")
                    }
                    .padding(16)
                    .background(FoyerTheme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type DELETE to confirm")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                        TextField("DELETE", text: $confirmText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .padding(12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(FoyerTheme.terracotta.opacity(0.4), lineWidth: 1)
                            )
                            .foregroundStyle(FoyerTheme.cream)
                            .disabled(inFlight)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(FoyerTheme.terracotta)
                            .padding(.top, 4)
                    }

                    Button {
                        Task {
                            inFlight = true
                            errorMessage = nil
                            do {
                                try await AuthStore.shared.deleteAccount()
                                onConfirmed()
                            } catch {
                                errorMessage = "Couldn't delete your account: \(error.localizedDescription)"
                                inFlight = false
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if inFlight {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "trash.fill")
                            }
                            Text(inFlight ? "Deleting…" : "Delete my account")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            (canDelete ? FoyerTheme.terracotta : FoyerTheme.terracotta.opacity(0.35)),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDelete)

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .background(FoyerTheme.bgDeep.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(FoyerTheme.gold)
                        .disabled(inFlight)
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(FoyerTheme.terracotta)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.cream.opacity(0.9))
            Spacer(minLength: 0)
        }
    }
}
