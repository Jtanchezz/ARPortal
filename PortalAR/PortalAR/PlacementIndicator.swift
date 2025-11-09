import RealityKit
import UIKit

final class PlacementIndicator {
    private let anchor = AnchorEntity(world: matrix_identity_float4x4)
    private let pulseEntity: Entity
    private weak var arView: ARView?

    init(arView: ARView) {
        self.arView = arView

        let ringMesh = MeshResource.generatePlane(width: 0.35, depth: 0.35)
        let ringMaterial = SimpleMaterial(color: UIColor(red: 0.2, green: 0.85, blue: 0.83, alpha: 0.25), roughness: 0.1, isMetallic: false)
        let ring = ModelEntity(mesh: ringMesh, materials: [ringMaterial])
        ring.name = "PlacementIndicatorRing"
        ring.position.y = 0.001

        let crossMaterial = SimpleMaterial(color: UIColor(red: 0.18, green: 0.72, blue: 0.9, alpha: 0.9), roughness: 0.2, isMetallic: false)
        let vertical = ModelEntity(mesh: MeshResource.generateBox(size: [0.02, 0.001, 0.32]), materials: [crossMaterial])
        vertical.position.y = 0.002
        let horizontal = ModelEntity(mesh: MeshResource.generateBox(size: [0.32, 0.001, 0.02]), materials: [crossMaterial])
        horizontal.position.y = 0.002

        pulseEntity = Entity()
        pulseEntity.addChild(ring)
        pulseEntity.addChild(vertical)
        pulseEntity.addChild(horizontal)

        anchor.addChild(pulseEntity)
        anchor.isEnabled = false
        arView.scene.addAnchor(anchor)
    }

    func show(at transform: simd_float4x4) {
        let placementTransform = Transform(matrix: transform)
        anchor.transform.translation = placementTransform.translation
        anchor.transform.rotation = placementTransform.rotation
        anchor.transform.scale = SIMD3<Float>(repeating: 1)
        anchor.isEnabled = true
    }

    func hide() {
        anchor.isEnabled = false
    }
}
