import SwiftUI
import Data

/// Real port of apps/web/app/cards/page.tsx + src/cards/CreditCard.tsx
/// (task #29), replacing a fake predecessor: hardcoded "Bank • Visa"
/// network label, a fake "Day N" due string instead of real billing-cycle
/// math, a random alternating gradient instead of the account's own
/// color, and a literal no-op `Button(action: {})` "Pay Bill" button.
/// See docs/mobile/screen-specs/credit-cards.md and Android's
/// CreditCardsScreen.kt (same session) for the mirrored implementation.
///
/// Note: docs/features/cards.md describes a three.js/react-three-fiber 3D
/// wallet -- that's stale, the real page.tsx is a plain CSS card list.
/// This screen matches the real source.
private let FALLBACK_PALETTE = ["#3e4a38", "#b06a4f", "#5f6647", "#7c4a3a", "#2b2723"]

struct CreditCardsView: View {
    @Binding var currentTab: NavTab
    @State private var viewModel = CreditCardsViewModel()

    var body: some View {
        SanvyaPage(S.Cards.title) {
            Group {
                if !viewModel.loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.cards.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { i, card in
                                CreditCardPanelView(card: card, index: i, holderName: viewModel.holderName, sources: viewModel.sources, viewModel: viewModel)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
            .sheet(isPresented: Binding(get: { !viewModel.coveredEmis.isEmpty }, set: { if !$0 { viewModel.skipMarkEmisPaid() } })) {
                CoveredEmisSheet(covered: viewModel.coveredEmis, onConfirm: { viewModel.confirmMarkEmisPaid() }, onSkip: { viewModel.skipMarkEmisPaid() })
            }
            // The charges behind the balance, newest first, with the same
            // running total web prints in the header. Presented once here
            // rather than inside each panel: the rows are view-model state, so
            // they survive the list re-rendering behind the scrim.
            .sanvyaModal(
                isPresented: Binding(get: { viewModel.charges != nil }, set: { if !$0 { viewModel.closeCharges() } }),
                label: S.Cards.cardTxnsTitle
            ) {
                if let charges = viewModel.charges {
                    CardChargesPanel(charges: charges, onClose: { viewModel.closeCharges() })
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard").font(.system(size: 28)).foregroundColor(Color.text2)
            // Web's empty state is `emptyBody` under the page title and a
            // `＋ newAccount` link -- no second heading, and no bespoke copy.
            Text(S.Cards.emptyBody)
                .font(.subheadline).foregroundColor(Color.text2).multilineTextAlignment(.center)
            Button("＋ " + S.Cards.newAccount) { currentTab = .accounts }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CreditCardPanelView: View {
    let card: CreditCardUiModel
    let index: Int
    let holderName: String
    let sources: [SettleSourceOption]
    let viewModel: CreditCardsViewModel

    @State private var expanded = false
    @State private var editing: Bool
    @State private var stmt: String
    @State private var due: String
    @State private var limit: String
    @State private var dueAmt: String
    @State private var last4: String
    @State private var fromId: String?
    @State private var amountText = ""
    @State private var error: String?

    init(card: CreditCardUiModel, index: Int, holderName: String, sources: [SettleSourceOption], viewModel: CreditCardsViewModel) {
        self.card = card; self.index = index; self.holderName = holderName; self.sources = sources; self.viewModel = viewModel
        _editing = State(initialValue: !card.hasCycle)
        _stmt = State(initialValue: String(card.statementDay))
        _due = State(initialValue: String(card.dueDay))
        // Seeded, not blank. This is the fix for a live data-loss bug: the form
        // used to open empty and `saveCycle` writes whatever the fields hold,
        // so changing only the statement day and pressing Save erased the
        // user's `pending_due` (and would have erased the credit limit, but for
        // a fallback in the view model). Web seeds its inputs from the loaded
        // detail, so an unchanged save is a no-op.
        _limit = State(initialValue: card.creditLimitMajorText)
        _dueAmt = State(initialValue: card.pendingDueMajorText)
        _last4 = State(initialValue: card.last4 ?? "")
    }

    /// Every stored value the form edits, as one comparable key.
    ///
    /// `@State` set in `init` is captured on the FIRST render only, so a detail
    /// row that lands afterwards would leave the form holding stale blanks --
    /// which is exactly the shape of the bug being fixed. Mirrors Android's
    /// seeding `LaunchedEffect`.
    private var storedSeed: String {
        "\(card.statementDay)|\(card.dueDay)|\(card.last4 ?? "")|\(card.creditLimitMajorText)|\(card.pendingDueMajorText)"
    }

    /// Reset every field to what is actually stored. Only ever called while the
    /// form is closed, or at the moment it opens -- never over live typing.
    private func seedFromCard() {
        stmt = String(card.statementDay)
        due = String(card.dueDay)
        limit = card.creditLimitMajorText
        dueAmt = card.pendingDueMajorText
        last4 = card.last4 ?? ""
    }

    var body: some View {
        let baseColor = card.accountColorHex.flatMap { Color(hex: $0) } ?? Color(hex: FALLBACK_PALETTE[index % FALLBACK_PALETTE.count]) ?? Color.forest

        VStack(spacing: 12) {
            cardFace(baseColor: baseColor)

            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation { expanded.toggle() } } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(S.Cards.spentThisCycle).font(.caption).foregroundColor(Color.text2)
                            Text(card.owedFormatted).font(.system(size: 26, weight: .bold)).foregroundColor(Color.negative)
                            if let l = card.creditLimitFormatted { Text(S.Cards.ofLimit(limit: l)).font(.caption).foregroundColor(Color.text2) }
                        }
                        Spacer()
                        if !expanded, card.hasCycle {
                            VStack(alignment: .trailing, spacing: 2) {
                                if let due = card.dueThisCycleFormatted {
                                    Text(S.Cards.dueThisCycle).font(.caption).foregroundColor(Color.text2)
                                    Text(due).font(.system(size: 18, weight: .bold)).foregroundColor(card.dueThisCycle != 0 ? Color.negative : Color.positive)
                                }
                                if let payBy = card.payByIso {
                                    // Web stacks the label above its value; two
                                    // Texts, not one concatenated string.
                                    Text(S.Cards.payBy).font(.caption2).foregroundColor(Color.text2)
                                    Text(payBy.toDisplayDate()).font(.footnote).fontWeight(.semibold).foregroundColor(Color.text)
                                }
                                // A closed statement whose due date has moved
                                // past this cycle shows "Due this cycle 0";
                                // without this line nothing says where the
                                // balance went. Web renders the same pair
                                // together (cards/page.tsx).
                                if card.rolledToNext, let pending = card.pendingDueFormatted {
                                    Text(S.Cards.dueNextCycle(amount: pending)).font(.caption2).foregroundColor(Color.text2)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 12) {
                        if card.hasCycle {
                            if let avail = card.availableCreditFormatted { Text(S.Cards.availableCredit(amount: avail)).font(.caption).foregroundColor(Color.positive) }
                            if let spend = card.newSpendFormatted { Text(S.Cards.newSpendThisCycle(amount: spend)).font(.caption2).foregroundColor(Color.text2) }
                            if let stmtDate = card.statementDateIso { Text(S.Cards.statement(date: stmtDate.toDisplayDate())).font(.caption2).foregroundColor(Color.text2) }
                            if !editing {
                                HStack(spacing: 12) {
                                    // Web hides this control when the card has
                                    // no charges yet, which is why the count
                                    // travels with the model.
                                    if card.chargeCount > 0 {
                                        Button(S.Cards.viewTransactions) {
                                            viewModel.openCharges(accountId: card.id, currency: card.currency)
                                        }
                                        .font(.footnote)
                                    }
                                    // Seeds explicitly as well as via
                                    // `storedSeed` below: this is what
                                    // guarantees the state the user sees is the
                                    // state that will be saved.
                                    Button(S.Cards.editDetails) { seedFromCard(); editing = true }.font(.footnote)
                                }
                            }
                        }

                        if editing {
                            TextField(S.Cards.statementDay, text: $stmt).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            TextField(S.Cards.dueDay, text: $due).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            TextField(S.Cards.creditLimit, text: $limit).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            TextField(S.Cards.amountDue, text: $dueAmt).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            TextField(S.Cards.cardNumber, text: $last4).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                .onChange(of: last4) { _, v in last4 = String(v.filter(\.isNumber).suffix(4)) }
                            HStack {
                                Button(S.Cards.save) {
                                    Task {
                                        error = await viewModel.saveCycle(accountId: card.id, currency: card.currency, statementDayText: stmt, dueDayText: due, creditLimitMajorText: limit, dueAmountMajorText: dueAmt, last4: last4, existingCreditLimit: card.creditLimit)
                                        if error == nil { editing = false }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                if card.hasCycle { Button(S.Cards.cancel) { editing = false } }
                            }
                        }

                        Divider()

                        Text(S.Cards.settleFrom).font(.caption).foregroundColor(Color.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(sources) { s in
                                    let active = (fromId ?? sources.first?.id) == s.id
                                    Text(s.name)
                                        .font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Capsule().fill(active ? Color.accent.opacity(0.18) : Color.surface2))
                                        .foregroundColor(active ? Color.accent : Color.text2)
                                        .onTapGesture { fromId = s.id }
                                }
                            }
                        }
                        HStack {
                            TextField(S.Cards.amountPlaceholder, text: $amountText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            Button(S.Cards.settle) {
                                Task {
                                    if let from = fromId ?? sources.first?.id {
                                        error = await viewModel.settle(cardAccountId: card.id, currency: card.currency, fromAccountId: from, amountMajorText: amountText)
                                        if error == nil { amountText = "" }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(amountText.isEmpty || sources.isEmpty)
                        }
                        if let error { Text(error).font(.caption).foregroundColor(Color.negative) }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(20)
            .background(Color.surface)
            .cornerRadius(SanvyaRadius.radiusLg)
        }
        // Re-seed if the stored detail changes while the form is closed --
        // notably when the detail row lands after this panel first rendered.
        // Guarded on `!editing` so it can never overwrite live typing.
        .onChange(of: storedSeed) { _, _ in if !editing { seedFromCard() } }
    }

    @ViewBuilder
    private func cardFace(baseColor: Color) -> some View {
        ZStack {
            LinearGradient(colors: [baseColor, shade(baseColor, -0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading) {
                HStack {
                    Text(card.accountName).font(.subheadline).fontWeight(.bold).foregroundColor(.white)
                    Spacer()
                    Text(")))").font(.headline).fontWeight(.bold).foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.91, green: 0.83, blue: 0.66)).frame(width: 40, height: 30)
                Spacer()
                Text(card.last4 != nil ? "••••  ••••  ••••  \(card.last4!)" : "••••  ••••  ••••  ••••")
                    .font(.system(.title3, design: .monospaced)).fontWeight(.bold).foregroundColor(.white)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.Cards.cardHolder).font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7))
                        // Web: `(session?.username || "").trim() || t("cardHolder")` --
                        // an unnamed user still gets a plausible-looking card
                        // rather than a blank line.
                        Text(holderName.isEmpty ? S.Cards.cardHolder : holderName)
                            .font(.subheadline).fontWeight(.bold).foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(S.Accounts.currency).font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7))
                        Text(card.currency).font(.subheadline).fontWeight(.bold).foregroundColor(.white)
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 200)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

/// The charges that add up to the amount due -- newest first, with the running
/// total in the header. Web's `Modal` in cards/page.tsx.
///
/// A plain `VStack`, not a `List`: `sanvyaModal` already puts its panel inside
/// a `ScrollView`, and a `List` nested in one gets no intrinsic height.
private struct CardChargesPanel: View {
    let charges: CardChargesUiModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                Text(S.Cards.cardTxnsTitle).font(.title3).fontWeight(.bold).foregroundColor(Color.text)
                Spacer()
                Text(S.Cards.cardTxnsTotal(amount: charges.totalFormatted))
                    .font(.footnote).foregroundColor(Color.text2)
            }
            if charges.rows.isEmpty {
                Text(S.Cards.noCardTxns).font(.footnote).foregroundColor(Color.text2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(charges.rows.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { Divider().background(Color.border) }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                // Web falls back to the `uncategorised` label
                                // for a charge with no description.
                                Text(descriptionOrFallback(row))
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.text)
                                    .lineLimit(1)
                                Text(row.occurredAtIso.toDisplayDate())
                                    .font(.caption2).foregroundColor(Color.text2)
                            }
                            Spacer()
                            Text(row.amountFormatted).font(.system(size: 14, weight: .bold)).foregroundColor(Color.text)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            HStack {
                Spacer()
                Button(S.Cards.cancel, action: onClose).font(.footnote)
            }
        }
    }

    private func descriptionOrFallback(_ row: CardChargeUiModel) -> String {
        guard let d = row.description, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return S.Cards.uncategorised
        }
        return d
    }
}

private struct CoveredEmisSheet: View {
    let covered: [CoveredEmi]
    let onConfirm: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(S.Cards.emiCoveredTitle).font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text(S.Cards.emiCoveredBody(count: covered.count))
                .font(.subheadline).foregroundColor(Color.text2)
            ForEach(covered, id: \.emiNo) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.Cards.emiNo(n: String(c.emiNo)) + (c.lender.map { " · \($0)" } ?? "")).font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
                        Text(c.dueDate.toDisplayDate()).font(.caption).foregroundColor(Color.text2)
                    }
                    Spacer()
                    Text(formatMoneyINRForCards(c.amount)).fontWeight(.bold).foregroundColor(Color.text)
                }
            }
            HStack {
                Spacer()
                Button(S.Cards.emiCoveredSkip) { onSkip() }
                Button(S.Cards.emiCoveredConfirm) { onConfirm() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}

private func shade(_ color: Color, _ percent: Double) -> Color {
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    func ch(_ c: CGFloat) -> Double { min(1, max(0, Double(c) + percent)) }
    return Color(red: ch(r), green: ch(g), blue: ch(b), opacity: Double(a))
}

/// A card face shows the user's own balances — masked like everywhere else.
/// The removed copy hardcoded INR and ÷100.
private func formatMoneyINRForCards(_ minor: Int64) -> String {
    formatMoney(minor, baseCurrencyNow())
}

private extension String {
    func toDisplayDate() -> String {
        let s = String(prefix(10))
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return s }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard m >= 1, m <= 12 else { return s }
        return "\(d) \(months[m - 1]) \(y)"
    }
}

#Preview {
    CreditCardsView(currentTab: .constant(.cards))
}
