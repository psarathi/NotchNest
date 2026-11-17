import AppKit
import NotchNestCore
import SwiftUI

struct NotesTabView: View {
    @Bindable var model: NotchNestModel
    let onRequestFocus: () -> Void

    @FocusState private var editorFocused: Bool
    @State private var convertedBanner: String?

    var body: some View {
        HStack(spacing: 10) {
            notesSidebar
                .frame(width: 180)

            noteEditorArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var notesSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily Notepad")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Button {
                    model.addNote()
                    onRequestFocus()
                    editorFocused = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NotchTheme.lavenderSoft)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("New note")
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(model.notes) { note in
                        let selected = note.id == model.selectedNoteID
                        Button {
                            model.selectedNoteID = note.id
                        } label: {
                            HStack {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .black : .white.opacity(0.82))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? NotchTheme.sagePaper : Color.white.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var noteEditorArea: some View {
        if let index = model.selectedNoteIndex {
            let note = model.notes[index]
            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    Text(note.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    Spacer()

                    if let convertedBanner {
                        Text(convertedBanner)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(NotchTheme.sagePaper)
                    } else {
                        Text("\(note.body.count) chars")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Button {
                        let count = model.convertNoteLinesToTasks(note.id)
                        if count > 0 {
                            convertedBanner = "Added \(count) to Today"
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                convertedBanner = nil
                            }
                        }
                    } label: {
                        Label("To Tasks", systemImage: "checklist")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(NotchTheme.sagePaper, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Create Today tasks from lines in this note")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.body, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .help("Copy note")

                    if model.notes.count > 1 {
                        Button {
                            model.deleteNote(note.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help("Delete note")
                    }
                }

                TextEditor(
                    text: Binding(
                        get: { model.notes.indices.contains(index) ? model.notes[index].body : "" },
                        set: { newValue in
                            model.updateNoteBody(note.id, body: newValue)
                        }
                    )
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .focused($editorFocused)
                .onTapGesture {
                    onRequestFocus()
                    editorFocused = true
                }
            }
            .padding(11)
            .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
    }
}
