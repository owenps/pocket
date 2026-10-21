import AppKit
import SwiftUI

struct CommandSuggestionsView: View {
    let commands: [ConversationCommand]
    let selectedCommand: ConversationCommand?
    let fontSize: Double
    let rowHeight: CGFloat
    let select: (ConversationCommand) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var commandColumnWidth: CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        return ConversationCommand.allCases.map {
            ($0.rawValue as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(commands, id: \.self) { command in
                Button { select(command) } label: {
                    HStack(spacing: 8) {
                        Text(command.rawValue)
                            .monospaced()
                            .frame(width: commandColumnWidth, alignment: .leading)
                            .lineLimit(1)
                        Text(command.summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                    .background {
                        if command == selectedCommand {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(contrast == .increased ? 0.20 : 0.08))
                        }
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("\(command.rawValue), \(command.summary)")
                .accessibilityValue(command == selectedCommand ? "Selected" : "")
                .accessibilityIdentifier("command-\(command.rawValue.dropFirst())")
            }
        }
        .font(.system(size: fontSize))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-suggestions")
    }
}
