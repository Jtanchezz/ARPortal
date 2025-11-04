import simd

extension SIMD3 where Scalar == Float {
    var lengthSquared: Float {
        dot(self, self)
    }

    func normalized3() -> SIMD3<Float>? {
        let lengthSq = lengthSquared
        guard lengthSq > 1e-5 else { return nil }
        return self / sqrt(lengthSq)
    }

    func horizontalRotationToFaceForward() -> simd_quatf? {
        let forward = SIMD3<Float>(0, 0, -1)
        var horizontal = SIMD3<Float>(x, 0, z)
        guard let direction = horizontal.normalized3() else { return nil }
        return simd_quatf(from: forward, to: direction)
    }
}
