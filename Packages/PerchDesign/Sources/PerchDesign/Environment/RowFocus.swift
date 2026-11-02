import Observation
import SwiftUI

/// Shared by a RowList so rows can lift the focused row and dim the rest.
@Observable @MainActor
public final class RowFocusContext {
    public var focusedRowID: AnyHashable?
    private var focusedCounts: [AnyHashable: Int] = [:]
    public init() {}

    /// Cards report focus gain and loss; a per-row count makes the result independent of callback order.
    public func report(rowID: AnyHashable, focused: Bool) {
        if focused {
            focusedCounts[rowID, default: 0] += 1
            focusedRowID = rowID
        } else {
            let count = max(0, (focusedCounts[rowID] ?? 0) - 1)
            focusedCounts[rowID] = count == 0 ? nil : count
            if count == 0, focusedRowID == rowID { focusedRowID = nil }
        }
    }
}

extension EnvironmentValues {
    @Entry public var perchRowFocus: RowFocusContext? = nil
    /// Called by cards when their focus changes; set by Row.
    public var perchFocusReporter: (@MainActor (Bool) -> Void)? {
        get { self[FocusReporterKey.self] }
        set { self[FocusReporterKey.self] = newValue }
    }
}

// Plain key rather than @Entry: avoids the "closure may not be comparable" warning.
private struct FocusReporterKey: EnvironmentKey {
    static let defaultValue: (@MainActor (Bool) -> Void)? = nil
}
