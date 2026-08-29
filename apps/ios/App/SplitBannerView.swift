import SwiftUI
import Data

/// Shown when this transaction is one leg of a split expense — a port of the
/// `SplitBanner` in apps/web/app/transactions/[id]/edit/page.tsx.
///
/// One split expense writes up to three private ledger rows, and without this
/// card the user opens one of them and sees a bare amount with nothing to say
/// it belongs to a shared bill. It explains that it is part of one and shows
/// the breakdown — total, your share, who paid, what is owed — with a way into
/// the group, so the split detail is found HERE instead of as three cryptic
/// rows in the list.
///
/// Renders nothing when `split` is nil: an ordinary transaction gets no banner.
struct SplitBannerView: View {
    let split: TransactionSplit?
    /// The signed-in user's id, so "You" can be told from everyone else.
    let myUserId: String?
    let onOpenGroup: (String) -> Void

    /// Positive: you overpaid and are owed the difference. Negative: you owe
    /// it. Minor units on both sides, so the subtraction is exact — the same
    /// `myPaid - myShare` web does, and the reason there is no scaling here.
    private var net: Int64 { myPaid - myShare }
    private var mine: SplitParticipant? { split?.participants.first { $0.userId == myUserId } }
    private var myShare: Int64 { mine?.shareAmount ?? 0 }
    private var myPaid: Int64 { mine?.paidAmount ?? 0 }

    var body: some View {
        if let split {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(S.Transactions.splitBannerTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.text)
                    Spacer()
                    if let groupId = split.groupId {
                        SanvyaChip(openGroupLabel(split), isActive: false) { onOpenGroup(groupId) }
                    }
                }

                stats(split)

                if !split.participants.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(S.Transactions.splitBannerParticipants)
                            .font(.system(size: 12.5))
                            .foregroundColor(.text2)
                        ForEach(split.participants, id: \.userId) { participant in
                            participantRow(participant, currency: split.currency)
                        }
                    }
                }

                Text(S.Transactions.splitBannerFootnote)
                    .font(.system(size: 11.5))
                    .foregroundColor(.text2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Web's `border: 1px solid var(--accent-soft)` over
            // `background: var(--accent-ghost)` — a tinted card, deliberately
            // not the neutral `SanvyaCard`, so it reads as an annotation on the
            // form rather than another field of it.
            .background(Color.accentGhost)
            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous)
                    .stroke(Color.accentSoft, lineWidth: 1)
            )
        }
    }

    private func openGroupLabel(_ split: TransactionSplit) -> String {
        guard let name = split.groupName, !name.isEmpty else { return S.Transactions.splitBannerOpenGroup }
        return S.Transactions.splitBannerOpenNamed(name: name)
    }

    /// The four figures.
    ///
    /// Web lets them flow with `flexWrap: wrap`, and on a phone that always
    /// wraps to two rows — so this IS the wrapped layout, laid out as a fixed
    /// 2x2. `ViewThatFits` is deliberately avoided for the reason FeedbackSheet
    /// gives: a fixed grid is predictable at every Dynamic Type size and a
    /// self-measuring flow is not.
    private func stats(_ split: TransactionSplit) -> some View {
        let currency = split.currency
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 18) {
                stat(S.Transactions.splitBannerTotalBill, formatMoney(split.total, currency), .text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                stat(S.Transactions.splitBannerYourShare, formatMoney(myShare, currency), .text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 18) {
                stat(S.Transactions.splitBannerYouPaid, formatMoney(myPaid, currency), .text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                netStat(currency)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func netStat(_ currency: String) -> some View {
        stat(
            net >= 0 ? S.Transactions.splitBannerOwedToYou : S.Transactions.splitBannerYouOwe,
            // `Math.abs` on web: the label already says which direction it is,
            // so the number is never shown with a minus sign.
            formatMoney(abs(net), currency),
            net >= 0 ? .positive : .negative
        )
    }

    /// One "Total bill / ₹1,240" pair from the banner's stat row.
    private func stat(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 13)).foregroundColor(.text2)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(valueColor)
        }
    }

    private func participantRow(_ participant: SplitParticipant, currency: String) -> some View {
        HStack(spacing: 10) {
            // Web's `p.user_id === me ? "You" : profiles.get(...)?.name ?? "Someone"`.
            // Both fallbacks are translated here; the repository deliberately
            // returns a nil name rather than an English one.
            Text(participantName(participant))
                .font(.system(size: 12.5))
                .foregroundColor(.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(S.Transactions.splitBannerParticipantLine(
                share: formatMoney(participant.shareAmount, currency),
                paid: formatMoney(participant.paidAmount, currency)
            ))
            .font(.system(size: 12.5))
            .foregroundColor(.text2)
        }
    }

    private func participantName(_ participant: SplitParticipant) -> String {
        if participant.userId == myUserId { return S.Transactions.you }
        if let name = participant.name, !name.isEmpty { return name }
        return S.Transactions.someone
    }
}
