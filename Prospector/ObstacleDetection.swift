//
//  ObstacleDetection.swift
//  Prospector
//

import ARKit
import simd

@MainActor
final class ObstacleDetection {
    private nonisolated static let cellSize: Float = 0.1
    private nonisolated static let obstacleHeights: ClosedRange<Float> = 0.15...2.0
    private let revealDistance: Float = 1.0
    private let restoreDistance: Float = 1.3
    private let fadeRate: Float = 4

    private(set) var isRunning = false
    private(set) var contentOpacity: Float = 1
    private var revealsSurroundings = false
    private var session: ARKitSession?
    private var updatesTask: Task<Void, Never>?
    private var cellsByAnchor: [UUID: Set<SIMD2<Int32>>] = [:]
    private var occupancy: [SIMD2<Int32>: Int] = [:]

    func start() async -> Bool {
        guard !isRunning else { return true }
        guard SceneReconstructionProvider.isSupported else { return false }

        let session = ARKitSession()
        let authorization = await session.requestAuthorization(for: SceneReconstructionProvider.requiredAuthorizations)
        guard authorization.values.allSatisfy({ $0 == .allowed }) else { return false }

        let provider = SceneReconstructionProvider()
        do {
            try await session.run([provider])
        } catch {
            print("Failed to start obstacle detection: \(error)")
            return false
        }

        self.session = session
        isRunning = true
        updatesTask = Task {
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { return }
                let cells = update.event == .removed ? [] : await Self.occupiedCells(in: update.anchor)
                guard !Task.isCancelled else { return }
                replaceCells(of: update.anchor.id, with: cells)
            }
        }
        return true
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        session?.stop()
        session = nil
        cellsByAnchor = [:]
        occupancy = [:]
        isRunning = false
        revealsSurroundings = false
    }

    func advanceContentOpacity(headPosition: SIMD3<Float>?, deltaTime: Float) -> Float {
        if isRunning, let headPosition {
            let clearance = clearance(around: headPosition, within: restoreDistance)
            if revealsSurroundings {
                revealsSurroundings = clearance < restoreDistance
            } else {
                revealsSurroundings = clearance < revealDistance
            }
        } else {
            revealsSurroundings = false
        }

        if revealsSurroundings {
            contentOpacity = max(0, contentOpacity - fadeRate * deltaTime)
        } else {
            contentOpacity = min(1, contentOpacity + fadeRate * deltaTime)
        }
        return contentOpacity
    }

    private func clearance(around position: SIMD3<Float>, within reach: Float) -> Float {
        let head = SIMD2<Float>(position.x, position.z)
        let center = Self.cell(containing: head)
        let radius = Int32((reach / Self.cellSize).rounded(.up))
        var nearest = reach
        for dx in -radius...radius {
            for dz in -radius...radius {
                let cell = center &+ SIMD2(dx, dz)
                guard occupancy[cell] != nil else { continue }
                let cellCenter = (SIMD2<Float>(cell) + 0.5) * Self.cellSize
                nearest = min(nearest, max(0, simd_distance(cellCenter, head) - Self.cellSize / 2))
            }
        }
        return nearest
    }

    private func replaceCells(of anchorID: UUID, with cells: Set<SIMD2<Int32>>) {
        for cell in cellsByAnchor[anchorID] ?? [] {
            let remaining = (occupancy[cell] ?? 1) - 1
            occupancy[cell] = remaining > 0 ? remaining : nil
        }
        for cell in cells {
            occupancy[cell, default: 0] += 1
        }
        cellsByAnchor[anchorID] = cells.isEmpty ? nil : cells
    }

    private nonisolated static func cell(containing point: SIMD2<Float>) -> SIMD2<Int32> {
        SIMD2<Int32>((point / cellSize).rounded(.down))
    }

    @concurrent
    private nonisolated static func occupiedCells(in anchor: MeshAnchor) async -> Set<SIMD2<Int32>> {
        let vertices = anchor.geometry.vertices
        let faces = anchor.geometry.faces
        let transform = anchor.originFromAnchorTransform
        let vertexBytes = UnsafeRawPointer(vertices.buffer.contents()).advanced(by: vertices.offset)
        let positions = (0..<vertices.count).map { index in
            let base = index * vertices.stride
            let local = SIMD4<Float>(
                vertexBytes.load(fromByteOffset: base, as: Float.self),
                vertexBytes.load(fromByteOffset: base + 4, as: Float.self),
                vertexBytes.load(fromByteOffset: base + 8, as: Float.self),
                1
            )
            let world = transform * local
            return SIMD3<Float>(world.x, world.y, world.z)
        }

        let indexBytes = UnsafeRawPointer(faces.buffer.contents())
        let indicesPerFace = faces.primitive.indexCount
        var cells = Set<SIMD2<Int32>>()
        for face in 0..<faces.count {
            let corners = (0..<3).map { corner in
                let offset = (face * indicesPerFace + corner) * faces.bytesPerIndex
                let index = faces.bytesPerIndex == 2
                    ? Int(indexBytes.load(fromByteOffset: offset, as: UInt16.self))
                    : Int(indexBytes.load(fromByteOffset: offset, as: UInt32.self))
                return positions[index]
            }
            let longestEdge = max(
                simd_distance(corners[0], corners[1]),
                simd_distance(corners[1], corners[2]),
                simd_distance(corners[2], corners[0])
            )
            let steps = max(1, Int((longestEdge / cellSize).rounded(.up)))
            for i in 0...steps {
                for j in 0...(steps - i) {
                    let point = corners[0]
                        + (corners[1] - corners[0]) * (Float(i) / Float(steps))
                        + (corners[2] - corners[0]) * (Float(j) / Float(steps))
                    guard obstacleHeights.contains(point.y) else { continue }
                    cells.insert(cell(containing: SIMD2(point.x, point.z)))
                }
            }
        }
        return cells
    }
}
