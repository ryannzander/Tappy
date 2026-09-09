import ActivityKit
import SwiftUI
import TappyKit
import WidgetKit

@main
struct TappyWidgetsBundle: WidgetBundle {
    var body: some Widget { ApprovalLiveActivity() }
}

/// The Dynamic Island while a transaction waits on you.
///
/// The point is that a pending approval is visible without opening anything — the AI asked,
/// and the phone is holding the request in front of you until you deal with it.
struct ApprovalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ApprovalAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.verb.capitalized, systemImage: icon(context.state.status))
                        .font(.caption).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.headline).font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.amountUsd)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 3) {
                        Text(context.state.counterparty)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if context.state.isPending {
                            Text("Open Tappy to approve with Face ID")
                                .font(.caption2).foregroundStyle(accent)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: icon(context.state.status)).foregroundStyle(accent)
            } compactTrailing: {
                Text(context.state.amountUsd).font(.caption2).bold().foregroundStyle(accent)
            } minimal: {
                Image(systemName: icon(context.state.status)).foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }

    private var accent: Color { Color(red: 0.42, green: 0.30, blue: 0.94) }

    private func icon(_ status: String) -> String {
        switch status {
        case "PENDING_HUMAN": return "faceid"
        case "SUBMITTED": return "arrow.up.circle"
        case "EXECUTED": return "checkmark.circle.fill"
        default: return "xmark.circle.fill"
        }
    }

    private func lockScreen(_ context: ActivityViewContext<ApprovalAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon(context.state.status))
                .font(.title2).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.headline).font(.caption).foregroundStyle(.secondary)
                Text(context.state.amountUsd)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(context.state.counterparty)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(Color.white)
    }
}
