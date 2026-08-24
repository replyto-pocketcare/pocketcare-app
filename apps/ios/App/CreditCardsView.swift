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
        NavigationStack {
            Group {
                if !viewModel.loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.cards.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { i, card in
                                CreditCardPanelView(card: card, index: i, sources: viewModel.sources, viewModel: viewModel)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Credit Cards")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
            .sheet(isPresented: Binding(get: { !viewModel.coveredEmis.isEmpty }, set: { if !$0 { viewModel.skipMarkEmisPaid() } })) {
                CoveredEmisSheet(covered: viewModel.coveredEmis, onConfirm: { viewModel.confirmMarkEmisPaid() }, onSkip: { viewModel.skipMarkEmisPaid() })
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard").font(.system(size: 28)).foregroundColor(Color.text2)
            Text("No credit cards yet").font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text("Add a credit-card account to track its billing cycle, dues, and settle-ups here.")
                .font(.subheadline).foregroundColor(Color.text2).multilineTextAlignment(.center)
            Button("＋ Add account") { currentTab = .accounts }
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
    let sources: [SettleSourceOption]
    let viewModel: CreditCardsViewModel

    @State private var expanded = false
    @State private var editing: Bool
    @State private var stmt: String
    @State private var due: String
    @State private var limit = ""
    @State private var dueAmt = ""
    @State private var last4: String
    @State private var fromId: String?
    @State private var amountText = ""
    @State private var error: String?

    init(card: CreditCardUiModel, index: Int, sources: [SettleSourceOption], viewModel: CreditCardsViewModel) {
        self.card = card; self.index = index; self.sources = sources; self.viewModel = viewModel
        _editing = State(initialValue: !card.hasCycle)
        _stmt = State(initialValue: String(card.statementDay))
        _due = State(initialValue: String(card.dueDay))
        _last4 = State(initialValue: card.last4 ?? "")
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
                            if let l = card.creditLimitFormatted { Text("of \(l) limit").font(.caption).foregroundColor(Color.text2) }
                        }
                        Spacer()
                        if !expanded, card.hasCycle {
                            VStack(alignment: .trailing, spacing: 2) {
                                if let due = card.dueThisCycleFormatted {
                                    Text(S.Cards.dueThisCycle).font(.caption).foregroundColor(Color.text2)
                                    Text(due).font(.system(size: 18, weight: .bold)).foregroundColor(card.dueThisCycle != 0 ? Color.negative : Color.positive)
                                }
                                if let payBy = card.payByIso {
                                    Text("Pay by \(payBy.toDisplayDate())").font(.caption2).foregroundColor(Color.text2)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 12) {
                        if card.hasCycle {
                            if let avail = card.availableCreditFormatted { Text("Available credit: \(avail)").font(.caption).foregroundColor(Color.positive) }
                            if let spend = card.newSpendFormatted { Text("+\(spend) new spend since the last statement").font(.caption2).foregroundColor(Color.text2) }
                            if let stmtDate = card.statementDateIso { Text("Statement: \(stmtDate.toDisplayDate())").font(.caption2).foregroundColor(Color.text2) }
                            if !editing {
                                Button(S.Cards.editDetails) { editing = true; limit = ""; dueAmt = "" }.font(.footnote)
                            }
                        }

                        if editing {
                            TextField(S.Cards.statementDay, text: $stmt).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            TextField(S.Cards.dueDay, text: $due).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            TextField(S.Cards.creditLimit, text: $limit).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            TextField(S.Cards.amountDue, text: $dueAmt).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            TextField("Card number (last 4)", text: $last4).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
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

                        Text("Settle from").font(.caption).foregroundColor(Color.text2)
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
                        Text(S.Cards.cardHolder).font(.subheadline).fontWeight(.bold).foregroundColor(.white)
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

private struct CoveredEmisSheet: View {
    let covered: [CoveredEmi]
    let onConfirm: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(S.Cards.emiCoveredTitle).font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text("This payment covers \(covered.count) instalment(s) charged to this card. Mark them paid?")
                .font(.subheadline).foregroundColor(Color.text2)
            ForEach(covered, id: \.emiNo) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EMI #\(c.emiNo)" + (c.lender.map { " · \($0)" } ?? "")).font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
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
