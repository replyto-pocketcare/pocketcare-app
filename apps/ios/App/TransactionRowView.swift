import SwiftUI

/**
 One transaction, as a row.

 Was `private` inside TransactionsView.swift. Promoted 2026-08-25 for the
 dashboard's Recent Activity tile — web renders the same `<TransactionTile>` on
 Transactions, Search, Statements and the dashboard, and a second copy here is
 the re-inlining the audit's component inventory exists to prevent.
 */
struct TransactionRowView: View {
    let item: TransactionListItem

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(avatarColor(item.title))
                .frame(width: 34, height: 34)
                .overlay(Text(item.avatarLetter).font(.system(size: 14, weight: .bold)).foregroundColor(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.text)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color.text2)
                        .lineLimit(2)
                }
                if !item.tagsText.isEmpty {
                    Text(item.tagsText)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color.text2)
                        .lineLimit(1)
                }
                if let account = item.accountName {
                    Text(account).font(.system(size: 11.5)).foregroundColor(Color.text2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.amountFormatted)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(item.isPositive ? Color.positive : Color.text)
                Text(item.dateFormatted).font(.system(size: 11)).foregroundColor(Color.text2)
            }
        }
        .padding(14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
    }
}
