import AppKit
import Foundation
import Vision

public enum DropActionExecutor {
    @MainActor
    public static func execute(
        _ action: DropActionKind,
        urls: [URL],
        onAddToShelf: ([URL]) -> Void
    ) async -> String {
        guard !urls.isEmpty else { return "No files provided." }

        switch action {
        case .shelf:
            onAddToShelf(urls)
            return urls.count == 1
                ? "Added \(urls[0].lastPathComponent) to Clips"
                : "Added \(urls.count) items to Clips"

        case .copyText:
            do {
                let extracted = try await Task.detached(priority: .userInitiated) {
                    try recognizeText(from: urls)
                }.value
                guard !extracted.isEmpty else {
                    return "No readable text found in image."
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(extracted, forType: .string)
                let lineCount = extracted.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
                return "Copied \(lineCount) line(s) of text to clipboard"
            } catch {
                return "OCR failed: \(error.localizedDescription)"
            }

        case .compressImage:
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try compressImages(urls)
                }.value
                onAddToShelf(summary.outputs)
                let before = ByteCountFormatter.string(fromByteCount: summary.originalBytes, countStyle: .file)
                let after = ByteCountFormatter.string(fromByteCount: summary.compressedBytes, countStyle: .file)
                return "Compressed \(summary.outputs.count) image(s): \(before) → \(after)"
            } catch {
                return "Compression failed: \(error.localizedDescription)"
            }

        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop) else {
                return "AirDrop is unavailable on this Mac."
            }
            if service.canPerform(withItems: urls) {
                service.perform(withItems: urls)
                return "Opened AirDrop sheet"
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return "Revealed files in Finder for AirDrop"

        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return "Revealed in Finder"

        case .zip:
            do {
                let archiveURL = try await Task.detached(priority: .userInitiated) {
                    try createZipArchive(from: urls)
                }.value
                onAddToShelf([archiveURL])
                return "Created \(archiveURL.lastPathComponent)"
            } catch {
                return "Zip failed: \(error.localizedDescription)"
            }

        case .convertPNG:
            do {
                let outputs = try await Task.detached(priority: .userInitiated) {
                    try convertImages(urls, to: .png, fileExtension: "png")
                }.value
                onAddToShelf(outputs)
                return "Converted \(outputs.count) image(s) to PNG"
            } catch {
                return "PNG conversion failed: \(error.localizedDescription)"
            }

        case .convertJPG:
            do {
                let outputs = try await Task.detached(priority: .userInitiated) {
                    try convertImages(urls, to: .jpeg, fileExtension: "jpg")
                }.value
                onAddToShelf(outputs)
                return "Converted \(outputs.count) image(s) to JPG"
            } catch {
                return "JPG conversion failed: \(error.localizedDescription)"
            }

        case .trash:
            var trashed = 0
            for url in urls {
                if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                    trashed += 1
                }
            }
            return trashed > 0 ? "Moved \(trashed) item(s) to Trash" : "Could not move item(s) to Trash"

        case .eject:
            return ejectMatchingVolumes(for: urls)
        }
    }

    public nonisolated static func createZipArchive(from urls: [URL]) throws -> URL {
        guard let first = urls.first else {
            throw NSError(domain: "NotchNestDrop", code: 1, userInfo: [NSLocalizedDescriptionKey: "No files to archive."])
        }

        let fm = FileManager.default
        let baseName = urls.count == 1
            ? first.deletingPathExtension().lastPathComponent
            : "NotchNest-Archive"
        let preferredDir = first.deletingLastPathComponent()
        let destDir = fm.isWritableFile(atPath: preferredDir.path)
            ? preferredDir
            : fm.temporaryDirectory
        let destination = uniqueURL(in: destDir, baseName: baseName, ext: "zip")

        if urls.count == 1 {
            try runDitto(source: first, destination: destination)
            return destination
        }

        let staging = fm.temporaryDirectory.appendingPathComponent("NotchNestZip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for url in urls {
            let stagedTarget = staging.appendingPathComponent(url.lastPathComponent)
            try fm.copyItem(at: url, to: stagedTarget)
        }
        try runDitto(source: staging, destination: destination, keepParent: false)
        return destination
    }

    public nonisolated static func convertImages(
        _ urls: [URL],
        to type: NSBitmapImageRep.FileType,
        fileExtension: String
    ) throws -> [URL] {
        var outputs: [URL] = []
        let fm = FileManager.default

        for url in urls {
            guard let image = NSImage(contentsOf: url),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else {
                continue
            }
            let props: [NSBitmapImageRep.PropertyKey: Any] = type == .jpeg
                ? [.compressionFactor: 0.90]
                : [:]
            guard let encoded = rep.representation(using: type, properties: props) else { continue }

            let dir = fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
                ? url.deletingLastPathComponent()
                : fm.temporaryDirectory
            let base = url.deletingPathExtension().lastPathComponent
            let outURL = uniqueURL(in: dir, baseName: base, ext: fileExtension)
            try encoded.write(to: outURL, options: [.atomic])
            outputs.append(outURL)
        }

        guard !outputs.isEmpty else {
            throw NSError(
                domain: "NotchNestDrop",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Drop PNG, JPG, HEIC, WEBP, or TIFF images to convert."]
            )
        }
        return outputs
    }

    public nonisolated static func recognizeText(from urls: [URL]) throws -> String {
        var blocks: [String] = []
        for url in urls {
            guard let nsImage = NSImage(contentsOf: url),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            if !lines.isEmpty {
                blocks.append(lines.joined(separator: "\n"))
            }
        }
        guard !blocks.isEmpty else {
            throw NSError(
                domain: "NotchNestDrop",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No readable text found in image(s)."]
            )
        }
        return blocks.joined(separator: "\n\n")
    }

    public nonisolated static func compressImages(
        _ urls: [URL],
        maxDimension: CGFloat = 1920,
        jpegQuality: Double = 0.76
    ) throws -> (outputs: [URL], originalBytes: Int64, compressedBytes: Int64) {
        var outputs: [URL] = []
        var totalBefore: Int64 = 0
        var totalAfter: Int64 = 0
        let fm = FileManager.default

        for url in urls {
            guard let sourceImage = NSImage(contentsOf: url),
                  let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }
            let srcBytes = ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            totalBefore += Int64(srcBytes)

            let srcW = CGFloat(cgImage.width)
            let srcH = CGFloat(cgImage.height)
            let longest = max(srcW, srcH)
            let scale = (longest > maxDimension && maxDimension > 0) ? (maxDimension / longest) : 1.0
            let dstW = max(1, Int(round(srcW * scale)))
            let dstH = max(1, Int(round(srcH * scale)))

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                      data: nil,
                      width: dstW,
                      height: dstH,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else {
                continue
            }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: dstW, height: dstH))
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
            guard let rendered = ctx.makeImage() else { continue }

            let rep = NSBitmapImageRep(cgImage: rendered)
            guard let jpegData = rep.representation(
                using: .jpeg,
                properties: [.compressionFactor: jpegQuality]
            ) else { continue }

            let dir = fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
                ? url.deletingLastPathComponent()
                : fm.temporaryDirectory
            let base = url.deletingPathExtension().lastPathComponent
            let outURL = uniqueURL(in: dir, baseName: "\(base)-compressed", ext: "jpg")
            try jpegData.write(to: outURL, options: [.atomic])
            outputs.append(outURL)
            totalAfter += Int64(jpegData.count)
        }

        guard !outputs.isEmpty else {
            throw NSError(
                domain: "NotchNestDrop",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Drop PNG, JPG, HEIC, or TIFF images to compress."]
            )
        }
        return (outputs, totalBefore, totalAfter)
    }

    @MainActor
    private static func ejectMatchingVolumes(for urls: [URL]) -> String {
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey],
            options: [.skipHiddenVolumes]
        ) ?? []

        var ejected: [String] = []
        for url in urls {
            let stdPath = url.standardizedFileURL.path
            if let matchingVolume = mounted.first(where: { volume in
                let vPath = volume.standardizedFileURL.path
                guard vPath != "/" else { return false }
                return stdPath == vPath || stdPath.hasPrefix(vPath + "/")
            }) {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: matchingVolume)
                    ejected.append(matchingVolume.lastPathComponent)
                } catch {
                    return "Eject failed: \(error.localizedDescription)"
                }
            }
        }
        return ejected.isEmpty
            ? "Drop a mounted USB/DMG volume to eject it."
            : "Ejected \(ejected.joined(separator: ", "))"
    }

    private nonisolated static func runDitto(source: URL, destination: URL, keepParent: Bool = true) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        var args = ["-c", "-k"]
        if keepParent {
            args.append("--keepParent")
        }
        args.append(source.path)
        args.append(destination.path)
        process.arguments = args

        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
            throw NSError(domain: "NotchNestDrop", code: 3, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
    }

    private nonisolated static func uniqueURL(in directory: URL, baseName: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
