import AppKit
import NotchNestCore
import SwiftUI
import UniformTypeIdentifiers

struct ClipsTabView: View {
    @Bindable var model: NotchNestModel
    @State private var isDropTargeted = false
    @State private var targetedAction: DropActionKind?

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clips & Drop Tray")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

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
            }

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
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
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

            HStack(spacing: 5) {
                Button {
                    copyClipToClipboard(item)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard")

                Button {
                    Task { await model.performDropAction(.airDrop, on: [item.url]) }
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("AirDrop")

                Button {
                    Task { await model.performDropAction(.zip, on: [item.url]) }
                } label: {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("Create Zip")

                if item.isImage {
                    let isPNG = item.url.pathExtension.lowercased() == "png"
                    Button {
                        Task {
                            await model.performDropAction(isPNG ? .convertJPG : .convertPNG, on: [item.url])
                        }
                    } label: {
                        Text(isPNG ? "JPG" : "PNG")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.skyWave)
                    }
                    .buttonStyle(.plain)
                    .help(isPNG ? "Convert to JPG" : "Convert to PNG")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

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
