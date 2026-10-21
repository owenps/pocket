import CoreGraphics
import Foundation

/// Owns poses and deadlines; the native view supplies time and runs the clocks.
struct AvatarAnimation {
    enum Behavior: Equatable {
        case inactive
        case resting // Static baseline for working phases.
        case idle
        case speaking
        case preview // One blink, brief speech, then static until a new request.
    }

    enum State: Equatable {
        case inactive, idle, previewBlink, speaking
    }

    struct Pose: Hashable {
        var mouth: AvatarRenderer.Mouth = .resting
        var eyes: AvatarRenderer.Eyes = .natural
    }

    private(set) var state: State = .inactive
    private(set) var pose = Pose()
    private(set) var drawingOffset = CGPoint.zero
    private(set) var nextDeadline: TimeInterval?

    private let blinkInterval: ClosedRange<TimeInterval>
    private var behavior: Behavior = .inactive
    private var speakingStartedAt: TimeInterval = 0
    private static let mouths: [AvatarRenderer.Mouth] = [.small, .resting, .small, .open, .small, .resting]

    init(blinkInterval: ClosedRange<TimeInterval> = 8...15) {
        self.blinkInterval = blinkInterval
    }

    mutating func update(behavior: Behavior, at time: TimeInterval) {
        guard behavior != self.behavior else {
            advance(to: time)
            return
        }
        self.behavior = behavior
        pose = Pose()
        drawingOffset = .zero
        nextDeadline = nil
        switch behavior {
        case .inactive:
            state = .inactive
        case .resting, .idle:
            resumeBaseline(at: time)
        case .speaking:
            state = .speaking
            speakingStartedAt = time
            advance(to: time)
        case .preview:
            state = .previewBlink
            pose = Pose(eyes: .blink)
            speakingStartedAt = time + 0.125
            nextDeadline = speakingStartedAt
        }
    }

    mutating func advance(to time: TimeInterval) {
        switch state {
        case .inactive:
            return
        case .previewBlink:
            guard time >= speakingStartedAt else { return }
            state = .speaking
            nextDeadline = speakingStartedAt + 1.25
            advance(to: time)
        case .speaking:
            if behavior == .preview, time >= speakingStartedAt + 1.25 {
                state = .inactive
                pose = Pose()
                drawingOffset = .zero
                nextDeadline = nil
                return
            }
            let frame = Int(max(0, time - speakingStartedAt) * 8) % 1680
            let eyeFrame = frame % 48
            pose = Pose(mouth: Self.mouths[frame % Self.mouths.count],
                        eyes: (16..<20).contains(eyeFrame) ? .glance : (eyeFrame == 32 ? .blink : .natural))
            drawingOffset = CGPoint(x: 0.35 * sin(Double(frame % 80) * .pi / 40),
                                    y: 0.35 * sin(Double(frame % 56) * .pi / 28))
        case .idle:
            guard let nextDeadline, time >= nextDeadline else { return }
            if pose.eyes == .blink {
                resumeBaseline(at: time)
            } else {
                pose = Pose(eyes: .blink)
                self.nextDeadline = time + 0.125
            }
        }
    }

    private mutating func resumeBaseline(at time: TimeInterval) {
        state = .idle
        pose = Pose()
        drawingOffset = .zero
        nextDeadline = behavior == .idle ? time + .random(in: blinkInterval) : nil
    }
}
