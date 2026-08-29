import SwiftUI
import Domain

/// Ported from apps/web/app/investments/page.tsx per
/// docs/mobile/screen-specs/investments.md, mirroring Android's
/// InvestmentsScreen.kt.
///
/// Drill-in is local `@State` (which group tile is expanded), not a pushed
/// `NavigationStack` destination -- it's just a filtered view of the same
/// list, matching web's own DrillIn being page-local state rather than a
/// route. Edit is inline within the holding row (web's own EditHolding).
///
/// The insights section (dividends-this-FY card, allocation donut, gain/loss
/// bars) and the two interactive panels below it are page.tsx's, in page.tsx's
/// order, and were absent from this port entirely until now. They render only
/// on the group grid, never inside a drill-in, because they describe the WHOLE
/// portfolio and web hides them the same way.
///
/// Every label resolves through `S.Investments`. The view model hands over
/// keys and numbers, never sentences -- see its HoldingUiModel comment.
struct InvestmentsView: View {
    @State private var viewModel = InvestmentsViewModel()
    @State private var drilledKey: String?
    @State private var showingAddSheet = false
    @State private var showingCreateAccountSheet = false

    private var drilledGroup: InvestmentsViewModel.GroupUiModel? {
        guard let drilledKey else { return nil }
        return viewModel.groups.first { $0.key == drilledKey }
    }

    var body: some View {
        SanvyaPage(drilledGroup.map { groupDisplayLabel($0.key) } ?? S.Translation.navInvestments) {
            Button(action: { showingAddSheet = true }) {
                Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
            }
        } content: {
            Group {
                if viewModel.invAccounts.isEmpty {
                    emptyAccountState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let drilledGroup {
                                ForEach(drilledGroup.holdings) { holding in
                                    HoldingRowView(
                                        holding: holding,
                                        onUpdate: { qty, avgCost, curVal, rate in
                                            Task { _ = await viewModel.updateHolding(id: holding.id, quantityText: qty, avgCostMajorText: avgCost, currentValueMajorText: curVal, annualRateText: rate, currency: holding.currency) }
                                        },
                                        onDelete: { viewModel.deleteHolding(holding.id) },
                                        onStopSip: { viewModel.stopSip(holding.id) }
                                    )
                                }
                                Button(S.Investments.addTo(name: groupDisplayLabel(drilledGroup.key))) { showingAddSheet = true }
                                    .foregroundColor(Color.accent)
                                    .fontWeight(.semibold)
                            } else {
                                PortfolioTotalCard(
                                    valueFormatted: viewModel.totalValueFormatted,
                                    costFormatted: viewModel.totalCostFormatted,
                                    gainFormatted: viewModel.totalGainFormatted,
                                    gainPositive: viewModel.totalGainPositive
                                )
                                if viewModel.groups.isEmpty {
                                    Text(S.Investments.noInvestments)
                                        .font(.subheadline)
                                        .foregroundColor(Color.text2)
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 24)
                                } else {
                                    SectionEyebrow(S.Investments.byExchangeScheme)
                                    ForEach(viewModel.groups) { group in
                                        GroupTileView(group: group) { drilledKey = group.key }
                                    }
                                    InsightsSection(viewModel: viewModel)
                                    DividendPanel(viewModel: viewModel)
                                    ProjectionPanel(viewModel: viewModel)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            // Drill-in is local state, not a route, so the shell cannot
            // infer it — the screen says so and the util row shows Back.
            // Not a toolbar button: a screen gets ONE back affordance and
            // it is the util row's (screen-specs/app-shell.md §7).
            .registerBack(drilledKey != nil) { drilledKey = nil }
        }
        .sanvyaFormPresentation(isPresented: $showingAddSheet) {
            AddHoldingView(initialGroupKey: drilledGroup?.key, viewModel: viewModel)
        }
        .sanvyaFormPresentation(isPresented: $showingCreateAccountSheet) {
            CreateAccountView()
        }
    }

    private var emptyAccountState: some View {
        VStack(spacing: 10) {
            Text("▲").font(.system(size: 26)).foregroundColor(Color.accent)
            Text(S.Investments.noInvAccountTitle).font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            // Web writes this sentence in three pieces so "Demat" can be
            // emphasised mid-sentence; the pieces are joined here rather than a
            // fourth key being invented for the whole line.
            Text(S.Investments.noInvAccountBodyPre + S.Investments.demat + S.Investments.noInvAccountBodyPost)
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
            // Without this the empty state was a dead end: nothing on the screen
            // could create the account it asks for. Web's own empty state links
            // to /accounts/new, so the CTA opens the same form rather than
            // bouncing the user to the Accounts tab to find it.
            Button(S.Investments.addInvAccount) { showingCreateAccountSheet = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
    }
}

// MARK: - label resolution

/// The display name of a group key.
///
/// Domain's `groupLabel()` returns web's English ("Mutual Funds", "Stocks
/// (other)") and is kept exactly as it is, because it is also the SORT key
/// that orders the tiles identically on all three platforms. Translating it
/// there would reorder the screen per language. So the English one sorts and
/// this one shows. An exchange group is its exchange CODE -- "NSE_IN" is a
/// proper noun, not a word.
func groupDisplayLabel(_ key: String) -> String {
    if key.hasPrefix("ex:") {
        let ex = String(key.dropFirst(3))
        return ex == "OTHER" ? S.Investments.groupTitleStocksOther : ex
    }
    switch String(key.dropFirst(4)) {
    case "stock": return S.Investments.groupTitleStock
    case "mf": return S.Investments.groupTitleMf
    case "sip": return S.Investments.groupTitleSip
    case "crypto": return S.Investments.groupTitleCrypto
    case "fd": return S.Investments.groupTitleFd
    case "other": return S.Investments.groupTitleOther
    default: return S.Investments.groupTitleFallback
    }
}

/// The display name of an asset class. Same split as `groupDisplayLabel`:
/// Domain keeps web's English for parity, the view shows the user's.
func assetClassDisplayLabel(_ key: String) -> String {
    switch key {
    case "stock": return S.Investments.assetClassStock
    case "mf": return S.Investments.assetClassMf
    case "sip": return S.Investments.assetClassSip
    case "crypto": return S.Investments.assetClassCrypto
    case "fd": return S.Investments.assetClassFd
    default: return S.Investments.assetClassOther
    }
}

/// "shares" / "units" / "coins". Nil in, nil out -- a fixed deposit has a
/// principal, not a countable unit.
func unitWordLabel(_ key: String?) -> String? {
    switch key {
    case "shares": return S.Investments.unitWordShares
    case "units": return S.Investments.unitWordUnits
    case "coins": return S.Investments.unitWordCoins
    default: return nil
    }
}

/// Localises a view-model failure. The failure crosses the boundary as a
/// value so that i18n stays in the view layer on both platforms.
func investmentFormMessage(_ error: InvestmentsViewModel.InvestmentFormError) -> String {
    switch error {
    case .quantity: return S.Investments.errQuantity
    case .name: return S.Investments.errName
    case .instrument: return S.Investments.errInstrument
    case .fundingAccount: return S.Investments.errFundingAccount
    case .overFunds(let account): return S.Investments.overFunds(account: account)
    case .sipAmount: return S.Investments.errSipAmount
    case .sipSource: return S.Investments.errSipSource
    case .noUser: return S.Investments.errNoUser
    case .addFailed: return S.Investments.errAddFailed
    case .saveFailed: return S.Investments.errSaveFailed
    case .holdingNotFound: return S.Investments.errHoldingNotFound
    case .invalidQuantity: return S.Investments.errInvalidQuantity
    }
}

/// The dot-separated meta line under a holding: class, exchange, FD rate and
/// maturity, then the live SIP amount -- web's order exactly.
///
/// Built here rather than in the view model because every piece of it is a
/// translated word. A `·` separator is punctuation, not copy.
func holdingMetaLine(_ h: InvestmentsViewModel.HoldingUiModel) -> String {
    var parts = [assetClassDisplayLabel(h.assetClassKey)]
    if let ex = h.exchange { parts.append(ex) }
    if let rate = h.annualRatePlain { parts.append(S.Investments.perAnnum(rate: rate)) }
    if let m = h.maturityDate { parts.append("\(S.Investments.matures) \(m)") }
    if let sip = h.sipAmountFormatted { parts.append("\(S.Investments.sipLine) \(sip)") }
    return parts.joined(separator: " · ")
}

// MARK: - pieces

/// Web's `.eyebrow` — the small caps label above a section.
private struct SectionEyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack {
            Text(text.uppercased()).font(.caption2).fontWeight(.semibold).foregroundColor(Color.text3)
            Spacer()
        }
    }
}

private struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.surface)
            .cornerRadius(18)
    }
}

private struct StatView: View {
    let label: String
    let value: String
    var color: Color = Color.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(Color.text2)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PortfolioTotalCard: View {
    let valueFormatted: String
    let costFormatted: String
    let gainFormatted: String
    let gainPositive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(S.Investments.currentValue).font(.caption).fontWeight(.medium).foregroundColor(Color.text2)
            Text(valueFormatted).font(.system(size: 30, weight: .bold)).foregroundColor(Color.text)
            // Web's grand total puts Invested next to Current value: without the
            // cost there is no way to read what the gain figure is a gain ON.
            // Empty only until the first rebuild lands.
            if !costFormatted.isEmpty {
                Text(S.Investments.investedLabel(amount: costFormatted)).font(.caption).foregroundColor(Color.text2)
            }
            Text(gainFormatted).font(.caption).fontWeight(.semibold).foregroundColor(gainPositive ? Color.positive : Color.negative)
            Text(S.Investments.syncNote).font(.caption2).foregroundColor(Color.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface)
        .cornerRadius(18)
    }
}

private struct GroupTileView: View {
    let group: InvestmentsViewModel.GroupUiModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(groupDisplayLabel(group.key)).font(.subheadline).fontWeight(.bold).foregroundColor(Color.text)
                        Text(S.Investments.holdingsCount(count: group.holdingsCount)).font(.caption).foregroundColor(Color.text2)
                    }
                    Spacer()
                    Text(group.gainPctFormatted).font(.caption).fontWeight(.semibold).foregroundColor(group.gainPositive ? Color.positive : Color.negative)
                }
                HStack {
                    Text(group.valueFormatted).font(.body).fontWeight(.bold).foregroundColor(Color.text)
                    Spacer()
                    Text(group.gainFormatted).font(.caption).fontWeight(.semibold).foregroundColor(group.gainPositive ? Color.positive : Color.negative)
                }
                HStack {
                    Text(S.Investments.investedLabel(amount: group.costFormatted)).font(.caption).foregroundColor(Color.text2)
                    Spacer()
                }
            }
            .padding(18)
            .background(Color.surface)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

/// Web's Insights band: the dividends-this-financial-year card, the allocation
/// donut and the gain/loss-by-group bars, in that order. Three side-by-side
/// cards on a desktop grid; three stacked cards on a phone.
private struct InsightsSection: View {
    let viewModel: InvestmentsViewModel

    var body: some View {
        SectionEyebrow(S.Investments.insights)
        SectionCard {
            Text(S.Investments.dividendsEarned(fy: S.Investments.fyLabel(start: String(viewModel.currentFy.startYear), end: viewModel.currentFy.endYearShort)))
                .font(.caption).foregroundColor(Color.text2)
            Text(viewModel.dividendFyFormatted).font(.system(size: 28, weight: .bold)).foregroundColor(Color.positive)
            Text(S.Investments.dividendsNote).font(.caption2).foregroundColor(Color.text3)
        }
        SectionCard {
            SectionEyebrow(S.Investments.allocation)
            AllocationDonut(
                slices: viewModel.allocation.map {
                    DonutSlice(label: groupDisplayLabel($0.groupKey), valueMajor: $0.valueMajor, amountFormatted: $0.valueFormatted, sharePct: $0.sharePct)
                },
                centerLabel: S.Investments.total,
                centerValue: viewModel.totalValueFormatted,
                emptyLabel: S.Investments.allocationEmpty
            )
        }
        SectionCard {
            SectionEyebrow(S.Investments.gainLossByGroup)
            SignedBarsChart(
                bars: viewModel.gainByGroup.map {
                    SignedBar(label: groupDisplayLabel($0.groupKey), valueMajor: $0.gainMajor, amountFormatted: $0.gainFormatted, positive: $0.positive)
                },
                emptyLabel: S.Investments.gainsEmpty
            )
        }
    }
}

private let dividendPeriods: [DividendPeriod] = [.week, .month, .quarter, .year, .all]

private func dividendPeriodLabel(_ p: DividendPeriod) -> String {
    switch p {
    case .week: return S.Investments.divPeriodWeek
    case .month: return S.Investments.divPeriodMonth
    case .quarter: return S.Investments.divPeriodQuarter
    case .year: return S.Investments.divPeriodYear
    case .all: return S.Investments.divPeriodAll
    }
}

/// Web's DividendPanel: period chips over a bar chart of income by bucket,
/// with trailing / forward / all-time totals above it.
///
/// Self-hides with no holdings, exactly as web's does -- a dividend chart on
/// an empty portfolio is a chart of nothing.
private struct DividendPanel: View {
    @Bindable var viewModel: InvestmentsViewModel

    var body: some View {
        let panel = viewModel.dividendPanel
        if panel.hasHoldings {
            SectionCard {
                Text(S.Investments.dividendIncome).font(.headline).foregroundColor(Color.text)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(dividendPeriods.enumerated()), id: \.offset) { _, p in
                            SanvyaChip(dividendPeriodLabel(p), isActive: p == viewModel.dividendPeriod) {
                                viewModel.dividendPeriod = p
                            }
                        }
                    }
                }
                HStack(spacing: 12) {
                    StatView(label: S.Investments.last12Months, value: panel.trailing12Formatted)
                    StatView(label: S.Investments.next12Months, value: panel.upcoming12Formatted, color: Color.accent)
                    StatView(label: S.Investments.allTime, value: panel.totalFormatted)
                }
                if panel.hasEvents {
                    SanvyaBarsChart(
                        // Upcoming buckets are the warning tone, matching web's
                        // amber bars -- the chart mixes money already received
                        // with money merely scheduled, and nothing else on the
                        // card says which is which.
                        series: panel.buckets.map { SeriesPoint($0.label, $0.valueMajor, $0.upcoming ? "warning" : "positive") },
                        unit: nil,
                        horizontal: false,
                        accent: Color.accent
                    )
                    .frame(height: 180)
                } else {
                    Text(S.Investments.noDividendData).font(.caption).foregroundColor(Color.text2)
                }
                Text(S.Investments.dividendFootnote).font(.caption2).foregroundColor(Color.text3)
            }
        }
    }
}

/// Web's ProjectionPanel: the compounded curve, with the three assumptions and
/// the reinvest switch under it.
///
/// The maths is Domain's `projectPortfolio` and is vector-pinned; the only
/// thing here is the controls. Self-hides with no holdings, like web's.
///
/// Note the current value it starts from is the portfolio's book value, not a
/// live one -- this port has no quote source, so the same simplification that
/// `valuation()` documents applies to the projection's opening balance.
private struct ProjectionPanel: View {
    @Bindable var viewModel: InvestmentsViewModel

    var body: some View {
        let panel = viewModel.projectionPanel
        if panel.hasHoldings {
            SectionCard {
                HStack(alignment: .lastTextBaseline) {
                    Text(S.Investments.projectedWealth).font(.headline).foregroundColor(Color.text)
                    Spacer()
                    Text(S.Investments.inYears(years: String(viewModel.projectionYears))).font(.caption).foregroundColor(Color.text2)
                }
                HStack(spacing: 12) {
                    StatView(label: S.Investments.projectedValue, value: panel.endValueFormatted, color: Color.accent)
                    StatView(label: S.Investments.youPutIn, value: panel.contributedFormatted)
                    StatView(label: S.Investments.growthPlusDividends, value: panel.growthFormatted, color: Color.positive)
                }
                SanvyaAreaChart(
                    // The area chart draws no axis labels, so the point's own
                    // year index is label enough to keep the series honest.
                    series: panel.series.enumerated().map { SeriesPoint(String($0.offset), $0.element) },
                    accent: Color.accent
                )
                .frame(height: 180)
                AssumptionSlider(
                    label: S.Investments.assumedGrowth,
                    display: String(format: "%.1f%%", viewModel.projectionGrowthPct),
                    value: $viewModel.projectionGrowthPct,
                    range: 0...15,
                    step: 0.5
                )
                AssumptionSlider(
                    label: S.Investments.monthlyContribution(cur: baseCurrencyNow()),
                    display: String(format: "%.0f", viewModel.projectionMonthlyMajor),
                    value: $viewModel.projectionMonthlyMajor,
                    range: 0...5000,
                    step: 50
                )
                AssumptionSlider(
                    label: S.Investments.horizon,
                    display: String(viewModel.projectionYears),
                    value: Binding(
                        get: { Double(viewModel.projectionYears) },
                        set: { viewModel.projectionYears = Int($0) }
                    ),
                    range: 1...40,
                    step: 1
                )
                Toggle(isOn: $viewModel.projectionReinvest) {
                    HStack(spacing: 6) {
                        Text(S.Investments.reinvestDividends).font(.subheadline).foregroundColor(Color.text)
                        if panel.hasYield {
                            Text(S.Investments.reinvestYield(pct: panel.yieldPctFormatted)).font(.caption).foregroundColor(Color.text2)
                        }
                    }
                }
                .tint(Color.accent)
                Text(S.Investments.projectionFootnote).font(.caption2).foregroundColor(Color.text3)
            }
        }
    }
}

private struct AssumptionSlider: View {
    let label: String
    let display: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundColor(Color.text2)
                Spacer()
                Text(display).font(.caption).fontWeight(.semibold).foregroundColor(Color.text)
            }
            Slider(value: $value, in: range, step: step).tint(Color.accent)
        }
    }
}

/// "Zerodha-style" holding row, matching web's HoldingTile + Android's
/// HoldingTile: left side is label + off-list "untracked" chip + qty;
/// right side is value + gain; bottom row is asset-class meta + FD
/// extras. Tapping the edit icon expands an inline edit form in place.
private struct HoldingRowView: View {
    let holding: InvestmentsViewModel.HoldingUiModel
    let onUpdate: (String, String, String, String) -> Void
    let onDelete: () -> Void
    let onStopSip: () -> Void

    @State private var editing = false
    @State private var showDeleteConfirm = false
    @State private var showStopSipConfirm = false
    @State private var quantityText = ""
    @State private var avgCostText = ""
    @State private var currentValueText = ""
    @State private var annualRateText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(holding.label).font(.body).fontWeight(.bold).foregroundColor(Color.text)
                        if holding.offList {
                            Text(S.Investments.untracked).font(.caption2).foregroundColor(Color.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentGhost).cornerRadius(8)
                        }
                    }
                    if let unit = unitWordLabel(holding.unitWordKey) {
                        Text("\(holding.quantityPlain) \(unit)").font(.caption).foregroundColor(Color.text2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(holding.valueFormatted).font(.body).fontWeight(.bold).foregroundColor(Color.text)
                    if holding.hasCostBasis {
                        Text(holding.gainFormatted).font(.caption).fontWeight(.semibold).foregroundColor(holding.gainPositive ? Color.positive : Color.negative)
                    }
                }
            }
            HStack {
                // A running SIP is a standing debit on a real account and has no
                // other home in the app -- recurring savings are not browsable
                // under Recurring -- so it has to be legible and stoppable right
                // here, exactly as web's HoldingTile does it.
                Text(holdingMetaLine(holding))
                    .font(.caption2).foregroundColor(Color.text2)
                Spacer()
                if holding.sipOn {
                    Button(S.Investments.stopSip) { showStopSipConfirm = true }
                        .font(.caption2)
                        .foregroundColor(Color.warning)
                        // Hung off the button, not the tile: two `.alert`
                        // modifiers on the SAME view is the case where SwiftUI
                        // only honours one of them, and the tile already owns
                        // the remove confirmation.
                        .alert(S.Investments.stopSipTitle, isPresented: $showStopSipConfirm) {
                            Button(S.Investments.stopSip, role: .destructive, action: onStopSip)
                            Button(S.Investments.cancel, role: .cancel) {}
                        } message: {
                            Text(S.Investments.stopSipMsg)
                        }
                }
                Button {
                    if !editing {
                        quantityText = holding.quantityPlain
                        avgCostText = holding.rawAvgCostMajor
                        currentValueText = holding.rawCurrentValueMajor
                        annualRateText = holding.rawAnnualRate
                    }
                    editing.toggle()
                } label: {
                    Image(systemName: "pencil").font(.caption).foregroundColor(Color.text2)
                }
                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash").font(.caption).foregroundColor(Color.negative)
                }
            }
            if editing {
                VStack(spacing: 8) {
                    TextField(unitWordLabel(holding.unitWordKey) ?? S.Investments.quantity, text: $quantityText)
                        .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    TextField(S.Investments.avgCost(cur: holding.currency), text: $avgCostText)
                        .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    // Web's EditHolding shows the current-value and rate fields
                    // only for an UNPRICED holding: a listed one's value comes
                    // from the market, so a field for it would be a lie.
                    if !holding.isListedClass {
                        TextField(S.Investments.currentValueCur(cur: holding.currency), text: $currentValueText)
                            .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                        if holding.assetClassKey == "fd" {
                            TextField(S.Investments.interestPa, text: $annualRateText)
                                .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                        }
                    }
                    HStack {
                        Button(S.Investments.cancel) { editing = false }
                        Spacer()
                        Button(S.Investments.save) {
                            onUpdate(quantityText, avgCostText, currentValueText, annualRateText)
                            editing = false
                        }.fontWeight(.semibold)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .alert(S.Investments.removeTitle, isPresented: $showDeleteConfirm) {
            Button(S.Investments.remove, role: .destructive, action: onDelete)
            Button(S.Investments.cancel, role: .cancel) {}
        } message: {
            Text(S.Investments.removeMsg(label: holding.label))
        }
    }
}

#Preview {
    InvestmentsView()
}
