import SwiftUI
import Data

/**
 Payments other people say they have made to you, awaiting your confirmation —
 ported from `apps/web/src/payments/PendingSettlements.tsx`.

 **This exists because UPI Intent gives us no callback.** The payer told their
 bank, not us. Only the payee can see the money land, so only the payee can
 close the loop. Without this screen a UPI settlement raised on a phone stayed
 pending until somebody opened the browser — and both people's balances stayed
 wrong in the meantime.

 Note what "Didn't arrive" does NOT do: it does not unwind the payer's ledger
 entry. The ledger is append-only, and if their money really left, that is still
 true. What changes is that the settlement stops counting toward the balance
 between you. Web's own comment, and the reason the two buttons are not mirror
 images.

 Renders nothing when there is nothing pending — web returns null, and an empty
 "Confirm a payment" card would be a permanent piece of furniture asking about
 money nobody sent.

 Mirrors Android's PendingSettlementsCard.kt.
 */
struct PendingSettlementsCard: View {
    let viewModel: SplitsViewModel

    /// ONE picker for the card, not one per row — web keeps a single
    /// `accountId` in page state and every row reads it. Confirming three
    /// payments that all landed in the same account should not mean choosing
    /// that account three times.
    @State private var accountId = ""

    var body: some View {
        if !viewModel.pending.isEmpty {
            SanvyaCard {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(S.Payments.confirmTitle)
                            .sanvyaStyle(SanvyaType.body.weighted(600))
                        Text(S.Payments.confirmIntro)
                            .sanvyaStyle(SanvyaType.body.resized(13))
                            .foregroundStyle(Color.text2)
                    }
                    ForEach(viewModel.pending, id: \.id) { settlement in
                        row(settlement)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func row(_ settlement: PendingSettlement) -> some View {
        let busy = viewModel.busySettlementId == settlement.id
        let anyBusy = viewModel.busySettlementId != nil

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(S.Payments.confirmClaim(name: viewModel.nameOfUser(settlement.fromUser)))
                    .sanvyaStyle(SanvyaType.body.resized(14))
                Spacer(minLength: 8)
                Text(formatMoney(settlement.amount, settlement.currency))
                    .sanvyaStyle(SanvyaType.body.weighted(700))
            }

            // The UPI reference is the one thread tying this to a line in a
            // bank statement, which is exactly what you need when the money is
            // missing.
            if let ref = settlement.upiRef, !ref.isEmpty {
                Text(S.Payments.confirmReference(ref: ref))
                    .sanvyaStyle(SanvyaType.body.resized(11.5))
                    .foregroundStyle(Color.text2)
            }

            Text(S.Payments.confirmReceivedInto)
                .sanvyaStyle(SanvyaType.body.resized(12))
                .foregroundStyle(Color.text2)
            // "" is a real option, not a placeholder: web's empty `<option>`
            // means "don't record a deposit", for money that arrived somewhere
            // this app does not track.
            ChipRow(
                options: [""] + viewModel.accounts.map(\.id),
                selected: accountId,
                label: { id in
                    id.isEmpty
                        ? S.Payments.confirmNoAccount
                        : (viewModel.accounts.first { $0.id == id }?.name ?? "")
                },
                onSelect: { accountId = $0 }
            )

            HStack(spacing: 8) {
                Button(busy ? S.Translation.commonSaving : S.Payments.confirmYes) {
                    viewModel.confirmArrived(settlement, accountId: accountId.isEmpty ? nil : accountId)
                }
                .buttonStyle(.borderedProminent)
                .disabled(anyBusy)

                Button(S.Payments.confirmNo) { viewModel.markDidNotArrive(settlement) }
                    .buttonStyle(.bordered)
                    .disabled(anyBusy)
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
