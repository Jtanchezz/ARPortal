import Foundation
import RealityKit
import ARKit
import Combine
import UIKit
import AVFoundation

final class PortalManager: NSObject {
    private let arView: ARView
    private let experienceState: PortalExperienceState
    private var portalAnchor: AnchorEntity?
    private var roomEntity: Entity?
    private var updateSubscription: Cancellable?
    private var isInsidePortal = false

    private var placementIndicator: PlacementIndicator!
    private var lastPlacementTransform: simd_float4x4?
    private var hasPlacedPortal = false

    private var portalSize = SIMD2<Float>(repeating: 0)
    private var mediaScreens: [ModelEntity] = []
    private let mediaService: PortalMediaService
    private var mediaTasks: [Task<Void, Never>] = []
    private var videoPlayers: [AVPlayer] = []
    private var videoLoopObservers: [NSObjectProtocol] = []

    private struct MediaPayload {
        let item: PortalMediaItem
        let imageData: Data?
    }

    private let portalWidth: Float = 1.1
    private let portalHeight: Float = 2.2
    private let portalOffsetDistance: Float = 1.5
    private let doorwayEntryDepth: Float = -0.08
    private let doorwayExitDepth: Float = 0.15

    init(arView: ARView, experienceState: PortalExperienceState) {
        self.arView = arView
        self.experienceState = experienceState
        self.mediaService = PortalMediaService(configuration: PortalManager.mediaConfiguration())
        super.init()

        placementIndicator = PlacementIndicator(arView: arView)
        configureSession()
        setupCoachingOverlay()
        installGestures()
        observeUpdates()
        Task {
            await MainActor.run {
                self.experienceState.setInsidePortal(false)
            }
        }
    }

    deinit {
        updateSubscription?.cancel()
        mediaTasks.forEach { $0.cancel() }
        videoLoopObservers.forEach { NotificationCenter.default.removeObserver($0) }
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
            guard let self else { return }
            self.updatePlacementIndicator()
            self.evaluateCameraPosition()
        }
    }

    private func updatePlacementIndicator() {
        guard !hasPlacedPortal else {
            placementIndicator.hide()
            return
        }

        let centerPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let raycast = arView
            .raycast(from: centerPoint, allowing: .estimatedPlane, alignment: .horizontal)
            .first else {
            placementIndicator.hide()
            lastPlacementTransform = nil
            return
        }

        lastPlacementTransform = raycast.worldTransform
        placementIndicator.show(at: raycast.worldTransform)
    }

    @objc
    @MainActor
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let fallbackLocation = recognizer.location(in: arView)
        let fallbackTransform = arView
            .raycast(from: fallbackLocation, allowing: .estimatedPlane, alignment: .horizontal)
            .first?
            .worldTransform

        guard let transform = lastPlacementTransform ?? fallbackTransform else { return }
        placePortal(at: transform)
    }

    @MainActor
    private func placePortal(at transform: simd_float4x4) {
        if let existingAnchor = portalAnchor {
            arView.scene.removeAnchor(existingAnchor)
        }

        var anchorTransform = Transform(matrix: transform)
        let cameraPosition = arView.cameraTransform.translation
        var portalTranslation = anchorTransform.translation
        let directionFromCamera = SIMD3<Float>(portalTranslation.x - cameraPosition.x,
                                               0,
                                               portalTranslation.z - cameraPosition.z)
        if let forward = directionFromCamera.normalized3() {
            portalTranslation.x = cameraPosition.x + forward.x * portalOffsetDistance
            portalTranslation.z = cameraPosition.z + forward.z * portalOffsetDistance
            anchorTransform.translation = portalTranslation
        }

        let directionToCamera = SIMD3<Float>(cameraPosition.x - anchorTransform.translation.x,
                                             0,
                                             cameraPosition.z - anchorTransform.translation.z)
        if let yawAlignment = directionToCamera.horizontalRotationToFaceForward() {
            anchorTransform.rotation = yawAlignment
        }

        let anchor = AnchorEntity(world: anchorTransform.matrix)

        let portalFrame = makePortalFrame()
        anchor.addChild(portalFrame)

        let roomResult = makeRoomEntity(frameHeight: portalHeight)
        let room = roomResult.room
        room.isEnabled = true
        mediaScreens = roomResult.screens
        anchor.addChild(room)

        arView.scene.addAnchor(anchor)
        portalAnchor = anchor
        roomEntity = room
        portalSize = SIMD2<Float>(portalWidth, portalHeight)
        isInsidePortal = false
        hasPlacedPortal = true
        placementIndicator.hide()

        loadMediaContent()
    }

    private func makePortalFrame() -> Entity {
        let frameRoot = Entity()

        let frameThickness: Float = 0.1
        let depth: Float = 0.12

        let frameColor = UIColor(red: 0.92, green: 0.77, blue: 0.55, alpha: 1.0)
        let frameMaterial = SimpleMaterial(color: frameColor, roughness: 0.25, isMetallic: true)

        let sideMesh = MeshResource.generateBox(size: [frameThickness, portalHeight, depth], cornerRadius: 0.02)
        let topMesh = MeshResource.generateBox(size: [portalWidth + frameThickness * 2, frameThickness, depth], cornerRadius: 0.02)
        let leftPost = ModelEntity(mesh: sideMesh, materials: [frameMaterial])
        leftPost.position = [-portalWidth / 2 - frameThickness / 2, portalHeight / 2, 0]

        let rightPost = ModelEntity(mesh: sideMesh, materials: [frameMaterial])
        rightPost.position = [portalWidth / 2 + frameThickness / 2, portalHeight / 2, 0]

        let topBeam = ModelEntity(mesh: topMesh, materials: [frameMaterial])
        topBeam.position = [0, portalHeight + frameThickness / 2, 0]

        let transitionFloorMesh = MeshResource.generatePlane(width: portalWidth + 1.0, depth: portalWidth + 1.0)
        let transitionFloorMaterial = SimpleMaterial(color: UIColor(red: 0.1, green: 0.12, blue: 0.18, alpha: 1.0), roughness: 0.6, isMetallic: false)
        let transitionFloor = ModelEntity(mesh: transitionFloorMesh, materials: [transitionFloorMaterial])
        transitionFloor.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        transitionFloor.position = [0, 0, -portalWidth * 0.75]

        frameRoot.addChild(leftPost)
        frameRoot.addChild(rightPost)
        frameRoot.addChild(topBeam)
        frameRoot.addChild(transitionFloor)

        return frameRoot
    }

    private func makeRoomEntity(frameHeight: Float) -> (room: Entity, screens: [ModelEntity]) {
        let room = Entity()
        let roomWidth: Float = 4.5
        let roomDepth: Float = 5.2
        let roomHeight: Float = max(frameHeight + 0.4, 3.0)

        let floorMesh = MeshResource.generatePlane(width: roomWidth, depth: roomDepth)
        let floorMaterial = SimpleMaterial(color: UIColor(red: 0.63, green: 0.64, blue: 0.67, alpha: 1.0), roughness: 0.45, isMetallic: false)
        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floor.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        floor.position = [0, 0, -roomDepth / 2]

        let ceilingMesh = MeshResource.generatePlane(width: roomWidth, depth: roomDepth)
        let ceilingMaterial = SimpleMaterial(color: UIColor(white: 0.97, alpha: 1.0), roughness: 0.08, isMetallic: false)
        let ceiling = ModelEntity(mesh: ceilingMesh, materials: [ceilingMaterial])
        ceiling.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        ceiling.position = [0, roomHeight, -roomDepth / 2]

        let wallMaterial = SimpleMaterial(color: UIColor(white: 0.93, alpha: 1.0), roughness: 0.18, isMetallic: false)

        let wallThickness: Float = 0.05
        let leftWall = ModelEntity(mesh: MeshResource.generateBox(size: [wallThickness, roomHeight, roomDepth]), materials: [wallMaterial])
        leftWall.position = [-roomWidth / 2 + wallThickness / 2, roomHeight / 2, -roomDepth / 2]
        let rightWall = ModelEntity(mesh: MeshResource.generateBox(size: [wallThickness, roomHeight, roomDepth]), materials: [wallMaterial])
        rightWall.position = [roomWidth / 2 - wallThickness / 2, roomHeight / 2, -roomDepth / 2]
        let backWall = ModelEntity(mesh: MeshResource.generateBox(size: [roomWidth, roomHeight, wallThickness]), materials: [wallMaterial])
        backWall.position = [0, roomHeight / 2, -roomDepth + wallThickness / 2]

        let frontSegmentWidth = (roomWidth - portalWidth) / 2
        let frontWallLeft = ModelEntity(mesh: MeshResource.generateBox(size: [frontSegmentWidth, frameHeight, wallThickness]), materials: [wallMaterial])
        frontWallLeft.position = [-portalWidth / 2 - frontSegmentWidth / 2, frameHeight / 2, 0.025]
        let frontWallRight = ModelEntity(mesh: MeshResource.generateBox(size: [frontSegmentWidth, frameHeight, wallThickness]), materials: [wallMaterial])
        frontWallRight.position = [portalWidth / 2 + frontSegmentWidth / 2, frameHeight / 2, 0.025]
        let frontWallTop = ModelEntity(mesh: MeshResource.generateBox(size: [portalWidth + 0.2, 0.4, wallThickness]), materials: [wallMaterial])
        frontWallTop.position = [0, frameHeight + 0.2, 0.025]

        room.addChild(floor)
        room.addChild(ceiling)
        room.addChild(leftWall)
        room.addChild(rightWall)
        room.addChild(backWall)
        room.addChild(frontWallLeft)
        room.addChild(frontWallRight)
        room.addChild(frontWallTop)
        let screens = addTelevisions(to: room, roomSize: SIMD3<Float>(roomWidth, roomHeight, roomDepth))

        return (room, screens)
    }

    private func addTelevisions(to room: Entity, roomSize: SIMD3<Float>) -> [ModelEntity] {
        var screens: [ModelEntity] = []
        let screenWidth: Float = 1.1
        let screenHeight: Float = 0.68
        let screenMaterial = SimpleMaterial(color: UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0), roughness: 0.1, isMetallic: true)

        func createScreen(with orientation: simd_quatf, position: SIMD3<Float>) -> ModelEntity {
            let mesh = MeshResource.generatePlane(width: screenWidth, depth: screenHeight)
            let screen = ModelEntity(mesh: mesh, materials: [screenMaterial])
            screen.orientation = orientation
            let offset = orientation.act(SIMD3<Float>(0, 0, 0.015))
            screen.position = position + offset
            return screen
        }

        let halfWidth = roomSize.x / 2 - 0.15
        let eyeLevel: Float = 1.45

        let leftPositions: [SIMD3<Float>] = [
            [-halfWidth, eyeLevel + 0.15, -roomSize.z * 0.35],
            [-halfWidth, eyeLevel - 0.35, -roomSize.z * 0.7]
        ]

        let rightPositions: [SIMD3<Float>] = [
            [halfWidth, eyeLevel + 0.15, -roomSize.z * 0.35],
            [halfWidth, eyeLevel - 0.35, -roomSize.z * 0.7]
        ]

        let backPositions: [SIMD3<Float>] = [
            [-roomSize.x * 0.25, eyeLevel + 0.05, -roomSize.z + 0.15],
            [roomSize.x * 0.25, eyeLevel - 0.35, -roomSize.z + 0.15]
        ]

        let verticalOrientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        let leftOrientation = simd_mul(simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]), verticalOrientation)
        let rightOrientation = simd_mul(simd_quatf(angle: .pi / 2, axis: [0, 1, 0]), verticalOrientation)
        let backOrientation = verticalOrientation

        for position in leftPositions {
            let adjusted = SIMD3<Float>(position.x + 0.03, position.y, position.z)
            let screen = createScreen(with: leftOrientation, position: adjusted)
            room.addChild(screen)
            screens.append(screen)
        }

        for position in rightPositions {
            let adjusted = SIMD3<Float>(position.x - 0.03, position.y, position.z)
            let screen = createScreen(with: rightOrientation, position: adjusted)
            room.addChild(screen)
            screens.append(screen)
        }

        for position in backPositions {
            let adjusted = SIMD3<Float>(position.x, position.y, position.z + 0.03)
            let screen = createScreen(with: backOrientation, position: adjusted)
            room.addChild(screen)
            screens.append(screen)
        }

        return screens
    }

    @MainActor
    private func loadMediaContent() {
        guard !mediaScreens.isEmpty else { return }
        mediaTasks.forEach { $0.cancel() }
        mediaTasks.removeAll()
        videoPlayers.removeAll()
        videoLoopObservers.forEach { NotificationCenter.default.removeObserver($0) }
        videoLoopObservers.removeAll()

        resetScreensToPlaceholder()

        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let items = await mediaService.loadMedia()
            let payloads = await self.prepareMediaPayloads(for: items)
            await self.applyMediaPayloads(payloads)
        }

        mediaTasks.append(task)
    }

    private func prepareMediaPayloads(for items: [PortalMediaItem]) async -> [MediaPayload] {
        guard !items.isEmpty else { return [] }

        return await withTaskGroup(of: MediaPayload?.self) { group in
            for item in items {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    switch item.type {
                    case .image:
                        if let data = try? await self.imageData(for: item) {
                            return MediaPayload(item: item, imageData: data)
                        } else if item.assetName != nil {
                            return MediaPayload(item: item, imageData: nil)
                        } else {
                            return nil
                        }
                    case .video:
                        return MediaPayload(item: item, imageData: nil)
                    }
                }
            }

            var payloads: [MediaPayload] = []
            for await result in group {
                if let payload = result {
                    payloads.append(payload)
                }
            }
            return payloads
        }
    }

    private func imageData(for item: PortalMediaItem) async throws -> Data {
        if let url = item.url {
            if url.isFileURL {
                return try Data(contentsOf: url)
            } else {
                let (data, _) = try await URLSession.shared.data(from: url)
                return data
            }
        }
        throw NSError(domain: "PortalMedia", code: -3, userInfo: [NSLocalizedDescriptionKey: "No URL available for item \(item.id)"])
    }

    @MainActor
    private func applyMediaPayloads(_ payloads: [MediaPayload]) async {
        guard !mediaScreens.isEmpty else { return }

        guard !payloads.isEmpty else {
            resetScreensToPlaceholder()
            return
        }

        for (index, screen) in mediaScreens.enumerated() {
            let payload = payloads[index % payloads.count]
            await assign(payload, to: screen)
        }
    }

    @MainActor
    private func resetScreensToPlaceholder() {
        let placeholderMaterial = SimpleMaterial(color: UIColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1.0), roughness: 0.2, isMetallic: false)
        mediaScreens.forEach { $0.model?.materials = [placeholderMaterial] }
    }

    @MainActor
    private func assign(_ payload: MediaPayload, to screen: ModelEntity) async {
        switch payload.item.type {
        case .image:
            await assignImage(payload, to: screen)
        case .video:
            assignVideo(payload.item, to: screen)
        }
    }

    @MainActor
    private func assignImage(_ payload: MediaPayload, to screen: ModelEntity) async {
        if let data = payload.imageData, let image = UIImage(data: data) {
            apply(image: image, to: screen)
            return
        }

        if let assetName = payload.item.assetName, let image = UIImage(named: assetName) {
            apply(image: image, to: screen)
            return
        }

        if let url = payload.item.url {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    apply(image: image, to: screen)
                }
            } catch {
                print("Failed to load image \(String(describing: payload.item.url)): \(error.localizedDescription)")
            }
        }
    }

    private func apply(image: UIImage, to screen: ModelEntity) {
        guard let cgImage = image.cgImage else { return }
        do {
            let texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            screen.model?.materials = [material]
        } catch {
            print("Failed to create texture: \(error.localizedDescription)")
        }
    }

    private func assignVideo(_ item: PortalMediaItem, to screen: ModelEntity) {
        guard let url = item.url else { return }
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        let material = VideoMaterial(avPlayer: player)
        screen.model?.materials = [material]
        player.play()
        videoPlayers.append(player)
        videoLoopObservers.append(token)
    }

    private func evaluateCameraPosition() {
        guard let portalAnchor, portalSize.x > 0, portalSize.y > 0 else { return }

        let cameraPosition = arView.cameraTransform.translation
        let localPosition = portalAnchor.convert(position: cameraPosition, from: nil)

        let horizontalLimit = portalSize.x / 2
        let verticalLowerBound: Float = -0.1
        let verticalUpperBound: Float = portalSize.y + 0.35

        let isCenteredHorizontally = abs(localPosition.x) <= horizontalLimit
        let isWithinHeight = localPosition.y >= verticalLowerBound && localPosition.y <= verticalUpperBound
        let crossedIntoRoom = localPosition.z <= doorwayEntryDepth

        let nearPortal = abs(localPosition.z) < 0.35 &&
            abs(localPosition.x) <= horizontalLimit + 0.15 &&
            localPosition.y >= -0.2 &&
            localPosition.y <= verticalUpperBound

        let insideDoorway = crossedIntoRoom && isCenteredHorizontally && isWithinHeight
        roomEntity?.isEnabled = insideDoorway || nearPortal

        if insideDoorway && !isInsidePortal {
            isInsidePortal = true
            updateEnvironmentForPortalState()
        } else if isInsidePortal {
            let exitedThroughDoor = localPosition.z >= doorwayExitDepth
            if exitedThroughDoor {
                isInsidePortal = false
                updateEnvironmentForPortalState()
            }
        }
    }

    private func updateEnvironmentForPortalState() {
        Task {
            await MainActor.run {
                self.experienceState.setInsidePortal(self.isInsidePortal)
            }
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

private extension PortalManager {
    static func mediaConfiguration() -> PortalMediaConfiguration {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PortalMediaEndpoint") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return PortalMediaConfiguration(endpoint: url)
            }
        }
        return .default
    }
}
