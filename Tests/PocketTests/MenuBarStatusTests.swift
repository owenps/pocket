import AppKit
import PocketTestSupport
import Testing
@testable import Pocket

@MainActor
struct MenuBarStatusTests {
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func onlyHiddenUnreadShowsAMark(hasUnreadReply: Bool, isExpanded: Bool) async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            if hasUnreadReply {
                state.conversation.draft = "Question"
                #expect(state.submitDraft())
                state.conversation.stopReply()
            }
            if isExpanded { state.openPanel() }
            let status = MenuBarStatus(state: state)
            let marked = hasUnreadReply && !isExpanded
            #expect(status.showsUnreadReply == marked)
            for text in [status.toolTip, status.accessibilityLabel] {
                #expect(text.contains("unread reply") == marked)
                #expect(text.contains("local simulation"))
                #expect(text.contains("assistant not connected"))
                #expect(text.contains("no network"))
                #expect(!text.contains("online"))
            }
        }
    }

    @Test func conversationAndPanelChangesAutomaticallyPublishUnreadStatus() async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            var publishedUnread: Bool?
            var label = ""
            let status = MenuBarStatus(state: state) {
                publishedUnread = $0.showsUnreadReply
                label = $0.accessibilityLabel
            }
            #expect(publishedUnread == false)

            // Opening before any reply must still rearm observation for closing.
            state.openPanel()
            state.conversation.draft = "Question"
            #expect(state.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Reply")
            state.conversation.stopReply()
            #expect(!status.showsUnreadReply)

            state.closePanel()
            try await AsyncTestSupport.wait { publishedUnread == true }
            #expect(label.contains("unread reply"))
            let replyID = try #require(state.conversation.unreadReplyID)
            state.openPanel()
            try await AsyncTestSupport.wait { publishedUnread == false }
            state.closePanel()
            try await AsyncTestSupport.wait { publishedUnread == true }
            #expect(state.conversation.unreadReplyID == replyID)

            state.openPanel()
            state.markReplyViewed(replyID)
            state.closePanel()
            try await AsyncTestSupport.wait { publishedUnread == false }
            #expect(!label.contains("unread reply"))

            // New output while already collapsed must notify without a panel change.
            state.conversation.draft = "Another question"
            #expect(state.submitDraft())
            let nextRun = try await backend.waitForRun(at: 1)
            nextRun.emit("Another reply")
            try await AsyncTestSupport.wait { publishedUnread == true }
            state.resetConversation()
            try await AsyncTestSupport.wait { publishedUnread == false }
        }
    }

    @Test func statusImagesAreMonochromeWithAVisibleUnreadBadge() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            let status = MenuBarStatus(state: state)
            let base = status.image
            state.conversation.draft = "Question"
            #expect(state.submitDraft())
            state.conversation.stopReply()
            try await AsyncTestSupport.wait { status.showsUnreadReply }
            let unread = status.image
            #expect(base.isTemplate && unread.isTemplate)
            #expect(base.size == NSSize(width: 28, height: 18))
            #expect(unread.size == base.size)
            let basePixels = try pixels(base)
            let unreadPixels = try pixels(unread)
            #expect(basePixels.alpha > 0 && unreadPixels.alpha > 0)
            // The approved unread badge is a transparent knockout, not added ink.
            #expect(unreadPixels.alpha != basePixels.alpha)
            #expect(basePixels.monochrome && unreadPixels.monochrome)
        }
    }

    private func pixels(_ image: NSImage) throws -> (alpha: CGFloat, monochrome: Bool) {
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var alpha: CGFloat = 0
        var monochrome = true
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                alpha += color.alphaComponent
                if color.alphaComponent > 0 {
                    monochrome = monochrome
                        && abs(color.redComponent - color.greenComponent) < 0.01
                        && abs(color.greenComponent - color.blueComponent) < 0.01
                }
            }
        }
        return (alpha, monochrome)
    }
}
