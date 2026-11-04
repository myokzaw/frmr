import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Crop tool (F-122-F)
    enum Crop {
        /// Smallest crop side, as a share of the photo's short side. Keeps
        /// the frame big enough to grab and the render from collapsing to a
        /// few pixels.
        static let minimumShortSideFraction: Double = 0.1
        /// Within this share (0…1) of the photo's width or height, a moved
        /// frame snaps onto the photo's edge.
        static let snapDistance: Double = 0.012
        /// A crop edge this close (0…1) to the photo's edge counts as on it,
        /// and a rect this close to the whole photo counts as no crop.
        static let edgeEpsilon: Double = 0.0005
    }
}
