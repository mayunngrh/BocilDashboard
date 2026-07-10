import SwiftUI

/// Modal editor for a single persona's markdown. Handles both create (empty
/// name field, editable) and edit (name locked, content loaded from server).
/// Presented as an overlay from SettingsView's Characters card.
struct PersonaEditorView: View {
    @ObservedObject var service: PersonaBackendService

    /// nil → creating a new character; non-nil → editing an existing one.
    let editingName: String?

    let onClose: () -> Void

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var localError: String?
    @State private var savedLive = false
    @State private var showDeleteConfirm = false

    private var isCreating: Bool { editingName == nil }

    private var nameValid: Bool { PersonaBackendService.isValidName(name) }
    private var contentValid: Bool { PersonaBackendService.isValidContent(content) }
    private var canSave: Bool { nameValid && contentValid && !isSaving }

    private let newTemplate = """
    # Identity & backstory


    # Voice & tone


    # Speech rules


    # Catchphrase


    # Personality & opinions


    # Emotion tool bias


    # Move tool bias


    # Staying in character

    """

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 16) {
                header

                Rectangle().fill(Bocil.hairline).frame(height: 1)

                if isCreating {
                    nameField
                }

                contentEditor

                if let localError {
                    Text(localError)
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if savedLive {
                    HStack(spacing: 6) {
                        Rectangle().fill(Bocil.accentSoft).frame(width: 7, height: 7)
                        Text("settings.characters.savedLive")
                            .font(Bocil.mono(11))
                            .foregroundColor(Bocil.subtext)
                    }
                }

                footer
            }
            .padding(24)
            .frame(width: 520)
            .background(Bocil.surface)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
        }
        .task {
            if let editingName {
                name = editingName
                await loadContent(editingName)
            } else {
                content = newTemplate
            }
        }
    }

    private var header: some View {
        HStack {
            Text(isCreating ? "settings.characters.newTitle" : "settings.characters.editTitle")
                .font(Bocil.header(18))
                .foregroundColor(Bocil.ink)
            if isLoading || isSaving {
                ProgressView().scaleEffect(0.6).padding(.leading, 6)
            }
            Spacer()
            if let editingName, service.active == editingName {
                Text("settings.characters.activeBadge")
                    .font(Bocil.mono(10))
                    .foregroundColor(Bocil.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Bocil.accentSoft)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings.characters.nameLabel")
                .font(Bocil.mono(11))
                .foregroundColor(Bocil.subtext)
            TextField("settings.characters.namePlaceholder", text: $name)
                .textFieldStyle(.plain)
                .font(Bocil.mono(13))
                .foregroundColor(Bocil.ink)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .overlay(Rectangle().stroke(
                    name.isEmpty || nameValid ? Bocil.cardBorder : Bocil.danger,
                    lineWidth: 1.5))
            Text("settings.characters.nameHint")
                .font(Bocil.mono(10))
                .foregroundColor(Bocil.faint)
        }
    }

    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings.characters.contentLabel")
                .font(Bocil.mono(11))
                .foregroundColor(Bocil.subtext)
            TextEditor(text: $content)
                .font(Bocil.mono(12))
                .foregroundColor(Bocil.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 280)
                .background(Bocil.bg)
                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !isCreating {
                Button(action: { showDeleteConfirm = true }) {
                    Text("common.delete")
                        .font(Bocil.mono(13))
                        .foregroundColor(Bocil.danger)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .overlay(Rectangle().stroke(Bocil.danger, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    Text("settings.characters.deleteConfirm"),
                    isPresented: $showDeleteConfirm
                ) {
                    Button(role: .destructive) {
                        if let editingName {
                            Task { await service.delete(editingName); onClose() }
                        }
                    } label: { Text("common.delete") }
                    Button(role: .cancel) {} label: { Text("common.cancel") }
                }
            }

            Spacer()

            Button("common.cancel") { onClose() }
                .font(Bocil.mono(13)).foregroundColor(Bocil.subtext)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                .buttonStyle(.plain)

            Button("common.save") { Task { await save() } }
                .font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(canSave ? Bocil.accentSoft : Bocil.hairline)
                .buttonStyle(.plain)
                .disabled(!canSave)
        }
    }

    private func loadContent(_ name: String) async {
        isLoading = true
        localError = nil
        do {
            let detail = try await service.fetchDetail(name)
            content = detail.content
        } catch {
            localError = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        localError = nil
        savedLive = false
        guard nameValid else {
            localError = String(localized: "settings.characters.nameError")
            return
        }
        guard contentValid else {
            localError = String(localized: "settings.characters.contentError")
            return
        }
        isSaving = true
        do {
            let saved = try await service.save(name: name, content: content)
            if saved.active {
                savedLive = true
                // Leave the toast up briefly, then close.
                try? await Task.sleep(for: .seconds(1.5))
            }
            onClose()
        } catch {
            localError = error.localizedDescription
        }
        isSaving = false
    }
}
