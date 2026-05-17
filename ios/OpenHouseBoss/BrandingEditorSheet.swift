import SwiftUI
import PhotosUI
import UIKit

// Agent branding editor — brokerage, license, phone, title, tagline,
// headshot. Shown from the Profile screen. The values land in the
// outgoing Open House Report's email signature (and the in-app report
// header), so every field here is optional: the agent can fill in just
// brokerage and still get a better signature than the bare name default.
struct BrandingEditorSheet: View {
    var onSaved: (AgentProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared

    @State private var brokerage = ""
    @State private var licenseNumber = ""
    @State private var phone = ""
    @State private var title = ""
    @State private var tagline = ""
    // Past follow-ups the agent has written, used by the AI as voice
    // anchor. Stored as an editable array so the user can paste a few
    // examples in separate boxes (mirrors how they'd think about them).
    @State private var voiceSamples: [String] = [""]

    @State private var headshotUrl: String?
    @State private var pickedHeadshotImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var uploadingHeadshot = false
    @State private var deletingHeadshot = false

    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading profile…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    headshotSection
                    Section("Brokerage") {
                        TextField("Brokerage name", text: $brokerage)
                            .textContentType(.organizationName)
                        TextField("License # (optional)", text: $licenseNumber)
                            .autocapitalization(.allCharacters)
                    }
                    Section("Contact") {
                        TextField("Phone", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Title — e.g. Listing Specialist", text: $title)
                            .textContentType(.jobTitle)
                    }
                    Section {
                        TextField("Tagline (optional, italic line at the bottom)",
                                  text: $tagline, axis: .vertical)
                            .lineLimit(2...3)
                    } header: {
                        Text("Tagline")
                    } footer: {
                        Text("Appears as a small italic line under your name. Example: \"Helping Seattle families find home since 2015.\"")
                    }
                    voiceSamplesSection
                    if let err = error ?? loadError {
                        Section { Text(err).foregroundStyle(.red).font(.footnote) }
                    }
                }
            }
            .navigationTitle("Branding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(saving || loading)
                }
            }
        }
        .task { await load() }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await loadAndUploadHeadshot(from: item) }
        }
    }

    // MARK: – Voice samples section

    // Editable list of past follow-ups in the agent's own voice. The
    // backend uses these as the dominant voice anchor when drafting
    // new AI follow-ups — without them, drafts default to the in-prompt
    // generic-good-voice examples (better than nothing, worse than yours).
    @ViewBuilder
    private var voiceSamplesSection: some View {
        Section {
            ForEach(voiceSamples.indices, id: \.self) { idx in
                HStack(alignment: .top, spacing: 8) {
                    TextField(
                        "Paste a past follow-up — exactly how you'd write it",
                        text: Binding(
                            get: { idx < voiceSamples.count ? voiceSamples[idx] : "" },
                            set: { if idx < voiceSamples.count { voiceSamples[idx] = $0 } }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    if voiceSamples.count > 1 {
                        Button {
                            voiceSamples.remove(at: idx)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if voiceSamples.count < 5 {
                Button {
                    voiceSamples.append("")
                } label: {
                    Label("Add another", systemImage: "plus.circle")
                        .font(.system(size: 14))
                }
            }
        } header: {
            Text("Your voice")
        } footer: {
            Text("Paste 2–3 follow-up messages you've actually sent — texts or emails, whatever you really write. The AI matches your phrasing, capitalization, and length when drafting new ones. The more honest, the better. Skip the polish.")
        }
    }

    // MARK: – Headshot section

    @ViewBuilder
    private var headshotSection: some View {
        Section {
            HStack(spacing: 16) {
                headshotPreview
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(
                        selection: $photoPickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 6) {
                            if uploadingHeadshot {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 12))
                            }
                            Text(uploadingHeadshot ? "Uploading…"
                                : (headshotUrl == nil ? "Add headshot" : "Replace"))
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .disabled(uploadingHeadshot || deletingHeadshot)

                    if headshotUrl != nil {
                        Button(role: .destructive) {
                            Task { await removeHeadshot() }
                        } label: {
                            HStack(spacing: 6) {
                                if deletingHeadshot {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                }
                                Text(deletingHeadshot ? "Removing…" : "Remove")
                                    .font(.system(size: 13))
                            }
                        }
                        .disabled(uploadingHeadshot || deletingHeadshot)
                    }
                }
            }
        } header: {
            Text("Headshot")
        } footer: {
            Text("Appears next to your name in the report's email signature. Square photo works best.")
        }
    }

    @ViewBuilder
    private var headshotPreview: some View {
        if let img = pickedHeadshotImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if let rel = headshotUrl {
            AuthedAsyncImage(relativePath: rel)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.gray)
                )
        }
    }

    // MARK: – Actions

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let p = try await APIClient.shared.getProfile()
            brokerage = p.brokerage
            licenseNumber = p.licenseNumber
            phone = p.phone
            title = p.title
            tagline = p.tagline
            // Always show at least one editable row so the section never
            // collapses to just the "Add another" button on a fresh profile.
            voiceSamples = p.voiceSamples.isEmpty ? [""] : p.voiceSamples
            headshotUrl = p.headshotUrl
        } catch {
            loadError = "Couldn't load profile: \(error.localizedDescription)"
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        let cleanedSamples = voiceSamples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            let updated = try await APIClient.shared.updateProfile(
                brokerage: brokerage.trimmingCharacters(in: .whitespaces),
                licenseNumber: licenseNumber.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces),
                title: title.trimmingCharacters(in: .whitespaces),
                tagline: tagline.trimmingCharacters(in: .whitespacesAndNewlines),
                voiceSamples: cleanedSamples
            )
            // Refresh AuthStore so other screens that render the agent's
            // profile pick up the new fields without a manual reload.
            await auth.refreshMe()
            onSaved(updated)
            dismiss()
        } catch let err {
            error = err.localizedDescription
        }
    }

    private func loadAndUploadHeadshot(from item: PhotosPickerItem) async {
        uploadingHeadshot = true
        error = nil
        defer { uploadingHeadshot = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                error = "Couldn't read the selected photo."
                return
            }
            // Downsize + recompress so a 4MB iPhone photo doesn't blow
            // through the 8MB backend limit, and so the headshot loads
            // fast in homeowner inboxes. 512px is plenty for a 64x64
            // signature image (≈2x retina) and most email previews.
            let resized = uiImage.resized(maxDimension: 512)
            guard let jpeg = resized.jpegData(compressionQuality: 0.85) else {
                error = "Couldn't compress the selected photo."
                return
            }
            let updated = try await APIClient.shared.uploadHeadshot(data: jpeg)
            pickedHeadshotImage = resized
            headshotUrl = updated.headshotUrl
            // Keep AuthStore in sync so the avatar in IPadProfile updates.
            await auth.refreshMe()
        } catch let err {
            error = "Upload failed: \(err.localizedDescription)"
        }
    }

    private func removeHeadshot() async {
        deletingHeadshot = true
        error = nil
        defer { deletingHeadshot = false }
        do {
            _ = try await APIClient.shared.deleteHeadshot()
            pickedHeadshotImage = nil
            headshotUrl = nil
            await auth.refreshMe()
        } catch let err {
            error = "Couldn't remove headshot: \(err.localizedDescription)"
        }
    }
}

// MARK: – Authenticated AsyncImage

// AsyncImage hits the URL with a bare URLRequest; the backend's headshot
// endpoint requires a Bearer JWT, so we have to drive the load by hand.
// Loads relative paths against Config.backendURL so the AgentProfile's
// "/me/profile/headshot?v=…" works as-is.
struct AuthedAsyncImage: View {
    let relativePath: String

    @State private var image: UIImage?
    @State private var loading = true

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loading {
                ProgressView().scaleEffect(0.6)
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.gray.opacity(0.5))
            }
        }
        .task(id: relativePath) { await load() }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        let req = await APIClient.shared.headshotRequest(relativePath: relativePath)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            image = UIImage(data: data)
        } catch {
            image = nil
        }
    }
}

// MARK: – UIImage downsize helper

extension UIImage {
    // Returns a copy whose longest side is at most `maxDimension`, scaling
    // proportionally. UIGraphicsImageRenderer handles the device scale
    // automatically — pass 512 to get a 512px-on-the-long-side image
    // regardless of retina factor.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
