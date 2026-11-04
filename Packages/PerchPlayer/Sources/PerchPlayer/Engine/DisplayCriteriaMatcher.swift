import AVKit
import CoreMedia
import PerchCore
import UIKit

// Approach from Dusk (MIT): build the display criteria from the decision (frame rate plus a format
// description carrying the colour extensions) and set them before the asset loads, so the TV has
// switched mode by the time the first frame arrives; reset to nil when the player goes away.
@MainActor
public final class DisplayCriteriaMatcher {
    private weak var manager: AVDisplayManager?

    public init() {}

    /// True while criteria we set are in force.
    public var isApplied: Bool { manager != nil }

    /// A format description for the decision's dynamic range: SDR BT.709; HDR10 and HDR10+ PQ with
    /// BT.2020 (HEVC); Dolby Vision PQ with BT.2020 as HEVC 'dvh1'.
    public static func formatDescription(for decision: PlaybackDecision) -> CMVideoFormatDescription? {
        let codec: CMVideoCodecType
        let primaries: CFString
        let transfer: CFString
        let matrix: CFString
        switch decision.videoRange {
        case .sdr:
            codec = kCMVideoCodecType_H264
            primaries = kCMFormatDescriptionColorPrimaries_ITU_R_709_2
            transfer = kCMFormatDescriptionTransferFunction_ITU_R_709_2
            matrix = kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
        case .hdr10, .hdr10Plus:
            codec = kCMVideoCodecType_HEVC
            primaries = kCMFormatDescriptionColorPrimaries_ITU_R_2020
            transfer = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
            matrix = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
        case .dolbyVision:
            codec = kCMVideoCodecType_DolbyVisionHEVC
            primaries = kCMFormatDescriptionColorPrimaries_ITU_R_2020
            transfer = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
            matrix = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
        }
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_ColorPrimaries: primaries,
            kCMFormatDescriptionExtension_TransferFunction: transfer,
            kCMFormatDescriptionExtension_YCbCrMatrix: matrix,
        ]
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, codecType: codec,
            width: Int32(decision.width ?? 3840), height: Int32(decision.height ?? 2160),
            extensions: extensions as CFDictionary, formatDescriptionOut: &description)
        return status == noErr ? description : nil
    }

    /// Nil when the frame rate is unknown: the caller then lets AVKit match from the asset itself.
    public static func criteria(for decision: PlaybackDecision) -> AVDisplayCriteria? {
        guard let rate = decision.frameRate, rate > 0, let format = formatDescription(for: decision) else {
            return nil
        }
        return AVDisplayCriteria(refreshRate: Float(rate), formatDescription: format)
    }

    /// Sets the criteria on the window's display manager. Skipped (returns false) when there is no
    /// manager, matching is off in tvOS Settings, or the criteria cannot be built.
    @discardableResult
    public func apply(_ decision: PlaybackDecision, window: UIWindow?) -> Bool {
        let candidate: AVDisplayManager? = window?.avDisplayManager
        guard let manager = candidate, manager.isDisplayCriteriaMatchingEnabled,
            let criteria = Self.criteria(for: decision)
        else { return false }
        manager.preferredDisplayCriteria = criteria
        self.manager = manager
        return true
    }

    /// Hands the display back to the system mode.
    public func reset() {
        manager?.preferredDisplayCriteria = nil
        manager = nil
    }
}
