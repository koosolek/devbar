import Foundation

/// Picks a free TCP port for newly-started projects so two projects
/// that would otherwise default to the same port (e.g. Vite's 5173)
/// don't collide. Only helps when the project's tooling reads the
/// `PORT` environment variable — frameworks that hardcode ports
/// need their own config fix.
enum PortAllocator {
    static let range: ClosedRange<UInt16> = 4100...4199

    /// First port in `range` not in `occupied`. `nil` if all are taken.
    static func allocate(occupied: Set<UInt16>) -> UInt16? {
        range.first { !occupied.contains($0) }
    }
}
