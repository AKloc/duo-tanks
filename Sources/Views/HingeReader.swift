import SwiftUI
import UIKit

struct HingeState: Equatable {
    var status: UIHinge.Status
    var degrees: Double

    var isPartiallyOpen: Bool { status == .partiallyOpen }
}

/// Reports the device hinge, or `nil` on hardware without one.
struct HingeReader: UIViewRepresentable {
    let onChange: (HingeState?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.addInteraction(UIHingeInteraction { _, update in
            coordinator.onChange(update.hinge.map { HingeState(status: $0.status, degrees: $0.angle * 180 / .pi) })
        })
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
    }

    final class Coordinator {
        var onChange: (HingeState?) -> Void

        init(onChange: @escaping (HingeState?) -> Void) {
            self.onChange = onChange
        }
    }
}
