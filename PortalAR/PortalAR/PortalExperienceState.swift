import SwiftUI
import UIKit

@MainActor
final class PortalExperienceState: ObservableObject {
    @Published var isInsidePortal = false
    @Published var showInsideHint = false

    private var hintDismissTask: Task<Void, Never>?
    private let haptics = PortalHaptics()

    func setInsidePortal(_ newValue: Bool) {
        guard newValue != isInsidePortal else { return }
        isInsidePortal = newValue
        haptics.playTransition(isInside: newValue)

        hintDismissTask?.cancel()
        if newValue {
            showInsideHint = true
            hintDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.showInsideHint = false
            }
        } else {
            showInsideHint = false
        }
    }

    func dismissHint() {
        hintDismissTask?.cancel()
        showInsideHint = false
    }
}

@MainActor
private final class PortalHaptics {
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)

    func playTransition(isInside: Bool) {
        impactGenerator.prepare()
        impactGenerator.impactOccurred(intensity: isInside ? 0.9 : 0.4)
    }
}
