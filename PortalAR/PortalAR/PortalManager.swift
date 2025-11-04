import Foundation
import RealityKit
import ARKit
import Combine
import UIKit

final class PortalManager: NSObject {
    private let arView: ARView
    private var portalAnchor: AnchorEntity?
    private var roomEntity: Entity?
    private var updateSubscription: Cancellable?
    private var isInsidePortal = false

    init(arView: ARView) {
        self.arView = arView
        super.init()

        configureSession()
        setupCoachingOverlay()
        installGestures()
        observeUpdates()
    }

    private func configureSession() {
        arView.session.delegate = self
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        arView.environment.background = .cameraFeed()
    }

    private func setupCoachingOverlay() {
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.frame = arView.bounds
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)
    }

    private func installGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
    }

    private func observeUpdates() {
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.evaluateCameraPosition()
        }
    }

    @objc
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: arView)
        guard let raycast = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
        placePortal(at: raycast.worldTransform)
    }

    private func placePortal(at transform: simd_float4x4) {
        if let existingAnchor = portalAnchor {
            arView.scene.removeAnchor(existingAnchor)
        }

        var anchorTransform = Transform(matrix: transform)
        let cameraPosition = arView.cameraTransform.translation
        let directionToCamera = SIMD3<Float>(cameraPosition.x - anchorTransform.translation.x,
                                             0,
                                             cameraPosition.z - anchorTransform.translation.z)
        if let yawAlignment = directionToCamera.horizontalRotationToFaceForward() {
            anchorTransform.rotation = yawAlignment
        }

        let anchor = AnchorEntity(world: anchorTransform.matrix)

        let portal = makePortalFrame()
        anchor.addChild(portal)

        let room = makeRoomEntity(frameHeight: portal.visualBounds(relativeTo: anchor).extents.y)
        room.isEnabled = false
        anchor.addChild(room)

        arView.scene.addAnchor(anchor)
        portalAnchor = anchor
        roomEntity = room
        isInsidePortal = false
    }

    private func makePortalFrame() -> Entity {
        let width: Float = 0.9
        let height: Float = 1.95
        let depth: Float = 0.1
        let frameThickness: Float = 0.08

        let frameRoot = Entity()

        let frameColor = UIColor(red: 0.95, green: 0.77, blue: 0.36, alpha: 1.0)
        let material = SimpleMaterial(color: frameColor, roughness: 0.2, isMetallic: true)
        let sideMesh = MeshResource.generateBox(size: [frameThickness, height, depth], cornerRadius: 0.02)
        let topMesh = MeshResource.generateBox(size: [width + frameThickness * 2, frameThickness, depth], cornerRadius: 0.02)
        let portalPlaneMesh = MeshResource.generatePlane(width: width, depth: 0.02)

        let leftPost = ModelEntity(mesh: sideMesh, materials: [material])
        leftPost.position = [-width / 2 - frameThickness / 2, height / 2, 0]

        let rightPost = ModelEntity(mesh: sideMesh, materials: [material])
        rightPost.position = [width / 2 + frameThickness / 2, height / 2, 0]

        let topBeam = ModelEntity(mesh: topMesh, materials: [material])
        topBeam.position = [0, height + frameThickness / 2, 0]

        let portalSurfaceColor = UIColor(red: 0.16, green: 0.43, blue: 0.98, alpha: 1.0)
        let portalSurfaceMaterial = UnlitMaterial(color: portalSurfaceColor)
        let portalSurface = ModelEntity(mesh: portalPlaneMesh, materials: [portalSurfaceMaterial])
        portalSurface.position = [0, height / 2, -0.01]
        portalSurface.components.set(PortalSurfaceComponent())

        let floorMesh = MeshResource.generatePlane(width: width * 2.2, depth: width * 2.2)
        let floorMaterial = SimpleMaterial(color: UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0), roughness: 0.6, isMetallic: false)
        let floorEntity = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floorEntity.position = [0, 0, -width]
        floorEntity.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        frameRoot.addChild(leftPost)
        frameRoot.addChild(rightPost)
        frameRoot.addChild(topBeam)
        frameRoot.addChild(portalSurface)
        frameRoot.addChild(floorEntity)
        frameRoot.position.y = 0

        return frameRoot
    }

    private func makeRoomEntity(frameHeight: Float) -> Entity {
        let room = Entity()
        let roomSize = SIMD3<Float>(x: 4.0, y: 3.0, z: 4.0)
        let box = MeshResource.generateBox(size: roomSize, cornerRadius: 0)
        let baseColor = UIColor(red: 0.10, green: 0.22, blue: 0.46, alpha: 1.0)
        let wallMaterial = SimpleMaterial(color: baseColor, roughness: 0.35, isMetallic: false)

        let boxEntity = ModelEntity(mesh: box, materials: [wallMaterial])
        boxEntity.scale.x = -1 // flip normals to render interior
        boxEntity.position = [0, frameHeight / 2, -roomSize.z / 2]

        let floorMesh = MeshResource.generatePlane(width: roomSize.x, depth: roomSize.z)
        let floorMaterial = SimpleMaterial(color: UIColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1.0), roughness: 0.55, isMetallic: false)
        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floor.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        floor.position = [0, 0.01, -roomSize.z / 2]

        room.addChild(boxEntity)
        room.addChild(floor)
        return room
    }

    private func evaluateCameraPosition() {
        guard let portalAnchor else { return }
        let cameraPosition = arView.cameraTransform.translation
        let localPosition = portalAnchor.convert(position: cameraPosition, from: nil)
        let inside = localPosition.z < -0.05
        guard inside != isInsidePortal else { return }

        isInsidePortal = inside
        roomEntity?.isEnabled = inside

        if inside {
            arView.environment.background = .color(.black)
        } else {
            arView.environment.background = .cameraFeed()
        }
    }
}

extension PortalManager: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("ARSession failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("ARSession interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("ARSession interruption ended")
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
}

private struct PortalSurfaceComponent: Component {}
