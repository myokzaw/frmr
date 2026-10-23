import SwiftUI
import Testing
import UIKit
@testable import frmr

// Black-box acceptance for the "each control rotates in place" model.
struct RotationAcceptanceTests {

    private static let allCases: [UIDeviceOrientation] = [
        .unknown, .portrait, .portraitUpsideDown, .landscapeLeft,
        .landscapeRight, .faceUp, .faceDown
    ]

    // Pose (mod 360, in 0..<360) each usable orientation must show
    private static func pose(_ o: UIDeviceOrientation) -> Double? {
        switch o {
        case .portrait: return 0
        case .portraitUpsideDown: return 180
        case .landscapeLeft: return 90
        case .landscapeRight: return 270
        default: return nil
        }
    }

    // SwiftUI.Angle stores radians, so degrees round-trip with ~1e-13 error;
    // compare poses with a tolerance far below anything visible (1e-6 deg).
    private static let tolerance = 1e-6

    // Circular distance between two angles in degrees
    private static func poseDistance(_ a: Double, _ b: Double) -> Double {
        let m = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(m, 360 - m)
    }

    @Test func everyOrientationFromEveryStartingAngleLandsOnItsPoseOrHolds() {
        let starts: [Double] = [-810, -450, -360, -270, -180, -90, 0, 90, 180, 270, 360, 450, 720, 810]
        for start in starts {
            for o in Self.allCases {
                let out = CameraViewModel.rotationAngle(for: o, current: .degrees(start)).degrees
                if let pose = Self.pose(o) {
                    #expect(Self.poseDistance(out, pose) < Self.tolerance, "start \(start) -> \(o)")
                    #expect(abs(out - start) <= 180 + Self.tolerance, "start \(start) -> \(o)")
                } else {
                    #expect(abs(out - start) < Self.tolerance, "flat/unknown must hold: start \(start) \(o)")
                }
            }
        }
    }

    @Test func longPseudoRandomSequenceNeverDriftsAndNeverSpinsTheLongWay() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 33)
        }
        var angle = Angle.zero
        var lastPose = 0.0
        for _ in 0..<5000 {
            let o = Self.allCases[next() % Self.allCases.count]
            let before = angle.degrees
            angle = CameraViewModel.rotationAngle(for: o, current: angle)
            #expect(abs(angle.degrees - before) <= 180 + Self.tolerance)
            if let p = Self.pose(o) { lastPose = p } else { #expect(angle.degrees == before) }
            #expect(Self.poseDistance(angle.degrees, lastPose) < Self.tolerance)
        }
    }

    @Test func faceUpBetweenTwoLandscapesDoesNotChangeTheShortArc() {
        var a = CameraViewModel.rotationAngle(for: .landscapeLeft, current: .zero)
        a = CameraViewModel.rotationAngle(for: .faceUp, current: a)
        a = CameraViewModel.rotationAngle(for: .landscapeRight, current: a)
        #expect(abs(abs(a.degrees - 90) - 180) < Self.tolerance)
    }

    @Test func quarterTurnsAreNeverMoreThan90() {
        for (from, to) in [(UIDeviceOrientation.portrait, UIDeviceOrientation.landscapeLeft),
                           (.portrait, .landscapeRight),
                           (.landscapeLeft, .portraitUpsideDown),
                           (.landscapeRight, .portraitUpsideDown)] {
            let s = CameraViewModel.rotationAngle(for: from, current: .zero)
            let e = CameraViewModel.rotationAngle(for: to, current: s)
            #expect(abs(abs(e.degrees - s.degrees) - 90) < Self.tolerance)
        }
    }

    // Exact values the matrix above cannot see: the sign of each pose from the
    // upright start (these are what the chrome animates to), the short arc
    // between landscapes, and no wrapping, ever (720 + 90 stays 810).
    @Test func chromeCounterRotatesToTheFourCardinalOrientations() {
        #expect(CameraViewModel.rotationAngle(for: .portrait, current: .degrees(90)) == .zero)
        #expect(CameraViewModel.rotationAngle(for: .portraitUpsideDown, current: .zero) == .degrees(180))
        #expect(CameraViewModel.rotationAngle(for: .landscapeLeft, current: .zero) == .degrees(90))
        #expect(CameraViewModel.rotationAngle(for: .landscapeRight, current: .zero) == .degrees(-90))
    }

    @Test func chromeRotationTakesTheShortArcAndAccumulatesWithoutWrapping() {
        let a = CameraViewModel.rotationAngle(for: .landscapeRight, current: .degrees(90))
        #expect(abs(a.degrees - 90) == 180)
        // 270 is the same pose as -90: no animation
        #expect(CameraViewModel.rotationAngle(for: .landscapeRight, current: .degrees(270)) == .degrees(270))

        var angle = Angle.zero
        angle = CameraViewModel.rotationAngle(for: .portraitUpsideDown, current: angle)
        #expect(angle.degrees == 180)
        angle = CameraViewModel.rotationAngle(for: .landscapeLeft, current: angle)
        #expect(angle.degrees == 90)   // 180 -> 90, delta -90
        angle = CameraViewModel.rotationAngle(for: .portrait, current: angle)
        #expect(angle.degrees == 0)

        // Already on the pose: held, whatever the accumulated turns
        #expect(CameraViewModel.rotationAngle(for: .landscapeLeft, current: .degrees(90)) == .degrees(90))
        #expect(CameraViewModel.rotationAngle(for: .landscapeLeft, current: .degrees(720)) == .degrees(810))
    }
}
