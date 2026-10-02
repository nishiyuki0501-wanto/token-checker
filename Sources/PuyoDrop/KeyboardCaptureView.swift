import AppKit
import SwiftUI

struct KeyboardCaptureView: NSViewRepresentable {
    let onCommand: (GameCommand) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCommand = onCommand
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCommand = onCommand
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCaptureNSView: NSView {
    var onCommand: ((GameCommand) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onCommand?(.left)
        case 124:
            onCommand?(.right)
        case 125:
            onCommand?(.softDrop)
        case 126, 49:
            onCommand?(.rotate)
        case 36, 76:
            onCommand?(.hardDrop)
        case 45, 15:
            onCommand?(.restart)
        case 35:
            onCommand?(.pause)
        default:
            super.keyDown(with: event)
        }
    }
}
