import SwiftUI
import RealityKit
import ARKit

struct PortalARView: UIViewRepresentable {
    @ObservedObject var experienceState: PortalExperienceState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: experienceState)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        configuration.isLightEstimationEnabled = true
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        #if !targetEnvironment(simulator)
        if ARBodyTrackingConfiguration.isSupported {
            arView.renderOptions.insert(.disableGroundingShadows)
        }
        #endif

        context.coordinator.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // No-op. All updates are handled by PortalManager.
    }

    final class Coordinator {
        private let state: PortalExperienceState
        private var manager: PortalManager?

        init(state: PortalExperienceState) {
            self.state = state
        }

        func attach(to arView: ARView) {
            if manager == nil {
                manager = PortalManager(arView: arView, experienceState: state)
            }
        }
    }
}
