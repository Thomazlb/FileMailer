import AppKit
import FileMailerCore
import SwiftUI

struct PlainTextBodyEditor: NSViewRepresentable {
    @Binding var text: String
    var isStreaming = false
    @Environment(\.locale) private var locale

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let editor = NSTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.isAutomaticSpellingCorrectionEnabled = true
        editor.isContinuousSpellCheckingEnabled = true
        editor.isGrammarCheckingEnabled = true
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textColor = .labelColor
        editor.insertionPointColor = .controlAccentColor
        editor.font = .preferredFont(forTextStyle: .body)
        editor.textContainerInset = NSSize(width: 18, height: 16)
        editor.string = text
        editor.setAccessibilityIdentifier("compose-body")
        editor.setAccessibilityLabel(FileMailerLocalization(languageIdentifier: locale.identifier).string("Message body"))
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        editor.setAccessibilityLabel(FileMailerLocalization(languageIdentifier: locale.identifier).string("Message body"))
        guard editor.string != text else { return }
        let selection = editor.selectedRanges
        editor.string = text
        editor.selectedRanges = selection
        if isStreaming, editor.window?.firstResponder !== editor {
            editor.scrollRangeToVisible(NSRange(location: editor.string.utf16.count, length: 0))
            editor.alphaValue = 0.90
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                editor.animator().alphaValue = 1
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextBodyEditor

        init(parent: PlainTextBodyEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}
