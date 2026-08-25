import SwiftUI
import Domain

/// Recurring payments & income — ported from apps/web/app/recurring/page.tsx.
///
/// **This was a `PlaceholderView`**; `recurring` was a nav-catalog id with no
/// screen behind it on either platform.
///
/// Everything here is a MONTHLY equivalent so a weekly bill and a yearly
/// subscription are comparable; the normalising happens in the view model via
/// the vector-tested `monthlyEquivalent`.
///
/// Scope, matching web minus what is genuinely elsewhere:
/// - **Net monthly cashflow**, the two sides drawn to scale, and a card per
///   direction — all present.
/// - **"Due now"**, with Skip and Record wired to the real engine.
/// - **Savings/SIPs are excluded**, exactly as on web: a SIP is a transfer
///   between your own accounts, so counting it as an outflow would understate
///   what you have spare. They still post and still appear under "Due now".
/// - **Create/edit lives on the direction screens**, not here. Web puts this
///   page's Add in the bottom bar via `useRegisterAddAction` (a two-item
///   payment/income menu); no native screen registers into `AddAction` yet and
///   iOS's `.button` case is a no-op, so there is no honest place to put it on
///   this page. `RecurringFormView` exists as of 2026-08-25 and the direction
///   screens open it. Recorded in ABSENT-BY-DECISION.md.
/// - **The direction rows ARE tappable now** — `RecurringDirectionView` exists
///   as of 2026-08-24. They were inert until it did.
struct RecurringView: View {
    @State private var viewModel = RecurringViewModel()

    /// The drill-down is local state, not a NavigationStack — the same shape
    /// LoansView uses for its loan detail. The shell owns navigation; a screen
    /// pushing its own stack inside it is how the duplicate title bars in W2
    /// happened.
    @State private var openDirection: RecurringDirectionSlug?

    /// Web paints the two halves with
    /// `color-mix(in srgb, var(--negative) 18%, transparent)`. There is no
    /// positive/negative "soft" design token, so the 18% is applied as opacity —
    /// the same number, arrived at the same way.
    private static let barTintOpacity: Double = 0.18

    var body: some View {
        if let slug = openDirection {
            RecurringDirectionView(slug: slug, onBack: { openDirection = nil })
        } else {
            overview
        }
    }

    private var overview: some View {
        ScrollView {
            SanvyaPage(S.Recurring.title) {
                summaryCard
                if !viewModel.due.isEmpty { dueCard }
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { viewModel.start() }
    }

    private var summaryCard: some View {
        SanvyaCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    SanvyaEyebrow(S.Recurring.netMonthly)
                    // The sign is rendered, not baked into the number: a minus
                    // glyph (U+2212) rather than a hyphen, matching web,
                    // because a hyphen in a tabular figure reads as a dash
                    // between two numbers.
                    Text(
                        (viewModel.netMonthlyMinor >= 0 ? "+" : "−")
                            + formatMoney(abs(viewModel.netMonthlyMinor), baseCurrencyNow())
                    )
                    .sanvyaStyle(SanvyaType.statValue)
                    .foregroundStyle(viewModel.netMonthlyMinor >= 0 ? Color.positive : Color.negative)
                }

                cashflowBar

                directionRow(
                    label: S.Recurring.incomes,
                    amount: viewModel.incomeMonthlyMinor,
                    sign: "+",
                    color: Color.positive,
                    count: viewModel.incomeCount,
                    emptyText: S.Recurring.emptyIncome,
                    onTap: { openDirection = .income }
                )
                directionRow(
                    label: S.Recurring.payments,
                    amount: viewModel.expenseMonthlyMinor,
                    sign: "−",
                    color: Color.negative,
                    count: viewModel.expenseCount,
                    emptyText: S.Recurring.emptyPayment,
                    onTap: { openDirection = .expense }
                )
            }
        }
    }

    /// Income vs expense drawn to scale against each other.
    ///
    /// Widths are shares of the COMBINED total, matching web: the point is the
    /// ratio between the two bars, not either against some fixed maximum.
    /// Renders nothing when both are zero — a bar with no data is decoration.
    @ViewBuilder
    private var cashflowBar: some View {
        let expense = viewModel.expenseMonthlyMinor
        let income = viewModel.incomeMonthlyMinor
        let total = expense + income
        if total > 0 {
            GeometryReader { geo in
                let expenseWidth = geo.size.width * (Double(expense) / Double(total))
                HStack(spacing: 0) {
                    if expense > 0 {
                        barHalf(
                            text: "−" + formatMoney(expense, baseCurrencyNow()),
                            color: Color.negative
                        )
                        .frame(width: expenseWidth)
                    }
                    if income > 0 {
                        barHalf(
                            text: formatMoney(income, baseCurrencyNow()),
                            color: Color.positive
                        )
                    }
                }
            }
            .frame(height: 34)
            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.row))
            .overlay(
                RoundedRectangle(cornerRadius: SanvyaRadius.row)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
    }

    private func barHalf(text: String, color: Color) -> some View {
        color.opacity(Self.barTintOpacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Text(text)
                    .sanvyaStyle(SanvyaType.chip)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            )
    }

    private func directionRow(
        label: String,
        amount: Int64,
        sign: String,
        color: Color,
        count: Int,
        emptyText: String,
        onTap: @escaping () -> Void
    ) -> some View {
        // Tappable as of RecurringDirectionView existing. Inert before that —
        // a row that goes nowhere is worse than a row that reads as a summary.
        Button(action: onTap) {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).sanvyaStyle(SanvyaType.sectionTitle).foregroundStyle(Color.text)
                Text(count == 0 ? emptyText : "\(S.Recurring.itemCount(count: count)) · \(S.Recurring.perMonthLabel)")
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(sign + formatMoney(amount, baseCurrencyNow()))
                .sanvyaStyle(SanvyaType.statValue)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm))
        }
        .buttonStyle(SanvyaLiftPressStyle())
    }

    private var dueCard: some View {
        SanvyaCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(S.Recurring.dueNow)
                    .sanvyaStyle(SanvyaType.sectionTitle)
                    .foregroundStyle(Color.text)
                ForEach(viewModel.due) { item in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).sanvyaStyle(SanvyaType.body).foregroundStyle(Color.text)
                            Text(
                                S.Recurring.dueOn(date: item.nextDue)
                                    + (item.amountFormatted.map { " · \($0)" } ?? "")
                            )
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text2)
                        }
                        Spacer(minLength: 0)
                        SanvyaButton(ghost: true) { viewModel.skip(id: item.id) } label: {
                            Text(S.Recurring.skip)
                        }
                        SanvyaButton { viewModel.record(id: item.id) } label: {
                            Text(S.Recurring.record)
                        }
                    }
                }
            }
        }
    }
}
