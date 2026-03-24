import SwiftUI
import AppKit

/// Overlay invisibile che controlla la visibilità dei traffic lights
/// (close/minimize/zoom) della finestra in base allo stato dei pannelli.
struct WindowChromeControls: View {
    let showTrafficLights: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background(
                WindowChromeAccessor(showTrafficLights: showTrafficLights)
            )
    }
}

// MARK: - NSViewRepresentable

private struct WindowChromeAccessor: NSViewRepresentable {
    let showTrafficLights: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let buttonTypes: [NSWindow.ButtonType] = [
                .closeButton, .miniaturizeButton, .zoomButton,
            ]
            for buttonType in buttonTypes {
                guard let button = window.standardWindowButton(buttonType) else { continue }
                let target = showTrafficLights ? CGFloat(1) : CGFloat(0)
                if button.alphaValue != target {
                    button.animator().alphaValue = target
                }
                button.isEnabled = showTrafficLights
            }
        }
    }
}
