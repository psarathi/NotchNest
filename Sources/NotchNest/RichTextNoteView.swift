import AppKit
import Observation
import SwiftUI

enum RichTextFormatAction {
    case bold
    case italic
    case underline
    case strikethrough
    case heading
    case monospace
    case bulletList
    case numberedList
    case todoPrefix
}

struct RichTextSelectionState: Equatable {
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var isHeading = false
    var isMonospace = false
    var isBulletList = false
    var isNumberedList = false
}

@MainActor
@Observable
final class RichTextEditorController {
    var state = RichTextSelectionState()
    weak var activeTextView: NotchNoteTextView?
    var baseFontSize: CGFloat = 12
    var inkColor: NSColor = .labelColor

    func focus() {
        guard let textView = activeTextView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func apply(_ action: RichTextFormatAction) {
        guard let textView = activeTextView else { return }
        switch action {
        case .bold:
            toggleFontTrait(.bold, in: textView)
        case .italic:
            toggleFontTrait(.italic, in: textView)
        case .underline:
            toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: textView)
        case .strikethrough:
            toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, in: textView)
        case .heading:
            toggleHeading(in: textView)
        case .monospace:
            toggleMonospace(in: textView)
        case .bulletList:
            toggleLineListPrefix(kind: .bullet, in: textView)
        case .numberedList:
            toggleLineListPrefix(kind: .numbered, in: textView)
        case .todoPrefix:
            insertTodoPrefix(in: textView)
        }
        refreshSelectionState(from: textView)
    }

    func refreshSelectionState(from textView: NSTextView) {
        let storage = textView.textStorage
        let sel = textView.selectedRange()
        let attrs: [NSAttributedString.Key: Any]
        if let storage, storage.length > 0, sel.length > 0 {
            let safeLoc = min(sel.location, storage.length - 1)
            attrs = storage.attributes(at: safeLoc, effectiveRange: nil)
        } else if let storage, storage.length > 0, sel.location > 0 {
            let safeLoc = min(sel.location - 1, storage.length - 1)
            attrs = textView.typingAttributes.isEmpty
                ? storage.attributes(at: safeLoc, effectiveRange: nil)
                : textView.typingAttributes
        } else {
            attrs = textView.typingAttributes
        }

        let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: baseFontSize)
        let traits = font.fontDescriptor.symbolicTraits
        let isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        let isStrike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
        let isHeading = font.pointSize >= baseFontSize + 2.5
        let isMono = traits.contains(.monoSpace) || font.fontName.lowercased().contains("mono")

        let nsText = textView.string as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: min(sel.location, nsText.length), length: 0))
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let trimmedLeft = line.drop(while: { $0 == " " || $0 == "\t" })
        let isBullet = trimmedLeft.hasPrefix("• ")
        let isNumbered = trimmedLeft.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil

        state = RichTextSelectionState(
            isBold: traits.contains(.bold),
            isItalic: traits.contains(.italic),
            isUnderline: isUnderline,
            isStrikethrough: isStrike,
            isHeading: isHeading,
            isMonospace: isMono,
            isBulletList: isBullet,
            isNumberedList: isNumbered
        )
    }

    private func toggleFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, in textView: NSTextView) {
        let storage = textView.textStorage
        let sel = textView.selectedRange()
        let fallbackFont = NSFont.systemFont(ofSize: baseFontSize)

        if sel.length == 0 {
            var typing = textView.typingAttributes
            let current = (typing[.font] as? NSFont) ?? fallbackFont
            typing[.font] = Self.toggling(trait: trait, on: current)
            typing[.foregroundColor] = inkColor
            textView.typingAttributes = typing
            return
        }

        guard let storage, textView.shouldChangeText(in: sel, replacementString: nil) else { return }
        let startFont = (storage.attribute(.font, at: sel.location, effectiveRange: nil) as? NSFont) ?? fallbackFont
        let shouldEnable = !startFont.fontDescriptor.symbolicTraits.contains(trait)

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: sel) { value, subrange, _ in
            let current = (value as? NSFont) ?? fallbackFont
            let next = Self.setting(trait: trait, enabled: shouldEnable, on: current)
            storage.addAttribute(.font, value: next, range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    private func toggleAttribute(_ key: NSAttributedString.Key, value: Int, in textView: NSTextView) {
        let storage = textView.textStorage
        let sel = textView.selectedRange()

        if sel.length == 0 {
            var typing = textView.typingAttributes
            let active = (typing[key] as? Int ?? 0) != 0
            typing[key] = active ? 0 : value
            typing[.foregroundColor] = inkColor
            textView.typingAttributes = typing
            return
        }

        guard let storage, textView.shouldChangeText(in: sel, replacementString: nil) else { return }
        let currentlySet = (storage.attribute(key, at: sel.location, effectiveRange: nil) as? Int ?? 0) != 0
        let newValue = currentlySet ? 0 : value

        storage.beginEditing()
        storage.addAttribute(key, value: newValue, range: sel)
        storage.endEditing()
        textView.didChangeText()
    }

    private func toggleHeading(in textView: NSTextView) {
        let storage = textView.textStorage
        let sel = textView.selectedRange()
        let headingFont = NSFont.systemFont(ofSize: baseFontSize + 4, weight: .bold)
        let bodyFont = NSFont.systemFont(ofSize: baseFontSize)

        if sel.length == 0 {
            let nsText = textView.string as NSString
            let safeRange = NSRange(location: min(sel.location, nsText.length), length: 0)
            let rawLineRange = nsText.lineRange(for: safeRange)
            let trimmedLen = nsText.substring(with: rawLineRange).hasSuffix("\n") ? max(0, rawLineRange.length - 1) : rawLineRange.length
            let lineContentRange = NSRange(location: rawLineRange.location, length: trimmedLen)

            if lineContentRange.length > 0, let storage {
                let firstFont = (storage.attribute(.font, at: lineContentRange.location, effectiveRange: nil) as? NSFont) ?? bodyFont
                let nextFont = (firstFont.pointSize >= baseFontSize + 2.5) ? bodyFont : headingFont
                if textView.shouldChangeText(in: lineContentRange, replacementString: nil) {
                    storage.beginEditing()
                    storage.addAttribute(.font, value: nextFont, range: lineContentRange)
                    storage.endEditing()
                    textView.didChangeText()
                }
                var typing = textView.typingAttributes
                typing[.font] = nextFont
                typing[.foregroundColor] = inkColor
                textView.typingAttributes = typing
            } else {
                var typing = textView.typingAttributes
                let current = (typing[.font] as? NSFont) ?? bodyFont
                typing[.font] = (current.pointSize >= baseFontSize + 2.5) ? bodyFont : headingFont
                typing[.foregroundColor] = inkColor
                textView.typingAttributes = typing
            }
            return
        }

        guard let storage, textView.shouldChangeText(in: sel, replacementString: nil) else { return }
        let current = (storage.attribute(.font, at: sel.location, effectiveRange: nil) as? NSFont) ?? bodyFont
        let nextFont = (current.pointSize >= baseFontSize + 2.5) ? bodyFont : headingFont
        storage.beginEditing()
        storage.addAttribute(.font, value: nextFont, range: sel)
        storage.endEditing()
        textView.didChangeText()
    }

    private func toggleMonospace(in textView: NSTextView) {
        let storage = textView.textStorage
        let sel = textView.selectedRange()
        let monoFont = NSFont.monospacedSystemFont(ofSize: max(10, baseFontSize - 0.5), weight: .regular)
        let bodyFont = NSFont.systemFont(ofSize: baseFontSize)

        if sel.length == 0 {
            var typing = textView.typingAttributes
            let current = (typing[.font] as? NSFont) ?? bodyFont
            let isMono = current.fontDescriptor.symbolicTraits.contains(.monoSpace) || current.fontName.lowercased().contains("mono")
            typing[.font] = isMono ? bodyFont : monoFont
            typing[.foregroundColor] = inkColor
            textView.typingAttributes = typing
            return
        }

        guard let storage, textView.shouldChangeText(in: sel, replacementString: nil) else { return }
        let current = (storage.attribute(.font, at: sel.location, effectiveRange: nil) as? NSFont) ?? bodyFont
        let isMono = current.fontDescriptor.symbolicTraits.contains(.monoSpace) || current.fontName.lowercased().contains("mono")
        let nextFont = isMono ? bodyFont : monoFont
        storage.beginEditing()
        storage.addAttribute(.font, value: nextFont, range: sel)
        storage.endEditing()
        textView.didChangeText()
    }

    private enum LineListKind {
        case bullet
        case numbered
    }

    private func toggleLineListPrefix(kind: LineListKind, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let nsText = textView.string as NSString
        let sel = textView.selectedRange()
        let clampedLoc = min(sel.location, nsText.length)
        let clampedLen = min(sel.length, max(0, nsText.length - clampedLoc))
        let linesRange = nsText.lineRange(for: NSRange(location: clampedLoc, length: clampedLen))
        let block = nsText.substring(with: linesRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var rawLines = block.components(separatedBy: "\n")
        if hadTrailingNewline && rawLines.last == "" {
            rawLines.removeLast()
        }

        let allAlreadyMarked = !rawLines.isEmpty && rawLines.allSatisfy { line in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            switch kind {
            case .bullet: return trimmed.hasPrefix("• ")
            case .numbered: return trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            }
        }

        var nextNumber = 1
        let updatedLines: [String] = rawLines.map { line in
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            var rest = String(line.dropFirst(indent.count))
            // Strip any existing bullet or numbered prefix cleanly first
            rest = rest.replacingOccurrences(of: #"^(?:•\s+|\d+\.\s+)"#, with: "", options: .regularExpression)
            if allAlreadyMarked {
                return indent + rest
            }
            switch kind {
            case .bullet:
                return indent + "• " + rest
            case .numbered:
                let out = indent + "\(nextNumber). " + rest
                nextNumber += 1
                return out
            }
        }

        let replacement = updatedLines.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")
        guard textView.shouldChangeText(in: linesRange, replacementString: replacement) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: linesRange, with: replacement)
        storage.endEditing()
        let newCursor = min(storage.length, linesRange.location + (replacement as NSString).length - (hadTrailingNewline ? 1 : 0))
        textView.setSelectedRange(NSRange(location: max(linesRange.location, newCursor), length: 0))
        textView.didChangeText()
    }

    private func insertTodoPrefix(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let nsText = textView.string as NSString
        let sel = textView.selectedRange()
        let lineRange = nsText.lineRange(for: NSRange(location: min(sel.location, nsText.length), length: 0))
        let lineText = nsText.substring(with: lineRange)
        let indent = String(lineText.prefix(while: { $0 == " " || $0 == "\t" }))
        let afterIndent = String(lineText.dropFirst(indent.count))

        if afterIndent.hasPrefix("[] ") || afterIndent.hasPrefix("[ ] ") || afterIndent.hasPrefix("! ") {
            return
        }

        let insertLoc = lineRange.location + (indent as NSString).length
        let prefix = "[ ] "
        let replaceRange = NSRange(location: insertLoc, length: 0)
        guard textView.shouldChangeText(in: replaceRange, replacementString: prefix) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: replaceRange, with: prefix)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: inkColor
        ]
        storage.addAttributes(attrs, range: NSRange(location: insertLoc, length: (prefix as NSString).length))
        storage.endEditing()
        textView.setSelectedRange(NSRange(location: insertLoc + (prefix as NSString).length, length: 0))
        textView.didChangeText()
    }

    static func toggling(trait: NSFontDescriptor.SymbolicTraits, on font: NSFont) -> NSFont {
        let enabled = !font.fontDescriptor.symbolicTraits.contains(trait)
        return setting(trait: trait, enabled: enabled, on: font)
    }

    static func setting(trait: NSFontDescriptor.SymbolicTraits, enabled: Bool, on font: NSFont) -> NSFont {
        let currentTraits = font.fontDescriptor.symbolicTraits
        let desiredTraits = enabled ? currentTraits.union(trait) : currentTraits.subtracting(trait)
        let descriptor = font.fontDescriptor.withSymbolicTraits(desiredTraits)
        if let converted = NSFont(descriptor: descriptor, size: font.pointSize),
           converted.fontDescriptor.symbolicTraits.contains(trait) == enabled {
            return converted
        }
        let mask: NSFontTraitMask = (trait == .bold) ? .boldFontMask : .italicFontMask
        if enabled {
            return NSFontManager.shared.convert(font, toHaveTrait: mask)
        } else {
            return NSFontManager.shared.convert(font, toNotHaveTrait: mask)
        }
    }
}

final class NotchNoteTextView: NSTextView {
    var onFocusChanged: ((Bool) -> Void)?
    var onRequestPanelFocus: (() -> Void)?
    var baseFontSize: CGFloat = 12
    var inkColor: NSColor = .labelColor
    weak var editorController: RichTextEditorController?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            onRequestPanelFocus?()
            onFocusChanged?(true)
            editorController?.activeTextView = self
            editorController?.refreshSelectionState(from: self)
        }
        return ok
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command], let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "b":
                editorController?.activeTextView = self
                editorController?.apply(.bold)
                return true
            case "i":
                editorController?.activeTextView = self
                editorController?.apply(.italic)
                return true
            case "u":
                editorController?.activeTextView = self
                editorController?.apply(.underline)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length == 0 else {
            super.insertNewline(sender)
            return
        }

        let nsText = string as NSString
        let safeLoc = min(sel.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: safeLoc, length: 0))
        let prefixBeforeCursor = nsText.substring(
            with: NSRange(location: lineRange.location, length: max(0, safeLoc - lineRange.location))
        )

        let indent = String(prefixBeforeCursor.prefix(while: { $0 == " " || $0 == "\t" }))
        let afterIndent = String(prefixBeforeCursor.dropFirst(indent.count))

        // Smart bullet continuation (`• ` -> next `• `; empty bullet exits list)
        if afterIndent.hasPrefix("• ") {
            let contentAfterBullet = String(afterIndent.dropFirst(2))
            if contentAfterBullet.trimmingCharacters(in: .whitespaces).isEmpty {
                let fullLineNoNewline = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
                if fullLineNoNewline.trimmingCharacters(in: .whitespaces) == "•" {
                    let cleanLen = (nsText.substring(with: lineRange).hasSuffix("\n") ? lineRange.length - 1 : lineRange.length)
                    let clearRange = NSRange(location: lineRange.location, length: max(0, cleanLen))
                    if shouldChangeText(in: clearRange, replacementString: "") {
                        textStorage?.replaceCharacters(in: clearRange, with: "")
                        setSelectedRange(NSRange(location: clearRange.location, length: 0))
                        didChangeText()
                    }
                    return
                }
            }
            super.insertNewline(sender)
            insertText(indent + "• ", replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }

        // Smart numbered list continuation (`1. ` -> `2. `; empty exits list)
        if let regex = try? NSRegularExpression(pattern: #"^(\d+)\.\s+(.*)$"#),
           let match = regex.firstMatch(in: afterIndent, range: NSRange(location: 0, length: (afterIndent as NSString).length)),
           match.range(at: 1).location != NSNotFound,
           let num = Int((afterIndent as NSString).substring(with: match.range(at: 1))) {
            let content = (afterIndent as NSString).substring(with: match.range(at: 2))
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                let cleanLen = (nsText.substring(with: lineRange).hasSuffix("\n") ? lineRange.length - 1 : lineRange.length)
                let clearRange = NSRange(location: lineRange.location, length: max(0, cleanLen))
                if shouldChangeText(in: clearRange, replacementString: "") {
                    textStorage?.replaceCharacters(in: clearRange, with: "")
                    setSelectedRange(NSRange(location: clearRange.location, length: 0))
                    didChangeText()
                }
                return
            }
            super.insertNewline(sender)
            insertText("\(indent)\(num + 1). ", replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }

        super.insertNewline(sender)
        // Reset font back to clean body font after a Heading line break
        if let currentFont = typingAttributes[.font] as? NSFont,
           currentFont.pointSize >= baseFontSize + 2.5 {
            var nextTyping = typingAttributes
            nextTyping[.font] = NSFont.systemFont(ofSize: baseFontSize)
            nextTyping[.foregroundColor] = inkColor
            typingAttributes = nextTyping
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let plainInput = (string as? String) ?? (string as? NSAttributedString)?.string
        if plainInput == " " {
            let sel = selectedRange()
            if sel.length == 0 {
                let nsText = self.string as NSString
                let safeLoc = min(sel.location, nsText.length)
                let lineRange = nsText.lineRange(for: NSRange(location: safeLoc, length: 0))
                let prefix = nsText.substring(
                    with: NSRange(location: lineRange.location, length: max(0, safeLoc - lineRange.location))
                )
                let indent = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
                let marker = String(prefix.dropFirst(indent.count))
                if marker == "-" || marker == "*" {
                    let markerRange = NSRange(
                        location: lineRange.location + (indent as NSString).length,
                        length: (marker as NSString).length
                    )
                    let bullet = "• "
                    if shouldChangeText(in: markerRange, replacementString: bullet) {
                        textStorage?.replaceCharacters(in: markerRange, with: bullet)
                        setSelectedRange(NSRange(location: markerRange.location + (bullet as NSString).length, length: 0))
                        didChangeText()
                        return
                    }
                }
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }
}

struct RichTextNoteView: NSViewRepresentable {
    let noteID: UUID
    let plainText: String
    let rtfData: Data?
    let inkColor: NSColor
    let baseFontSize: CGFloat
    let controller: RichTextEditorController
    let onRequestFocus: () -> Void
    let onFocusChange: (Bool) -> Void
    let onContentChange: (_ plainText: String, _ rtfData: Data?, _ commitLastLine: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NotchNoteTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 2, height: 4)

        textView.drawsBackground = false
        textView.isRichText = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isContinuousSpellCheckingEnabled = false

        textView.baseFontSize = baseFontSize
        textView.inkColor = inkColor
        textView.insertionPointColor = inkColor
        textView.editorController = controller
        textView.onRequestPanelFocus = onRequestFocus
        textView.onFocusChanged = onFocusChange
        textView.delegate = context.coordinator

        controller.baseFontSize = baseFontSize
        controller.inkColor = inkColor
        controller.activeTextView = textView

        context.coordinator.loadContent(into: textView, from: self, force: true)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NotchNoteTextView else { return }

        textView.baseFontSize = baseFontSize
        textView.inkColor = inkColor
        textView.insertionPointColor = inkColor
        textView.editorController = controller
        controller.baseFontSize = baseFontSize
        controller.inkColor = inkColor
        if controller.activeTextView == nil {
            controller.activeTextView = textView
        }

        let switchedNote = context.coordinator.loadedNoteID != noteID
        let externalTextChanged = textView.string != plainText
        if switchedNote || externalTextChanged {
            context.coordinator.loadContent(into: textView, from: self, force: switchedNote)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextNoteView
        var loadedNoteID: UUID?
        private var isApplyingModelUpdate = false

        init(parent: RichTextNoteView) {
            self.parent = parent
        }

        func loadContent(into textView: NSTextView, from view: RichTextNoteView, force: Bool) {
            isApplyingModelUpdate = true
            defer { isApplyingModelUpdate = false }

            let previousSel = textView.selectedRange()
            let previousLen = (textView.string as NSString).length

            let attributed = Self.hydrateAttributedString(
                plainText: view.plainText,
                rtfData: view.rtfData,
                baseFontSize: view.baseFontSize,
                inkColor: view.inkColor
            )
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: view.baseFontSize),
                .foregroundColor: view.inkColor
            ]

            loadedNoteID = view.noteID
            if !force {
                let newLen = (textView.string as NSString).length
                let delta = newLen - previousLen
                let adjustedLoc = min(max(0, previousSel.location + delta), newLen)
                textView.setSelectedRange(NSRange(location: adjustedLoc, length: 0))
            }
            view.controller.refreshSelectionState(from: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingModelUpdate, let textView = notification.object as? NSTextView else { return }
            let plain = textView.string
            let rtf = Self.encodeRTF(from: textView.attributedString(), inkColor: parent.inkColor)
            parent.onContentChange(plain, rtf, false)
            parent.controller.refreshSelectionState(from: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
            guard !isApplyingModelUpdate, let textView = notification.object as? NSTextView else { return }
            let plain = textView.string
            let rtf = Self.encodeRTF(from: textView.attributedString(), inkColor: parent.inkColor)
            parent.onContentChange(plain, rtf, true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.controller.refreshSelectionState(from: textView)
        }

        static func hydrateAttributedString(
            plainText: String,
            rtfData: Data?,
            baseFontSize: CGFloat,
            inkColor: NSColor
        ) -> NSAttributedString {
            if let rtfData,
               let decoded = NSMutableAttributedString(rtf: rtfData, documentAttributes: nil),
               decoded.string == plainText {
                let fullRange = NSRange(location: 0, length: decoded.length)
                decoded.addAttribute(.foregroundColor, value: inkColor, range: fullRange)
                decoded.enumerateAttribute(.font, in: fullRange) { val, range, _ in
                    if val == nil {
                        decoded.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFontSize), range: range)
                    }
                }
                return decoded
            }

            return NSAttributedString(
                string: plainText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: baseFontSize),
                    .foregroundColor: inkColor
                ]
            )
        }

        static func encodeRTF(from attributed: NSAttributedString, inkColor: NSColor) -> Data? {
            guard attributed.length > 0 else { return nil }
            let clean = NSMutableAttributedString(attributedString: attributed)
            clean.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: clean.length))
            return try? clean.data(
                from: NSRange(location: 0, length: clean.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }
    }
}

struct RichTextFormatBar: View {
    @Bindable var controller: RichTextEditorController
    let inkColor: Color
    let mutedColor: Color
    let activePillColor: Color
    let compact: Bool
    var onActionComplete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            formatButton(
                title: nil,
                systemImage: "bold",
                active: controller.state.isBold,
                help: "Bold (⌘B)"
            ) {
                controller.apply(.bold)
            }

            formatButton(
                title: nil,
                systemImage: "italic",
                active: controller.state.isItalic,
                help: "Italic (⌘I)"
            ) {
                controller.apply(.italic)
            }

            formatButton(
                title: nil,
                systemImage: "underline",
                active: controller.state.isUnderline,
                help: "Underline (⌘U)"
            ) {
                controller.apply(.underline)
            }

            formatButton(
                title: nil,
                systemImage: "strikethrough",
                active: controller.state.isStrikethrough,
                help: "Strikethrough"
            ) {
                controller.apply(.strikethrough)
            }

            formatButton(
                title: "H",
                systemImage: nil,
                active: controller.state.isHeading,
                help: "Heading"
            ) {
                controller.apply(.heading)
            }

            if !compact {
                formatButton(
                    title: nil,
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    active: controller.state.isMonospace,
                    help: "Monospace / Code"
                ) {
                    controller.apply(.monospace)
                }
            }

            Divider()
                .frame(height: 11)
                .overlay(mutedColor.opacity(0.3))

            formatButton(
                title: nil,
                systemImage: "list.bullet",
                active: controller.state.isBulletList,
                help: "Bullet list (or type '- ')"
            ) {
                controller.apply(.bulletList)
            }

            formatButton(
                title: nil,
                systemImage: "list.number",
                active: controller.state.isNumberedList,
                help: "Numbered list"
            ) {
                controller.apply(.numberedList)
            }

            formatButton(
                title: nil,
                systemImage: "checkmark.square",
                active: false,
                help: "Insert [ ] prefix (or type '! ' / '[] ' + Enter to auto-create Todo)"
            ) {
                controller.apply(.todoPrefix)
            }
        }
    }

    private func formatButton(
        title: String?,
        systemImage: String?,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            onActionComplete?()
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                } else if let title {
                    Text(title)
                        .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(active ? inkColor : mutedColor)
            .frame(width: compact ? 19 : 22, height: compact ? 18 : 20)
            .background(
                active ? activePillColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
