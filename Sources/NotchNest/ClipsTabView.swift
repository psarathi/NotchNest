import AppKit
import NotchNestCore
import SwiftUI
import UniformTypeIdentifiers

private enum ClipsSection: String, CaseIterable {
    case files = "Files & Drops"
    case clipboard = "Clipboard"
}

struct ClipsTabView: View {
    @Bindable var model: NotchNestModel
    @State private var selectedSection: ClipsSection = .files
    @State private var isDropTargeted = false
    @State private var targetedAction: DropActionKind?
    @State private var clipboardSearch: String = ""
    @State private var copiedEntryID: UUID?
    @State private var qrEntry: ClipboardEntry?

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 8)
    ]

    private var filteredClipboardEntries: [ClipboardEntry] {
        let query = clipboardSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.clipboardService.entries }
        return model.clipboardService.entries.filter { $0.text.lowercased().contains(query) }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(ClipsSection.allCases, id: \.self) { section in
                            let isSelected = selectedSection == section
                            let title = section == .clipboard
                                ? "Clipboard (\(model.clipboardService.entries.count))"
                                : section.rawValue
                            Button {
                                selectedSection = section
                            } label: {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isSelected ? .black : .white.opacity(0.75))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4.5)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? NotchTheme.sagePaper : Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    if selectedSection == .files {
                        Button {
                            model.refreshClips()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else if model.clipboardService.entries.contains(where: { !$0.isPinned }) {
                        Button {
                            model.clipboardService.clearUnpinned()
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Clear unpinned clipboard history")
                    }
                }

                if selectedSection == .files {
                    dropZoneHeader

                    dropActionsBar

                    if let feedback = model.dropActionFeedback {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(NotchTheme.sagePaper)
                            Text(feedback)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                            Spacer()
                            Button("Clear") {
                                model.dismissDropActionBanner()
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(NotchTheme.sageBadgeFill.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if model.clips.isEmpty {
                        VStack(spacing: 6) {
                            Spacer()
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("Recent screenshots & dropped files appear here for quick drag-and-drop.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(model.clips) { item in
                                    clipCard(item)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    clipboardHistorySection
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            if let qrTarget = qrEntry {
                qrPreviewOverlay(for: qrTarget)
            }
        }
    }

    @ViewBuilder
    private var clipboardHistorySection: some View {
        if !model.settings.clipboardHistoryEnabled {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.amberGlow)
                Text("Clipboard tracking is paused in Settings.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button("Enable") {
                    model.settings.clipboardHistoryEnabled = true
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.amberGlow, in: Capsule())
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        }

        if !model.clipboardService.entries.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                TextField("Filter copied text & links…", text: $clipboardSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
                if !clipboardSearch.isEmpty {
                    Button {
                        clipboardSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5.5)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }

        if filteredClipboardEntries.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.4))
                Text(clipboardSearch.isEmpty
                    ? "Copied text & links appear here automatically. Passwords and 1Password entries are excluded."
                    : "No copied items matching \"\(clipboardSearch)\".")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(filteredClipboardEntries) { entry in
                        clipboardRow(entry)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func clipboardRow(_ entry: ClipboardEntry) -> some View {
        let url = entry.detectedURL
        let wasCopied = copiedEntryID == entry.id
        return HStack(spacing: 8) {
            Image(systemName: url != nil ? "link" : "doc.plaintext")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(url != nil ? NotchTheme.skyWave : NotchTheme.sagePaper)
                .frame(width: 24, height: 24)
                .background((url != nil ? NotchTheme.skyWave : NotchTheme.sagePaper).opacity(0.14), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(entry.addedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.45))

                    if let host = url?.host {
                        Text(host)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(NotchTheme.skyWave.opacity(0.85))
                            .lineLimit(1)
                    }

                    if entry.isPinned {
                        Text("PINNED")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.amberGlow)
                    }
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Button {
                    model.clipboardService.copyToPasteboard(entry)
                    copiedEntryID = entry.id
                    let targetID = entry.id
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1400))
                        if copiedEntryID == targetID {
                            copiedEntryID = nil
                        }
                    }
                } label: {
                    Image(systemName: wasCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(wasCopied ? NotchTheme.sagePaper : .white.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard")

                if let url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10.5))
                            .foregroundStyle(NotchTheme.skyWave)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Open Link")
                }

                Button {
                    qrEntry = entry
                } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Show QR Code")

                Button {
                    model.sendToTranslator(entry.text)
                } label: {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Send to Quick Translator")

                Button {
                    model.clipboardService.togglePin(entry.id)
                } label: {
                    Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(entry.isPinned ? Color.amberGlow : .white.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(entry.isPinned ? "Unpin" : "Pin")

                Button {
                    model.clipboardService.remove(entry.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 18, height: 22)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private func qrPreviewOverlay(for entry: ClipboardEntry) -> some View {
        ZStack {
            Color.black.opacity(0.65)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture {
                    qrEntry = nil
                }

            VStack(spacing: 10) {
                HStack {
                    Label("Instant QR Code", systemImage: "qrcode")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        qrEntry = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }

                if let qrImage = ClipboardHistoryService.qrCodeImage(for: entry.text, size: 150) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 138, height: 138)
                        .padding(8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text("Unable to encode text as QR.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text(entry.text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Button("Copy Text") {
                        model.clipboardService.copyToPasteboard(entry)
                        qrEntry = nil
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(NotchTheme.sagePaper, in: Capsule())
                    .buttonStyle(.plain)

                    Button("Close") {
                        qrEntry = nil
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: 270)
            .background(NotchTheme.obsidianBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 16, y: 6)
        }
    }

    private var dropZoneHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 11.5))
                .foregroundStyle(isDropTargeted ? Color.amberGlow : .white.opacity(0.55))
            Text(isDropTargeted
                ? "Release to stage in Clips, or drop onto an action tile below"
                : "Drop files onto an action tile (AirDrop, Zip, PNG, JPG, Trash) or into Shelf.")
                .font(.system(size: 10.5))
                .foregroundStyle(isDropTargeted ? Color.amberGlow : .white.opacity(0.65))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    (isDropTargeted || model.isDraggingFileOverNotch) ? Color.amberGlow : Color.white.opacity(0.14),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
    }

    private var dropActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DropActionKind.allCases) { action in
                    let isTileTargeted = targetedAction == action
                    let hasPending = !model.pendingActionURLs.isEmpty
                    Button {
                        let urls = model.pendingActionURLs
                        guard !urls.isEmpty else { return }
                        Task {
                            await model.performDropAction(action, on: urls)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                            Text(action.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(isTileTargeted ? .black : (hasPending ? .white : .white.opacity(0.68)))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            isTileTargeted
                                ? Color.amberGlow
                                : (hasPending ? Color.white.opacity(0.12) : Color.white.opacity(0.05)),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isTileTargeted ? Color.amberGlow : Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onDrop(
                        of: [.fileURL],
                        isTargeted: Binding(
                            get: { targetedAction == action },
                            set: { targeted in
                                targetedAction = targeted ? action : (targetedAction == action ? nil : targetedAction)
                            }
                        )
                    ) { providers in
                        handleActionTileDrop(action: action, providers: providers)
                    }
                }
            }
        }
    }

    private func clipCard(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ClipThumbnailView(item: item)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Button {
                    model.toggleClipPin(item)
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                        .foregroundStyle(item.isPinned ? .black : .white)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(item.isPinned ? Color.amberGlow : Color.black.opacity(0.55))
                        )
                }
                .buttonStyle(.plain)
                .padding(4)
            }

            Text(item.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                Button {
                    copyClipToClipboard(item)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard")

                if item.isImage {
                    Button {
                        Task { await model.performDropAction(.copyText, on: [item.url]) }
                    } label: {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTheme.sagePaper)
                    }
                    .buttonStyle(.plain)
                    .help("Extract Text (OCR)")
                }

                Button {
                    Task { await model.performDropAction(.airDrop, on: [item.url]) }
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .buttonStyle(.plain)
                .help("AirDrop")

                Menu {
                    if item.isImage {
                        let isPNG = item.url.pathExtension.lowercased() == "png"
                        Button("Copy Text (OCR)") {
                            Task { await model.performDropAction(.copyText, on: [item.url]) }
                        }
                        Button("Compress Image") {
                            Task { await model.performDropAction(.compressImage, on: [item.url]) }
                        }
                        Button(isPNG ? "Convert to JPG" : "Convert to PNG") {
                            Task { await model.performDropAction(isPNG ? .convertJPG : .convertPNG, on: [item.url]) }
                        }
                        Divider()
                    }
                    Button("Create Zip") {
                        Task { await model.performDropAction(.zip, on: [item.url]) }
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    Divider()
                    Button("Move to Trash", role: .destructive) {
                        Task { await model.performDropAction(.trash, on: [item.url]) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More Actions")

                Spacer()

                Button {
                    model.removeClip(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Dismiss from Clips")
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func copyClipToClipboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.isImage, let image = NSImage(contentsOf: item.url) {
            pb.writeObjects([image, item.url as NSURL])
        } else {
            pb.writeObjects([item.url as NSURL])
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            Self.loadFileURL(from: provider) { resolvedURL in
                Task { @MainActor in
                    model.handleDroppedFilesForActions([resolvedURL])
                }
            }
        }
        return accepted
    }

    private func handleActionTileDrop(action: DropActionKind, providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            Self.loadFileURL(from: provider) { resolvedURL in
                Task { @MainActor in
                    await model.performDropAction(action, on: [resolvedURL])
                }
            }
        }
        return accepted
    }

    nonisolated private static func loadFileURL(
        from provider: NSItemProvider,
        onResolved: @escaping @Sendable (URL) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { rawItem, _ in
            let resolvedURL: URL?
            if let data = rawItem as? Data {
                resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = rawItem as? URL {
                resolvedURL = url
            } else {
                resolvedURL = nil
            }
            if let resolvedURL {
                onResolved(resolvedURL)
            }
        }
    }
}

private struct ClipThumbnailView: View {
    let item: ClipItem

    var body: some View {
        if item.isImage, let nsImage = NSImage(contentsOf: item.url) {
            Color.white.opacity(0.04)
                .overlay {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            ZStack {
                Color.white.opacity(0.06)
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
            }
        }
    }
}
