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
/// income/expense summary, behind the paid gate. That is what this is now.
///
/// Deliberately absent, because web's versions do not translate:
/// - **Print.** `window.print()` has no phone equivalent; a share/PDF export is
///   a real feature to design, not a button to add.
///
/// **Analyze** is no longer in that list: `/statements/analyze` landed
/// 2026-08-27 and the link below reaches it, as web's does.
struct StatementsView: View {
    @State private var viewModel = StatementsViewModel()
    @State private var showAnalyze = false

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
        HStack(alignment: .top, spacing: 12) {
            dateField(S.Statements.fromDate, text: $viewModel.startDate)
            dateField(S.Statements.toDate, text: $viewModel.endDate)
        }

        // Web puts this link at the top of the same screen. It is a different
        // job -- read someone ELSE's statement -- so it is a link, not a tab.
        SanvyaButton(ghost: true) { showAnalyze = true } label: {
            Text(S.Statements.analyze).frame(maxWidth: .infinity)
        }

        SanvyaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(S.Statements.statementName)
                    .sanvyaStyle(SanvyaType.sectionTitle)
                    .foregroundStyle(Color.text)
                summaryRow(S.Statements.income, viewModel.incomeFormatted, Color.positive)
                summaryRow(S.Statements.expenses, viewModel.expenseFormatted, Color.negative)
                summaryRow(
                    S.Statements.netForPeriod,
                    (viewModel.netIsPositive ? "+" : "−") + viewModel.netFormatted,
                    viewModel.netIsPositive ? Color.positive : Color.negative
                )
            }
        }

        SanvyaCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(S.Statements.transactions)
                    .sanvyaStyle(SanvyaType.sectionTitle)
                    .foregroundStyle(Color.text)
                if viewModel.transactions.isEmpty {
                    Text(S.Statements.noTransactions)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text2)
                } else {
                    ForEach(viewModel.transactions) { tx in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.title)
                                    .sanvyaStyle(SanvyaType.body)
                                    .foregroundStyle(Color.text)
                                    .lineLimit(1)
                                Text(tx.occurredOn)
                                    .sanvyaStyle(SanvyaType.statLabel)
                                    .foregroundStyle(Color.text2)
                            }
                            Spacer(minLength: 0)
                            Text((tx.isIncome ? "+" : "−") + tx.amountFormatted)
                                .sanvyaStyle(SanvyaType.body)
                                .foregroundStyle(tx.isIncome ? Color.positive : Color.negative)
                        }
                    }
                }
            }
        }
    }

    /// A plain ISO text field, not a date picker.
    ///
    /// Web renders `<input type="date">`, which the browser turns into a native
    /// picker. SwiftUI's `DatePicker` is a real option here and Android's
    /// Compose equivalent is not, so taking it on iOS alone would put the two
    /// platforms' Statements screens out of step over a control neither spec
    /// has settled. Left as text on both, and tracked.
    private func dateField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SanvyaEyebrow(label)
            SanvyaInput(text: text, placeholder: "YYYY-MM-DD")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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
