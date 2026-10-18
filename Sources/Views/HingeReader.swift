import SwiftUI
import UIKit

struct HingeState: Equatable {
    enum Status { case unknown, closed, partiallyOpen, fullyOpen }

    var status: Status
    var degrees: Double

    var isPartiallyOpen: Bool { status == .partiallyOpen }
}

/// Reports the device hinge, or `nil` on hardware without one (or on iOS before 27.1).
struct HingeReader: UIViewRepresentable {
    let onChange: (HingeState?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        guard #available(iOS 27.1, *) else { return view }
        let coordinator = context.coordinator
        view.addInteraction(UIHingeInteraction { _, update in
            coordinator.onChange(update.hinge.map { HingeState(status: HingeState.Status($0.status), degrees: $0.angle * 180 / .pi) })
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

@available(iOS 27.1, *)
private extension HingeState.Status {
    init(_ status: UIHinge.Status) {
        switch status {
        case .closed: self = .closed
        case .partiallyOpen: self = .partiallyOpen
        case .fullyOpen: self = .fullyOpen
        default: self = .unknown
        }
    }
}
