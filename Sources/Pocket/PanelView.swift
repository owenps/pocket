import SwiftUI

struct PanelView: View {
    @Bindable var state: PanelState
    let expand: () -> Void
    let collapse: () -> Void
    let editorHeightChanged: (CGFloat) -> Void
    let submit: () -> Bool
    var transcriptHeightChanged: ((CGFloat) -> Void)? = nil
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var contentVisibility: Double {
        IslandMotion.contentVisibility(surfaceSize: state.surfaceRect.size, expandedSize: state.expandedSize,
                                       expansionProgress: state.expansionProgress)
    }

    private var buddyBehavior: AvatarAnimation.Behavior {
        guard state.isExpanded, contentVisibility >= 0.999, !reduceMotion else { return .inactive }
        return switch state.conversation.replyPhase {
        case .streaming: .speaking
        case .idle: .idle
        default: .resting
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            surface
                .frame(width: state.surfaceRect.width, height: state.surfaceRect.height)
                .offset(x: state.surfaceRect.minX, y: state.surfaceRect.minY)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .preferredColorScheme(.dark)
        .onExitCommand(perform: collapse)
    }

    private var surface: some View {
        ZStack(alignment: .top) {
            // Keep native editors mounted: visibility does not own conversation,
            // selection, undo, or the app-lifetime simulated response task.
            composer
                .frame(width: state.expandedSize.width, height: state.contentHeight, alignment: .top)
                .fixedSize()
                .compositingGroup()
                .blur(radius: reduceMotion ? 0 : 3 * (1 - contentVisibility))
                .opacity(contentVisibility)
                .mask(alignment: .top) {
                    Rectangle().padding(.top, state.bodyLayout.maskTopInset)
                }
                .allowsHitTesting(state.isExpanded && contentVisibility > 0.5)
                .accessibilityHidden(!state.isExpanded)

            Button(action: expand) {
                Group {
                    if state.notchHeight == 0 {
                        Text("Pocket").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(IslandShape(progress: state.expansionProgress))
            }
            .buttonStyle(.plain)
            .opacity(max(0, 1 - state.expansionProgress * 4))
            .allowsHitTesting(!state.isExpanded)
            .accessibilityHidden(state.isExpanded)
            .accessibilityLabel("Open Pocket")
            .help("Open Pocket · \(state.shortcut.title)")
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .background(.black)
        .clipShape(IslandShape(progress: state.expansionProgress))
    }

    private var composer: some View {
        @Bindable var conversation = state.conversation
        let layout = state.bodyLayout
        let entrance = BuddyEntranceMotion.pose(at: state.buddyEntranceProgress, reduceMotion: reduceMotion)
        return VStack(alignment: .leading, spacing: 0) {
            // Mount at zero height too: native measurement must be able to seed
            // a new viewport without reserving an empty conversation area.
            if !state.presentedMessages.isEmpty || layout.transcriptHeight > 0 || layout.transcriptGap > 0 {
                ConversationView(
                    messages: state.presentedMessages,
                    phase: conversation.replyPhase,
                    isExpanded: state.isExpanded && contentVisibility >= 0.999,
                    focusRequest: state.transcriptFocusRequest,
                    onFocusComposer: { state.focusComposer() },
                    animateThinking: !reduceMotion,
                    onReplyViewed: { state.markReplyViewed($0) },
                    onContentHeightChanged: transcriptHeightChanged,
                    fontSize: state.fontSize
                )
                .frame(height: layout.transcriptHeight)
                .padding(.bottom, layout.transcriptGap)
                .id(state.conversationPresentation == .unread)
            }

            HStack(alignment: .top, spacing: 12) {
                if state.showBuddy {
                    AvatarView(appearance: state.avatar, behavior: buddyBehavior)
                        .scaleEffect(entrance.scale, anchor: UnitPoint(x: 0.5, y: 0.8))
                        .offset(y: entrance.offsetY)
                        .opacity(entrance.opacity)
                }

                DraftEditor(
                    text: $conversation.draft,
                    isEditing: state.isExpanded,
                    focusRequest: state.focusRequest,
                    onHeightChange: editorHeightChanged,
                    onSubmit: submit,
                    onFocusConversation: { state.focusConversation() },
                    fontSize: state.fontSize,
                    userName: state.userName
                )
                .frame(height: layout.editorFrameHeight)
                .overlay {
                    if contrast == .increased {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.primary.opacity(0.65), lineWidth: 1)
                            .padding(-4)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: layout.composerHeight, alignment: .center)

                if !conversation.messages.isEmpty {
                    Button("Stop") { conversation.stopReply() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .frame(width: 36, height: min(24, layout.composerHeight))
                        .opacity(conversation.isBusy ? 1 : 0)
                        .disabled(!conversation.isBusy)
                        .accessibilityHidden(!conversation.isBusy)
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Stop simulated reply (⌘.)")
                }
            }
            .frame(height: layout.composerHeight, alignment: .top)

            if let error = state.shortcutError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(height: layout.errorHeight, alignment: .topLeading)
                    .padding(.top, layout.errorTopGap)
            }
        }
        .padding(.horizontal, layout.horizontalInset)
        .padding(.top, layout.topInset)
        .padding(.bottom, layout.bottomInset)
    }
}
