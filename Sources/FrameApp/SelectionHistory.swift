import CoreGraphics

struct SelectionHistory {
    let rect: CGRect
    let displayID: CGDirectDisplayID?

    func rectForRestore(activeDisplayID: CGDirectDisplayID?) -> CGRect? {
        guard let displayID,
              let activeDisplayID,
              displayID == activeDisplayID else {
            return nil
        }

        return rect
    }
}
