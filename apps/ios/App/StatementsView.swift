import SwiftUI
import Domain

/// Statements — ported from apps/web/app/statements/page.tsx.
///
/// **What was here before was not a mock of this screen; it was a different
/// feature that does not exist.** A searchable list of "July 2026", "June
/// 2026", "2025 Annual Statement" cards, the last one wearing a premium
/// padlock — none of it backed by anything, and no statement-generation feature
/// anywhere in the product for it to list. Fabricated UI is worse than a
/// placeholder: a placeholder tells the truth about what is missing.
///
/// Web's Statements is a date-ranged view of real transactions with an
/// income/expense summary, behind the paid gate. That is what this is now: rows
/// grouped per day under a header carrying that day's net, tappable through to
/// the transaction's edit screen, each carrying its category and label tags.
///
/// **Print** stays absent: `window.print()` has no phone equivalent. What
/// replaced it is **Share**, which is the same intent — get this statement out
/// of the app — expressed as the control iOS actually has.
struct StatementsView: View {
    @State private var viewModel = StatementsViewModel()
    @State private var showAnalyze = false
    // The Transactions list's own identifier type rather than a second one:
    // both wrap a transaction id to drive the same edit sheet.
    @State private var editingId: TransactionsView.EditingTransactionId?

    var body: some View {
        ScrollView {
            SanvyaPage(S.Statements.title) {
                // Nothing at all until the entitlement is known — see
                // StatementsViewModel.entitlementKnown for why this is not
                // merely caution.
                if viewModel.entitlementKnown {
                    if viewModel.isPaid { paidContent } else { upsell }
                }
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .sanvyaFormPresentation(isPresented: $showAnalyze) {
            NavigationStack { StatementAnalyzeView() }
        }
        .sanvyaFormPresentation(item: $editingId) { entry in
            EditTransactionView(transactionId: entry.id)
        }
        .onAppear { viewModel.start() }
    }

    private var upsell: some View {
        SanvyaCard(padding: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text(S.Statements.premiumTitle)
                    .sanvyaStyle(SanvyaType.h2)
                    .foregroundStyle(Color.text)
                Text(S.Statements.premiumBody)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
                // No "Go Premium" button: web links to /settings, and wiring one
                // here before the native upgrade flow exists would be a control
                // that goes nowhere.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var paidContent: some View {
        dateRange

        // Web puts both of these at the top of the same screen, side by side.
        // Analyze is a different job -- read someone ELSE's statement -- so it
        // is a link, not a tab; Share stands where web's Print does.
        HStack(spacing: 8) {
            SanvyaButton(ghost: true) { showAnalyze = true } label: {
                Text(S.Statements.analyze).frame(maxWidth: .infinity)
            }
            SanvyaShareLink(label: S.Statements.share, item: viewModel.shareText)
                // Nothing to share before the first row arrives, and an empty
                // share sheet is worse than a dimmed control.
                .disabled(viewModel.days.isEmpty)
                .opacity(viewModel.days.isEmpty ? 0.45 : 1)
        }

        summary
        dayGroups
    }

    /// Native `DatePicker`s, not ISO text fields.
    ///
    /// This is the divergence the audit already records for Groups: Compose has
    /// no `<input type="date">` primitive and Material 3's picker is a dialog
    /// with its own visual language, so Android keeps ISO text — while SwiftUI's
    /// `DatePicker` IS the platform-native control the rest of this app already
    /// uses. No "dates set" toggle here, unlike `EditGroupSheet`: a statement's
    /// range always has both ends (it defaults to this month so far), so there
    /// is no empty state for a toggle to express.
    ///
    /// The view model still speaks ISO strings — that is what the query, the
    /// clamping and the shared statement text all read — so the conversion
    /// happens in these two bindings, through `IsoDay` rather than a
    /// hand-rolled `DateFormatter`.
    private var dateRange: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(
                S.Statements.fromDate,
                selection: startBinding,
                displayedComponents: .date
            )
            // `in: start...` is web's `min={start}`: an inverted range matches
            // no transaction at all. The view model clamps too, for the case
            // where `start` moves past `end`.
            DatePicker(
                S.Statements.toDate,
                selection: endBinding,
                in: (IsoDay.date(from: viewModel.startDate) ?? Date())...,
                displayedComponents: .date
            )
        }
        .tint(Color.accent)
    }

    // Spelled out twice rather than through one key-path helper: a key path to
    // a property on a `@MainActor` type is exactly the kind of thing strict
    // concurrency rejects for reasons that read like a compiler bug, and there
    // is no local compiler here to find out cheaply.
    private var startBinding: Binding<Date> {
        Binding(
            get: { IsoDay.date(from: viewModel.startDate) ?? Date() },
            set: { viewModel.startDate = IsoDay.string(from: $0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { IsoDay.date(from: viewModel.endDate) ?? Date() },
            set: { viewModel.endDate = IsoDay.string(from: $0) }
        )
    }

    private var summary: some View {
        SanvyaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(S.Statements.statementName)
                        .sanvyaStyle(SanvyaType.sectionTitle)
                        .foregroundStyle(Color.text)
                    // Web's subtitle under the statement name. It is also the
                    // line that makes the SHARED text self-describing — a
                    // statement with no period on it is just a list of numbers.
                    Text("\(shortDateLabel(viewModel.startDate)) – \(shortDateLabel(viewModel.endDate))")
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text2)
                }
                summaryRow(S.Statements.income, viewModel.incomeFormatted, Color.positive)
                summaryRow(S.Statements.expenses, viewModel.expenseFormatted, Color.negative)
                summaryRow(S.Statements.transactions, String(viewModel.transactionCount), Color.text)
                summaryRow(
                    S.Statements.netForPeriod,
                    (viewModel.netIsPositive ? "+" : "\u{2212}") + viewModel.netFormatted,
                    viewModel.netIsPositive ? Color.positive : Color.negative
                )
            }
        }
    }

    @ViewBuilder
    private var dayGroups: some View {
        if viewModel.days.isEmpty {
            SanvyaCard {
                Text(S.Statements.noTransactions)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(viewModel.days) { day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        SanvyaEyebrow(day.label)
                        Spacer(minLength: 0)
                        Text((day.isPositive ? "+" : "\u{2212}") + day.netFormatted)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text2)
                    }
                    .padding(.horizontal, 4)

                    ForEach(day.items) { item in
                        // Web's tile is a `<Link href={/transactions/[id]/edit}>`.
                        // A statement row that could not be opened was the only
                        // list in the app where tapping a transaction did
                        // nothing.
                        Button {
                            editingId = TransactionsView.EditingTransactionId(id: item.id)
                        } label: {
                            TransactionRowView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func summaryRow(_ label: String, _ amount: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text2)
            Spacer(minLength: 0)
            Text(amount).sanvyaStyle(SanvyaType.body).foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm))
    }
}
