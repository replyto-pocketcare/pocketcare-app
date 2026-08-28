import SwiftUI
import Domain
import Data

/// The split editor on Add transaction — ported from the two cards at the foot
/// of `apps/web/app/transactions/new/page.tsx`.
///
/// **The largest single block of web behaviour that was missing from both
/// ports.** Without it a native user could not record a shared dinner at all,
/// and four other features had nothing to hang off: "paid for someone else",
/// auto-split trips, the `?split=` deep link, and Edit's SplitBanner.
///
/// The arithmetic is NOT here. `splitPlan` in Domain decides every number and
/// whether Save is allowed, under 35 vectors; this file only draws it and
/// reports the disagreements the user has to resolve.
///
/// The two cards are mutually exclusive by rendering, exactly as web has it:
/// "paid for someone else" disappears while the split is on, and vice versa. It
/// reads as one decision with two shapes, which is what it is.
///
/// It takes bindings rather than owning state because the state belongs to the
/// save() that reads it — a child that owned it would have to hand it all back.
///
/// Mirrors Android's SplitEditor.kt.
struct SplitEditorView: View {
    let type: String
    let currency: String
    /// The account the money leaves. Named in two sentences web shows under
    /// the payers, so the user knows which of their accounts is being charged.
    let accountName: String
    let me: String
    let groups: [SplitGroup]
    let connections: [UserProfile]
    let plan: SplitPlan
    let totalMinor: Int64
    /// Members of the given group, in `created_at` order.
    let membersOf: (String) -> [String]
    let memberName: (String) -> String

    @Binding var splitOn: Bool
    @Binding var splitTouched: Bool
    @Binding var splitGroupId: String
    @Binding var splitMode: String
    @Binding var splitMembers: [String]
    @Binding var shareText: [String: String]
    @Binding var multiPayer: Bool
    @Binding var paidText: [String: String]
    @Binding var forOtherOn: Bool
    @Binding var forOtherUserId: String

    var body: some View {
        if type == "expense" {
            if !splitOn { forOtherCard }
            if !forOtherOn { splitCard }
        }
    }

    // MARK: - "I paid this for someone else"

    private var forOtherCard: some View {
        SanvyaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.Transactions.paidForSomeone)
                            .sanvyaStyle(SanvyaType.body.weighted(600))
                        Text(S.Transactions.paidForSomeoneHint)
                            .sanvyaStyle(SanvyaType.body.resized(12))
                            .foregroundStyle(Color.text2)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $forOtherOn).labelsHidden()
                }

                if forOtherOn {
                    if connections.isEmpty {
                        // Nobody to owe yet. Web says so rather than showing an
                        // empty picker, and the sentence names where to fix it.
                        Text(S.Transactions.paidForSomeoneNoOne)
                            .sanvyaStyle(SanvyaType.body.resized(12.5))
                            .foregroundStyle(Color.text2)
                    } else {
                        Text(S.Transactions.paidForSomeonePick)
                            .sanvyaStyle(SanvyaType.body.resized(12))
                            .foregroundStyle(Color.text2)
                        FlowLayout(spacing: 6) {
                            ForEach(connections, id: \.id) { person in
                                SanvyaChip(person.name, isActive: forOtherUserId == person.id) {
                                    forOtherUserId = forOtherUserId == person.id ? "" : person.id
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - "Split this expense"

    private var splitCard: some View {
        SanvyaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(S.Transactions.splitExpense)
                        .sanvyaStyle(SanvyaType.body.weighted(600))
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { splitOn },
                        set: { splitTouched = true; splitOn = $0 }
                    )).labelsHidden()
                }
                if splitOn { splitBody }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var splitBody: some View {
        if let auto = groups.first(where: { $0.id == splitGroupId && $0.autoSplit }) {
            // Web explains WHY the trip was chosen for you, and how to decline
            // it -- a preselection with no explanation reads as a bug.
            Text(S.Transactions.autoSplitWith(name: auto.name))
                .sanvyaStyle(SanvyaType.body.resized(12))
                .foregroundStyle(Color.accent)
        }

        Text(S.Transactions.groupTrip)
            .sanvyaStyle(SanvyaType.body.resized(12))
            .foregroundStyle(Color.text2)
        FlowLayout(spacing: 6) {
            ForEach(groups, id: \.id) { group in
                SanvyaChip(group.name, isActive: splitGroupId == group.id) {
                    setGroup(splitGroupId == group.id ? "" : group.id)
                }
            }
        }

        let groupMemberIds = splitGroupId.isEmpty ? [] : membersOf(splitGroupId)
        if splitGroupId.isEmpty {
            Text(S.Transactions.pickGroupPre + S.Transactions.pickGroupLink + ".")
                .sanvyaStyle(SanvyaType.body.resized(12))
                .foregroundStyle(Color.text2)
        } else if groupMemberIds.count < 2 {
            Text(S.Transactions.onlyYou)
                .sanvyaStyle(SanvyaType.body.resized(12))
                .foregroundStyle(Color.text2)
        } else {
            HStack(spacing: 6) {
                ForEach([SplitModes.equal, SplitModes.exact, SplitModes.percent], id: \.self) { mode in
                    SanvyaChip(modeLabel(mode), isActive: splitMode == mode) { splitMode = mode }
                }
            }

            Text(S.Transactions.splitBetween)
                .sanvyaStyle(SanvyaType.body.resized(12))
                .foregroundStyle(Color.text2)
            FlowLayout(spacing: 6) {
                ForEach(groupMemberIds, id: \.self) { uid in
                    SanvyaChip(memberName(uid), isActive: splitMembers.contains(uid)) {
                        toggleMember(uid)
                    }
                }
            }

            if splitMode != SplitModes.equal && !splitMembers.isEmpty { shareFields }
            payerFields
            summary
        }
    }

    // MARK: - per-participant shares

    @ViewBuilder
    private var shareFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(splitMembers.enumerated()), id: \.element) { index, uid in
                AmountRow(
                    label: memberName(uid),
                    text: key($shareText, uid),
                    placeholder: splitMode == SplitModes.percent ? "%" : currency,
                    // The computed share beside the field is the point of the
                    // whole row: in percent mode you type 40 and need to see
                    // what 40% actually is.
                    trailing: formatMoney(index < plan.shares.count ? plan.shares[index] : 0, currency)
                )
            }
            Text(sharesSummaryText)
                .sanvyaStyle(SanvyaType.body.resized(12))
                .foregroundStyle(Color.text2)
        }
    }

    private var sharesSummaryText: String {
        if splitMode == SplitModes.exact {
            let sum = formatMoney(plan.sharesSum, currency)
            let total = formatMoney(totalMinor, currency)
            return plan.sharesSum == totalMinor
                ? S.Transactions.sharesMatch(sum: sum, total: total)
                : S.Transactions.sharesMismatch(sum: sum, total: total)
        }
        // `jsRound` on the SUM, matching Domain's own acceptance test -- three
        // people at 33.33 read as 100 here and are accepted there.
        let pct = String(Int(jsRound(plan.percentSum)))
        return Int(jsRound(plan.percentSum)) == 100
            ? S.Transactions.percentMatch(pct: pct)
            : S.Transactions.percentMismatch(pct: pct)
    }

    // MARK: - payers

    @ViewBuilder
    private var payerFields: some View {
        HStack {
            Text(S.Transactions.multiplePaid).sanvyaStyle(SanvyaType.body.resized(14))
            Spacer(minLength: 0)
            Toggle("", isOn: $multiPayer).labelsHidden()
        }
        if multiPayer {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(splitMembers, id: \.self) { uid in
                    AmountRow(
                        label: S.Transactions.memberPaid(name: memberName(uid)),
                        text: key($paidText, uid),
                        placeholder: currency,
                        trailing: nil
                    )
                }
                let sum = formatMoney(plan.paidSum, currency)
                let total = formatMoney(totalMinor, currency)
                Text(plan.paidSum == totalMinor
                     ? S.Transactions.paidMatch(sum: sum, total: total)
                     : S.Transactions.paidMismatch(sum: sum, total: total))
                    .sanvyaStyle(SanvyaType.body.resized(12))
                    .foregroundStyle(Color.text2)
                // Only one leg of a multi-payer split touches an account of
                // yours; the others are recorded as what they are owed. Web
                // says so here rather than letting the balance surprise you.
                Text(S.Transactions.onlyYourPayment(account: accountName))
                    .sanvyaStyle(SanvyaType.body.resized(11))
                    .foregroundStyle(Color.text2)
            }
        } else {
            Text(S.Transactions.youPaidFrom(total: formatMoney(totalMinor, currency), account: accountName))
                .sanvyaStyle(SanvyaType.body.resized(12))
                .foregroundStyle(Color.text2)
        }
    }

    // MARK: - summary

    /// Your share, and which way the money leans.
    ///
    /// `net` is what you paid minus what you owe. Positive and the others owe
    /// you; negative and you owe them. Web colours the two differently and so
    /// does this, because "you'll owe" and "others owe you" are opposite news.
    @ViewBuilder
    private var summary: some View {
        if plan.valid {
            let myIndex = splitMembers.firstIndex(of: me)
            let myShare: Int64 = {
                guard let i = myIndex, i < plan.shares.count else { return 0 }
                return plan.shares[i]
            }()
            let net = plan.payers.filter(\.isMe).reduce(Int64(0)) { $0 + $1.paidMinor } - myShare
            SanvyaCard(padding: 12, background: Color.surface2) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(S.Transactions.yourShare).sanvyaStyle(SanvyaType.body.resized(13))
                        Text(formatMoney(myShare, currency))
                            .sanvyaStyle(SanvyaType.body.resized(13).weighted(700))
                        Text(S.Transactions.countsInBudget)
                            .sanvyaStyle(SanvyaType.body.resized(13))
                            .foregroundStyle(Color.text2)
                    }
                    if net > 0 {
                        Text(S.Transactions.othersOweYou(amount: formatMoney(net, currency)))
                            .sanvyaStyle(SanvyaType.body.resized(13))
                            .foregroundStyle(Color.positive)
                    }
                    if net < 0 {
                        Text(S.Transactions.youllOwe(amount: formatMoney(-net, currency)))
                            .sanvyaStyle(SanvyaType.body.resized(13))
                            .foregroundStyle(Color.negative)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(S.Transactions.pickTwo)
                .sanvyaStyle(SanvyaType.body.resized(12))
                .foregroundStyle(Color.text2)
        }
    }

    // MARK: - helpers

    /// Choosing a group replaces the participant list with its members.
    private func setGroup(_ groupId: String) {
        splitTouched = true
        splitGroupId = groupId
        splitMembers = groupId.isEmpty ? [] : membersOf(groupId)
    }

    private func toggleMember(_ uid: String) {
        if let i = splitMembers.firstIndex(of: uid) {
            splitMembers.remove(at: i)
        } else {
            splitMembers.append(uid)
        }
    }

    /// A binding into one key of a dictionary binding.
    ///
    /// The raw field text is kept per user id because that is what the user
    /// typed, and `splitPlan` wants it unrounded so it can surface a
    /// disagreement rather than silently absorb it. A missing key reads as ""
    /// so an untouched field renders empty instead of trapping.
    private func key(_ dict: Binding<[String: String]>, _ id: String) -> Binding<String> {
        Binding(get: { dict.wrappedValue[id] ?? "" }, set: { dict.wrappedValue[id] = $0 })
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case SplitModes.exact: return S.Transactions.modeExact
        case SplitModes.percent: return S.Transactions.modePercent
        default: return S.Transactions.modeEqual
        }
    }
}

/// One "name … [field] … computed" row.
private struct AmountRow: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(label).sanvyaStyle(SanvyaType.body.resized(14))
            Spacer(minLength: 0)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
            if let trailing {
                Text(trailing)
                    .sanvyaStyle(SanvyaType.body.resized(12))
                    .foregroundStyle(Color.text2)
                    .frame(width: 80, alignment: .trailing)
            }
        }
    }
}
