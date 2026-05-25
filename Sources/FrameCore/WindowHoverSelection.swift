import CoreGraphics
import Foundation

public struct WindowHoverSelection {
    public let activationDelay: TimeInterval
    public let movementTolerance: CGFloat
    private var pendingCandidate: WindowCandidate?
    private var pendingStartedAt: TimeInterval?
    private var pendingMouseLocation: CGPoint?
    public private(set) var activeCandidate: WindowCandidate?
    public private(set) var isRegionLockedForSession = false

    public init(activationDelay: TimeInterval = 0.35, movementTolerance: CGFloat = 6) {
        self.activationDelay = activationDelay
        self.movementTolerance = movementTolerance
    }

    public mutating func update(
        candidate: WindowCandidate?,
        mouseLocation: CGPoint,
        isOverHUD: Bool,
        timestamp: TimeInterval
    ) -> WindowCandidate? {
        guard !isRegionLockedForSession, !isOverHUD, let candidate else {
            cancelPendingCandidate()
            activeCandidate = nil
            return nil
        }

        if activeCandidate == candidate, candidate.bounds.contains(mouseLocation) {
            return activeCandidate
        }

        if pendingCandidate != candidate || hasMovedPastTolerance(from: mouseLocation) {
            pendingCandidate = candidate
            pendingStartedAt = timestamp
            pendingMouseLocation = mouseLocation
            activeCandidate = nil
            return nil
        }

        guard let pendingStartedAt,
              timestamp - pendingStartedAt >= activationDelay else {
            return nil
        }

        activeCandidate = candidate
        return candidate
    }

    public mutating func lockRegionEditingForSession() {
        isRegionLockedForSession = true
        cancelPendingCandidate()
        activeCandidate = nil
    }

    public mutating func reset() {
        isRegionLockedForSession = false
        cancelPendingCandidate()
        activeCandidate = nil
    }

    private mutating func cancelPendingCandidate() {
        pendingCandidate = nil
        pendingStartedAt = nil
        pendingMouseLocation = nil
    }

    private func hasMovedPastTolerance(from mouseLocation: CGPoint) -> Bool {
        guard let pendingMouseLocation else {
            return false
        }

        return hypot(mouseLocation.x - pendingMouseLocation.x, mouseLocation.y - pendingMouseLocation.y) > movementTolerance
    }
}
