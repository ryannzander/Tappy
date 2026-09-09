import ActivityKit
import Foundation
import TappyKit

/// Puts a pending approval in the Dynamic Island so it is visible without opening the app.
///
/// Deliberately best-effort: Live Activities are unavailable on the Simulator's older runtimes,
/// disabled by the user, or absent on phones without a Dynamic Island. None of that is worth
/// failing an approval over — the island is a nicety, the signature is the product.
@MainActor
enum LiveActivity {
    private static var current: Activity<ApprovalAttributes>?

    static func start(_ proposal: MobileProposal, rate: Double) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if current?.attributes.proposalId == proposal.id { return }
        Task { await end() }

        let attributes = ApprovalAttributes(verb: proposal.action.verb, proposalId: proposal.id)
        do {
            current = try Activity.request(
                attributes: attributes,
                content: .init(state: state(proposal, rate: rate), staleDate: nil)
            )
        } catch {
            // Nothing to do and nothing worth interrupting the user for.
            print("[live activity] could not start: \(error.localizedDescription)")
        }
    }

    static func update(_ proposal: MobileProposal, rate: Double) async {
        guard let activity = current, activity.attributes.proposalId == proposal.id else { return }
        await activity.update(.init(state: state(proposal, rate: rate), staleDate: nil))
        // Let the outcome sit on screen for a moment before it disappears.
        if proposal.isSettled {
            await activity.end(nil, dismissalPolicy: .after(.now.addingTimeInterval(4)))
            current = nil
        }
    }

    static func end() async {
        await current?.end(nil, dismissalPolicy: .immediate)
        current = nil
    }

    private static func state(_ p: MobileProposal, rate: Double) -> ApprovalAttributes.ContentState {
        .init(
            status: p.status,
            amountUsd: Format.usd(wei: p.action.amountWei, rate: rate),
            amountEth: Format.eth(wei: p.action.amountWei),
            counterparty: Format.short(p.action.counterparty, lead: 10, tail: 6)
        )
    }
}
