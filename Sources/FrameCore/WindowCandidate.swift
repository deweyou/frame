import CoreGraphics
import Foundation

public struct WindowCandidate: Equatable {
    public let id: UInt32
    public let ownerProcessID: Int32
    public let bounds: CGRect

    public init(id: UInt32, ownerProcessID: Int32, bounds: CGRect) {
        self.id = id
        self.ownerProcessID = ownerProcessID
        self.bounds = bounds
    }
}
