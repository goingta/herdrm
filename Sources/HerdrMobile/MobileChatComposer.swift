import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MobileChatAttachment: Identifiable {
    let id = UUID()
    let name: String
    let remotePath: String
}

/// Per-target unsent attachments survive mode/root switches, never disk-persisted.
@MainActor @Observable
final class MobileChatDraft {
    var attachments: [MobileChatAttachment] = []
    var uploading = false
    var submitting = false
    var error: String?
    private var uploadGeneration = UUID()

    func invalidate() { uploadGeneration = UUID(); uploading = false; attachments.removeAll(); error = nil }

    func upload(data: Data, name: String, contentType: String,
                using operation: @escaping (Data, String, String) async throws -> String) async {
        guard !uploading else { return }
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else {
            error = AppLocalization.string("Choose a nonempty file no larger than 8 MiB."); return
        }
        let generation = uploadGeneration
        uploading = true
        error = nil
        defer { if generation == uploadGeneration { uploading = false } }
        do {
            let path = try await operation(data, name, contentType)
            guard generation == uploadGeneration else { return }
            attachments.append(MobileChatAttachment(name: name, remotePath: path))
        } catch {
            guard generation == uploadGeneration else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? AppLocalization.string("Attachment upload failed. Your draft was retained.")
        }
    }
}

struct MobileChatComposer: View {
    @Binding var text: String
    @Bindable var state: MobileChatDraft
    let modelName: String?
    let reasoningEffort: String?
    let enabled: Bool
    let upload: (Data, String, String) async throws -> String
    let send: ([String]) async -> MobilePromptResult
    @State private var choosingFile = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = state.error {
                Text(error).font(.caption).foregroundStyle(Theme.warning)
                    .accessibilityIdentifier("chat.composer.error")
            }
            if !state.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(state.attachments) { item in
                            Button {
                                state.attachments.removeAll { $0.id == item.id }
                            } label: {
                                Label(item.name, systemImage: "xmark.circle").font(.caption)
                                    .padding(.horizontal, 8).frame(minHeight: 44)
                            }
                            .disabled(state.submitting)
                            .accessibilityLabel(AppLocalization.string("Remove Attachment") + " " + item.name)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            VStack(spacing: 10) {
                Capsule().fill(MobileReferenceTheme.border).frame(width: 32, height: 3)
                TextField(AppLocalization.string("Message the agent…"), text: $text, axis: .vertical)
                    .font(.body).lineLimit(2...5).textFieldStyle(.plain)
                    .foregroundStyle(MobileReferenceTheme.text).tint(MobileReferenceTheme.accent)
                    .accessibilityIdentifier("agent.composer")
                HStack(spacing: 8) {
                    Menu {
                        Button(AppLocalization.string("Choose File"), systemImage: "doc") { choosingFile = true }
                        Button(AppLocalization.string("Choose Photo"), systemImage: "photo") { choosingPhoto = true }
                    } label: {
                        if state.uploading { ProgressView().frame(width: 44, height: 44) }
                        else { Image(systemName: "plus").font(.title3).frame(width: 44, height: 44) }
                    }
                    .disabled(!enabled || state.uploading || state.submitting)
                    .accessibilityLabel(AppLocalization.string("Add Attachment"))
                    .accessibilityIdentifier("chat.attachments")
                    Spacer(minLength: 0)
                    if let modelName, !modelName.isEmpty {
                        Text([modelName, reasoningEffort].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).lineLimit(2)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(MobileReferenceTheme.panel, in: Capsule())
                            .accessibilityIdentifier("chat.model")
                    }
                    Button { submit() } label: {
                        if state.submitting { ProgressView().tint(Color(red: 0.106, green: 0.078, blue: 0.027)) }
                        else { Image(systemName: "arrow.up").font(.system(size: 21, weight: .semibold)) }
                    }
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color(red: 0.106, green: 0.078, blue: 0.027))
                    .background(MobileReferenceTheme.primary, in: Circle())
                    .disabled(!enabled || state.uploading || state.submitting || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.attachments.isEmpty))
                    .opacity(enabled && !state.uploading ? 1 : 0.5)
                    .accessibilityLabel(AppLocalization.string("Send Prompt"))
                    .accessibilityIdentifier("chat.send")
                }
                .foregroundStyle(MobileReferenceTheme.dim)
            }
            .padding(.horizontal, 16).padding(.top, 5).padding(.bottom, 12)
            .background(MobileReferenceTheme.elevated, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(MobileReferenceTheme.border))
        }
        .padding(.horizontal, 12).padding(.top, 5).padding(.bottom, 10)
        .background(MobileReferenceTheme.panel)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { importFile(url) }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    let type = item.supportedContentTypes.first ?? .image
                    await state.upload(data: data, name: "photo." + (type.preferredFilenameExtension ?? "jpg"),
                        contentType: type.preferredMIMEType ?? "image/jpeg", using: upload)
                } catch { state.error = AppLocalization.string("Attachment upload failed. Your draft was retained.") }
                photo = nil
            }
        }
    }

    private func importFile(_ url: URL) {
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 8 * 1024 * 1024 else {
                    state.error = AppLocalization.string("Choose a nonempty file no larger than 8 MiB."); return
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                await state.upload(data: data, name: url.lastPathComponent,
                    contentType: values.contentType?.preferredMIMEType ?? "application/octet-stream", using: upload)
            } catch { state.error = AppLocalization.string("Attachment upload failed. Your draft was retained.") }
        }
    }

    private func submit() {
        guard enabled, !state.submitting, !state.uploading else { return }
        let submitted = state.attachments
        state.submitting = true
        state.error = nil
        Task {
            defer { state.submitting = false }
            let result = await send(submitted.map(\.remotePath))
            if result == .acknowledged {
                let ids = Set(submitted.map(\.id))
                state.attachments.removeAll { ids.contains($0.id) }
            } else {
                state.error = AppLocalization.string("Message not confirmed. Draft retained; check the Agent before retrying.")
            }
        }
    }
}
