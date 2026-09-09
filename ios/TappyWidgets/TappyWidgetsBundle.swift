import ActivityKit
import SwiftUI
import TappyKit
import WidgetKit

@main
struct TappyWidgetsBundle: WidgetBundle {
    var body: some Widget { ApprovalLiveActivity() }
}

private enum Island {
    static let lime = Color(red: 0.624, green: 0.910, blue: 0.439)
    static let ink = Color(red: 0.086, green: 0.200, blue: 0.000)

    /// Where the transaction is, 0 through 3. Drives the progress rail so the island shows
    /// movement rather than one frozen word.
    static func stage(_ status: String) -> Int {
        switch status {
        case "PENDING_HUMAN": return 1
        case "SUBMITTED": return 2
        case "EXECUTED": return 3
        default: return 3
        }
    }

    static func icon(_ status: String) -> String {
        switch status {
        case "PENDING_HUMAN": return "faceid"
        case "SUBMITTED": return "paperplane.fill"
        case "EXECUTED": return "checkmark.circle.fill"
        default: return "xmark.circle.fill"
        }
    }

    static func tint(_ status: String) -> Color {
        switch status {
        case "EXECUTED": return lime
        case "REJECTED", "FAILED", "EXPIRED": return Color(red: 0.95, green: 0.4, blue: 0.4)
        default: return lime
        }
    }

    static func failed(_ status: String) -> Bool {
        ["REJECTED", "FAILED", "EXPIRED"].contains(status)
    }
}

/// Four dots and a rail. Filled means done, hollow means still to come — the same shape as the
/// timeline inside the app, so the island reads as the same object seen from outside.
private struct ProgressRail: View {
    let stage: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1..<4) { step in
                Capsule()
                    .fill(step <= stage ? tint : tint.opacity(0.22))
                    .frame(height: 4)
            }
        }
    }
}

/// The Dynamic Island while a transaction is moving.
///
/// The point is that the AI asking for money — and the money then actually going — is visible
/// without opening anything. It is the product's claim made ambient.
struct ApprovalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ApprovalAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            let state = context.state
            let stage = Island.stage(state.status)
            let tint = Island.tint(state.status)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: Island.icon(state.status))
                        Text(context.attributes.verb.capitalized)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(state.amountUsd)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(state.amountEth)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        ProgressRail(stage: stage, tint: tint)
                        HStack {
                            Text(state.counterparty)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(caption(state.status))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(tint)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: Island.icon(state.status)).foregroundStyle(tint)
            } compactTrailing: {
                if state.isPending || state.status == "SUBMITTED" {
                    // A spinner while it is genuinely in flight; the amount once it is not.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(tint)
                        .scaleEffect(0.7)
                } else {
                    Text(state.amountUsd).font(.caption2.bold()).foregroundStyle(tint)
                }
            } minimal: {
                Image(systemName: Island.icon(state.status)).foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }

    private func caption(_ status: String) -> String {
        switch status {
        case "PENDING_HUMAN": return "Open Tappy to approve"
        case "SUBMITTED": return "On Sepolia…"
        case "EXECUTED": return "Done"
        case "REJECTED": return "You declined it"
        default: return "Failed"
        }
    }

    private func lockScreen(_ context: ActivityViewContext<ApprovalAttributes>) -> some View {
        let state = context.state
        let tint = Island.tint(state.status)

        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Island.failed(state.status) ? tint.opacity(0.25) : Island.lime)
                        .frame(width: 44, height: 44)
                    Image(systemName: Island.icon(state.status))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Island.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(state.amountUsd)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(state.counterparty)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            ProgressRail(stage: Island.stage(state.status), tint: tint)
        }
        .padding(16)
        .activityBackgroundTint(Color.white)
        .activitySystemActionForegroundColor(Island.ink)
    }
}
