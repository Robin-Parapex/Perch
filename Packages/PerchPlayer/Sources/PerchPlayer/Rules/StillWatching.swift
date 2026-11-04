import Foundation

/// Counts automatic advances with no remote input in between. "Are you still watching?" appears
/// before the 4th consecutive automatic advance (policy 3). A manual "Play next" is user input,
/// not an automatic advance.
public struct AutoChainCounter: Sendable, Equatable {
    public private(set) var count: Int

    public init(count: Int = 0) { self.count = count }

    public mutating func automaticAdvance() { count += 1 }
    public mutating func userInput() { count = 0 }
}
