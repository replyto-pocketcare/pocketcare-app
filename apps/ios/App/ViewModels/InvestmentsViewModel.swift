import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

/// Ported from apps/web/app/investments/page.tsx per
/// docs/mobile/screen-specs/investments.md, mirroring Android's
/// InvestmentsViewModel.kt field for field.
///
/// This pass added the five things page.tsx has and the port did not: the SIP
/// collection and its recurring-transfer write (mobile could not create a SIP
/// at all before it), the instrument-catalog picker (every mobile holding was
/// `off_list`), the allocation donut and gain/loss bars, the
/// dividends-this-financial-year card, and the dividend + projection panels.
///
/// Still deferred, and deliberately: live market quotes (so `valuation()` is
/// called with no quote and listed holdings value at `current_value ?? cost`,
/// exactly as an off-list holding does on web), the 63k-row daily instrument
/// download behind the seed catalog, and CSV/XLSX broker import.
@Observable
@MainActor
public final class InvestmentsViewModel {
    @ObservationIgnored
    @Injected(\.investmentsRepository) private var investmentsRepository

    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    @ObservationIgnored
    @Injected(\.supabaseClient) private var supabaseClient

    public struct InvAccountOption: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let currency: String
    }

    public struct FundingAccountOption: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let currency: String
        public let balanceFormatted: String
        public let balanceMinor: Int64
    }

    /// A holding row, reduced to the pieces the screen needs -- and no further.
    ///
    /// The display STRINGS that used to live here (`metaLine`, `quantityLine`,
    /// `fdExtra`) were built out of English literals and the Domain enum's
    /// English `label`, so the holding row was the one part of the screen no
    /// locale could reach. What crosses the boundary now is the asset class
    /// KEY, the exchange code and the raw numbers; the view joins them with
    /// `S.Investments`.
    public struct HoldingUiModel: Identifiable, Equatable {
        public let id: String
        public let label: String
        public let assetClassKey: String
        public let exchange: String?
        /// Plain quantity, no unit word -- the view appends the localised one.
        public let quantityPlain: String
        /// "shares" / "units" / "coins", or nil for a lump asset with no unit.
        public let unitWordKey: String?
        public let valueFormatted: String
        public let costFormatted: String
        public let gainFormatted: String
        public let gainPositive: Bool
        public let hasCostBasis: Bool
        public let offList: Bool
        public let isListedClass: Bool
        /// FD only: the rate as a plain number, for `investments:perAnnum`.
        public let annualRatePlain: String?
        /// FD only: `yyyy-MM-dd`, for `investments:matures`.
        public let maturityDate: String?
        public let rawQuantity: Double
        public let rawAvgCostMajor: String
        public let rawCurrentValueMajor: String
        public let rawAnnualRate: String
        public let currency: String
        /// True only while the holding still has a live SIP: `plannedId` alone
        /// can point at a recurring row that was already stopped, so web gates
        /// on `planned_id && sip_amount > 0` and so does this.
        public let sipOn: Bool
        public let sipAmountFormatted: String?
    }

    public struct GroupUiModel: Identifiable, Equatable {
        public var id: String { key }
        public let key: String
        public let holdingsCount: Int
        public let valueFormatted: String
        public let costFormatted: String
        public let gainFormatted: String
        public let gainPositive: Bool
        public let gainPctFormatted: String
        public let holdings: [HoldingUiModel]
    }

    /// One donut slice. `valueMajor` is a plottable Double; the formatted
    /// string is what the legend shows, so no view divides anything by
    /// anything.
    public struct AllocationSliceUi: Identifiable, Equatable {
        public var id: String { groupKey }
        public let groupKey: String
        public let valueMajor: Double
        public let sharePct: Double
        public let valueFormatted: String
    }

    /// One signed gain/loss bar.
    public struct GainBarUi: Identifiable, Equatable {
        public var id: String { groupKey }
        public let groupKey: String
        public let gainMajor: Double
        public let gainFormatted: String
        public let positive: Bool
    }

    public struct DividendBucketUi: Identifiable, Equatable {
        public var id: String { label }
        public let label: String
        public let valueMajor: Double
        public let upcoming: Bool
    }

    public struct DividendPanelUi: Equatable {
        public var hasHoldings = false
        public var hasEvents = false
        public var buckets: [DividendBucketUi] = []
        public var trailing12Formatted = ""
        public var upcoming12Formatted = ""
        public var totalFormatted = ""
    }

    public struct ProjectionPanelUi: Equatable {
        public var hasHoldings = false
        public var series: [Double] = []
        public var endValueFormatted = ""
        public var contributedFormatted = ""
        public var growthFormatted = ""
        /// The reinvestment yield as a percentage, for
        /// `investments:reinvestYield`.
        public var yieldPctFormatted = ""
        public var hasYield = false
    }

    /// Why the add/edit failures are an enum and not a String: the previous
    /// version returned ready-made English sentences, which is why this
    /// screen's error line was the only text on it that never translated. The
    /// failure crosses the boundary and the view resolves it, mirroring
    /// Android (where a view model additionally must not hold a `Resources`).
    public enum InvestmentFormError: Equatable {
        case quantity, name, instrument, fundingAccount, overFunds(String)
        case sipAmount, sipSource, noUser, addFailed, saveFailed, holdingNotFound, invalidQuantity
    }

    public var groups: [GroupUiModel] = []
    public var totalValueFormatted: String = ""
    /// Web's grand-total row shows Current value / Invested / Gain-loss side by
    /// side; the cost figure is what makes the gain readable at all.
    public var totalCostFormatted: String = ""
    public var totalGainFormatted: String = ""
    public var totalGainPositive: Bool = true
    public var invAccounts: [InvAccountOption] = []
    public var fundingAccounts: [FundingAccountOption] = []
    public var allocation: [AllocationSliceUi] = []
    public var gainByGroup: [GainBarUi] = []
    public var dividendFyFormatted: String = ""
    public var currentFy: FinancialYear = financialYear(IsoDay.today())

    // MARK: - panel controls (UI state, not database state)

    public var dividendPeriod: DividendPeriod = .month

    /// Web's defaults: 7% a year, nothing extra put in, fifteen years,
    /// dividends reinvested.
    public var projectionGrowthPct: Double = 7
    public var projectionMonthlyMajor: Double = 0
    public var projectionYears: Int = 15
    public var projectionReinvest: Bool = true

    // MARK: - instrument catalog

    /// The exchange the picker is scoped to, or nil for all of them.
    public var instrumentExchange: String?
    public var instrumentQuery: String = ""

    /// Every exchange the bundled catalog knows about. Static today -- it
    /// becomes reactive for free the day a downloaded catalog replaces the
    /// seed, because `knownExchanges` reads whatever list it is handed.
    public let catalogExchanges: [String] = knownExchanges(seedInstruments)

    public var instrumentResults: [Instrument] {
        searchInstruments(seedInstruments, query: instrumentQuery, exchange: instrumentExchange)
    }

    // MARK: - derived panels

    /// Everything the panels derive from, recomputed only when the DATABASE
    /// changes -- the period chips and the projection sliders read this rather
    /// than re-running the queries behind it.
    private var holdingsCount = 0
    private var dividendEvents: [DivEvent] = []
    private var totalValueMinor: Int64 = 0

    /// Computed rather than stored: `@Observable` tracks the control
    /// properties these read, so moving a slider re-renders exactly the panel
    /// that depends on it and nothing else. The loop is 180 multiplications at
    /// its longest, which is cheaper than the diff that publishing it would
    /// cost.
    public var dividendPanel: DividendPanelUi {
        let base = baseCurrencyNow()
        let scale = majorScale(base)
        let summary = dividendSummary(dividendEvents)
        var ui = DividendPanelUi()
        ui.hasHoldings = holdingsCount > 0
        ui.hasEvents = !dividendEvents.isEmpty
        // The bucket value is ALREADY Int64 minor units, so this is the one
        // conversion to a plottable Double and it goes through majorScale -- a
        // literal hundred here would flatten every JPY portfolio.
        ui.buckets = bucketize(dividendEvents, dividendPeriod).map {
            DividendBucketUi(label: $0.label, valueMajor: Double($0.value) / scale, upcoming: $0.upcoming)
        }
        ui.trailing12Formatted = formatMoney(summary.trailing12, base)
        ui.upcoming12Formatted = formatMoney(summary.upcoming12, base)
        ui.totalFormatted = formatMoney(summary.total, base)
        return ui
    }

    public var projectionPanel: ProjectionPanelUi {
        let base = baseCurrencyNow()
        let scale = majorScale(base)
        let summary = dividendSummary(dividendEvents)
        // Web's own fallback: use the last twelve months of income when there
        // is any, else the next twelve months' scheduled income.
        let annual = summary.trailing12 > 0 ? summary.trailing12 : summary.upcoming12
        let yieldRate = dividendYieldRate(annual, totalValueMinor)
        let projection = projectPortfolio(
            currentValueBase: totalValueMinor,
            growthPctPerYear: projectionGrowthPct,
            monthlyContributionBase: fromMajor(projectionMonthlyMajor, base).amount,
            years: projectionYears,
            reinvestDividends: projectionReinvest,
            dividendYieldRate: yieldRate
        )
        var ui = ProjectionPanelUi()
        ui.hasHoldings = holdingsCount > 0
        ui.series = projection.points.map { Double($0.valueBase) / scale }
        ui.endValueFormatted = formatMoney(projection.endValueBase, base)
        ui.contributedFormatted = formatMoney(projection.contributedBase, base)
        ui.growthFormatted = formatMoney(projection.growthBase, base)
        ui.yieldPctFormatted = String(format: "%.1f", yieldRate * 100)
        ui.hasYield = yieldRate > 0
        return ui
    }

    private var latestHoldings: [Holding] = []
    private var currentUserId: String?

    public init() {
        Task { await startObserving() }
    }

    private func startObserving() async {
        guard let userId = try? await supabaseClient.auth.session.user.id.canonicalString else { return }
        currentUserId = userId
        do {
            let stream = try await investmentsRepository.watchHoldings(userId: userId)
            for try await dbHoldings in stream {
                latestHoldings = dbHoldings
                await rebuild(holdings: dbHoldings)
            }
        } catch {
            print("Failed to observe investments: \(error)")
        }
    }

    /// Re-fetches account balances/rates/dividends (one-shot on this platform,
    /// see LedgerRepository.swift) and rebuilds the grouped view. Called each
    /// time the holdings stream emits, and again explicitly after any write
    /// (add/update/delete) so funding-account balances reflect the
    /// just-posted transaction immediately.
    private func rebuild(holdings: [Holding]) async {
        let balances = (try? await ledgerRepository.accountBalances()) ?? []
        // `@Sendable` on the fallback is load-bearing: `RateLookup` is a
        // `@Sendable` typealias, and a bare closure literal is not -- Swift 6
        // rejects the conversion with "may introduce data races". Same trap
        // `InsightsViewModel` documents at its own `noRates`.
        let rates = (try? await ledgerRepository.rates()) ?? { @Sendable _, _ in 1.0 }
        let dividends = (try? await investmentsRepository.dividendsOnce()) ?? []
        let base = baseCurrencyNow()

        invAccounts = balances
            .filter { FormOptions.isInvestmentAccount($0.account.type) }
            .map { InvAccountOption(id: $0.account.id, name: $0.account.name, currency: $0.account.currency) }

        fundingAccounts = balances
            .filter { !FormOptions.isInvestmentAccount($0.account.type) }
            .map {
                FundingAccountOption(
                    id: $0.account.id, name: $0.account.name, currency: $0.account.currency,
                    balanceFormatted: formatMoney($0.balance.amount, $0.account.currency),
                    balanceMinor: $0.balance.amount
                )
            }

        let rows = holdings.map { $0.toHoldingRow() }
        let groupsResult = buildGroups(rows) { amount, currency in
            if currency == base { return amount }
            return (try? convert(money(amount, currency), to: base, rate: rates(currency, base)).amount) ?? amount
        }
        var byGroupKey: [String: [Holding]] = [:]
        for h in holdings { byGroupKey[groupKeyOf(h.toHoldingRow()), default: []].append(h) }

        groups = groupsResult.map { g in
            GroupUiModel(
                key: g.key, holdingsCount: g.holdings.count,
                valueFormatted: formatMoney(g.value, base),
                costFormatted: formatMoney(g.cost, base),
                gainFormatted: signedGain(g.gain, g.gainPct, base),
                gainPositive: g.gain >= 0,
                gainPctFormatted: formatPct(g.gainPct),
                holdings: (byGroupKey[g.key] ?? []).map { self.toUiModel($0) }
            )
        }

        let totals = portfolioTotals(groupsResult)
        totalValueFormatted = formatMoney(totals.value, base)
        totalCostFormatted = formatMoney(totals.cost, base)
        totalGainPositive = totals.gain >= 0
        totalGainFormatted = signedGain(totals.gain, totals.gainPct, base)

        let scale = majorScale(base)
        allocation = allocationSlices(groupsResult).map {
            AllocationSliceUi(
                groupKey: $0.key, valueMajor: Double($0.valueBase) / scale, sharePct: $0.sharePct,
                valueFormatted: formatMoney($0.valueBase, base)
            )
        }
        gainByGroup = gainBars(groupsResult).map {
            GainBarUi(
                groupKey: $0.key, gainMajor: Double($0.gainBase) / scale,
                gainFormatted: formatMoney($0.gainBase, base), positive: $0.gainBase >= 0
            )
        }

        // Dividends: only listed, catalog-matched holdings can be matched to a
        // `market_dividends` row at all -- an off-list holding has no symbol
        // the market data knows, so counting it would silently attribute
        // someone else's dividend to it.
        let lite = holdings
            .filter { isListed(assetClassOf($0.toHoldingRow())) && !$0.offList }
            .map { HoldingLite(symbol: $0.symbol, exchange: $0.exchange, quantity: $0.quantity, currency: $0.currency) }
        let divRows = dividends.map {
            DivRow(symbol: $0.symbol, exchange: $0.exchange, exDate: $0.exDate, payDate: $0.payDate, amount: $0.amount, currency: $0.currency)
        }
        let events = computeDividendEvents(lite, divRows, rates, base)
        let today = IsoDay.today()
        currentFy = financialYear(today)
        dividendFyFormatted = formatMoney(dividendsThisFy(events, today), base)

        holdingsCount = holdings.count
        dividendEvents = events
        totalValueMinor = totals.value
    }

    /// "+₹1,200 (+4.5%)" / "-₹300 (-2.0%)" -- web's own grand-total shape.
    private func signedGain(_ gain: Int64, _ gainPct: Double, _ currency: String) -> String {
        "\(gain >= 0 ? "+" : "")\(formatMoney(gain, currency)) (\(formatPct(gainPct)))"
    }

    private func formatPct(_ pct: Double) -> String {
        String(format: "%+.1f%%", pct)
    }

    /// "10", not "10.0"; "10.5" stays "10.5". Quantities are fractional for
    /// mutual-fund units and whole for shares, and a share count printed with
    /// a decimal point reads like a rounding error.
    private func plainNumber(_ v: Double) -> String {
        v.isFinite && v == v.rounded() ? String(Int64(v)) : String(v)
    }

    private func toUiModel(_ h: Holding) -> HoldingUiModel {
        let row = h.toHoldingRow()
        // Web's `sipOn`: a SIP is running only while it still has an amount AND
        // its recurring item is alive.
        let sipLive = h.plannedId != nil && (h.sipAmount ?? 0) > 0
        let v = valuation(row)
        let cls = assetClassOf(row)
        return HoldingUiModel(
            id: h.id,
            label: holdingLabel(row),
            assetClassKey: cls.rawValue,
            exchange: (h.exchange?.isEmpty == false) ? h.exchange : nil,
            quantityPlain: plainNumber(h.quantity),
            unitWordKey: cls.unitWord.isEmpty ? nil : cls.unitWord,
            valueFormatted: formatMoney(v.value, h.currency),
            costFormatted: formatMoney(v.cost, h.currency),
            // Web's HoldingTile prints the percentage next to the amount, to
            // two places rather than the group tile's one -- a single holding
            // moving 0.4% is a different fact from a whole group doing it.
            gainFormatted: "\(v.gain >= 0 ? "+" : "")\(formatMoney(v.gain, h.currency)) (\(String(format: "%+.2f%%", v.gainPct)))",
            gainPositive: v.gain >= 0,
            // Web hides the gain line entirely when there is neither a cost
            // basis nor a current value: "+₹0" on a holding nobody has priced
            // reads as "flat", which is a claim the data does not support.
            hasCostBasis: h.avgCost != nil || h.currentValue != nil,
            offList: h.offList,
            isListedClass: isListed(cls),
            annualRatePlain: cls == .fd ? h.annualRate.map { String(format: "%.1f", $0) } : nil,
            maturityDate: cls == .fd ? h.maturityDate.map { String($0.prefix(10)) } : nil,
            rawQuantity: h.quantity,
            rawAvgCostMajor: h.avgCost.map { formatMajorPlain($0, currency: h.currency) } ?? "",
            rawCurrentValueMajor: h.currentValue.map { formatMajorPlain($0, currency: h.currency) } ?? "",
            rawAnnualRate: h.annualRate.map { plainNumber($0) } ?? "",
            currency: h.currency,
            sipOn: sipLive,
            sipAmountFormatted: sipLive ? formatMoney(h.sipAmount ?? 0, h.currency) : nil
        )
    }

    /// Add a holding -- web's AddInvestmentDialog.submit(), including its SIP
    /// branch. Returns nil on success, or the failure for the view to
    /// localise.
    public func addHolding(
        investmentAccountId: String, assetClass: AssetClass, instrument: Instrument?, name: String,
        exchange: String?, quantityText: String, avgCostMajorText: String, currentValueMajorText: String,
        annualRateText: String, maturityDate: String?, currency: String,
        fundingExisting: Bool, fundingSourceAccountId: String?,
        sipAmountMajorText: String = "", sipFrequency: String = "monthly",
        sipStartDate: String = "", sipDayText: String = "", sipSourceAccountId: String? = nil
    ) async -> InvestmentFormError? {
        let isSip = assetClass == .sip
        let isLump = assetClass == .fd
        // Web's SIP branch collects an amount, not units: quantity and cost are
        // not asked for and the holding starts at zero units, because the units
        // only exist once instalments have actually posted.
        let qty: Double = isSip ? 0 : (isLump ? 1 : (Double(quantityText) ?? 0))
        if !isSip && !isLump && qty <= 0 { return .quantity }

        // A catalog pick supplies symbol, exchange and trading currency; free
        // text supplies only a name and is written off_list.
        let fromCatalog = instrument != nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromCatalog && trimmedName.isEmpty { return .name }

        let avgCostMinor: Int64? = isSip ? nil : Double(avgCostMajorText).map { fromMajor($0, currency).amount }
        let currentValueMinor: Int64? = (!isSip && !isListed(assetClass))
            ? Double(currentValueMajorText).map { fromMajor($0, currency).amount }
            : nil
        let annualRate = assetClass == .fd ? Double(annualRateText) : nil

        var sip: SipSetup?
        if isSip {
            let amount = Double(sipAmountMajorText).map { fromMajor($0, currency).amount } ?? 0
            if amount <= 0 { return .sipAmount }
            guard let sipSource = sipSourceAccountId, !sipSource.isEmpty else { return .sipSource }
            let start = sipStartDate.isEmpty ? IsoDay.today() : sipStartDate
            sip = SipSetup(
                amount: amount,
                frequency: sipFrequency,
                // Web sends the start date as the first due date too: the
                // engine posts from there forward, so a SIP started last month
                // catches up rather than silently skipping its first month.
                firstDue: start,
                sourceAccountId: sipSource,
                startDate: start,
                day: clampSipDay(Int(sipDayText) ?? 0)
            )
        } else {
            if !fundingExisting && (fundingSourceAccountId?.isEmpty ?? true) { return .fundingAccount }
            if !fundingExisting {
                let costTotal = Int64((Double(avgCostMinor ?? 0) * qty).rounded())
                if let source = fundingAccounts.first(where: { $0.id == fundingSourceAccountId }), costTotal > source.balanceMinor {
                    return .overFunds(source.name)
                }
            }
        }

        guard let userId = currentUserId else { return .noUser }
        let funding: HoldingFunding = (!isSip && !fundingExisting)
            ? .new(sourceAccountId: fundingSourceAccountId ?? "")
            : .existing
        do {
            try await investmentsRepository.addHolding(
                userId: userId,
                input: AddHoldingInput(
                    investmentAccountId: investmentAccountId,
                    assetClass: assetClass.rawValue,
                    symbol: instrument?.symbol ?? "",
                    exchange: instrument?.exchange ?? (assetClass == .stock ? exchange : nil),
                    name: instrument?.symbol ?? trimmedName,
                    quantity: qty,
                    avgCost: avgCostMinor,
                    currency: currency,
                    currentValue: currentValueMinor,
                    annualRate: annualRate,
                    maturityDate: assetClass == .fd ? ((maturityDate?.isEmpty ?? true) ? nil : maturityDate) : nil,
                    // The whole point of the picker: a catalog-matched holding
                    // is ON the list, so it can be priced and matched to a
                    // dividend row. Before it existed every mobile holding was
                    // written off_list = 1.
                    offList: !fromCatalog,
                    autoFetch: fromCatalog,
                    // A SIP tracks the units already bought as already-owned;
                    // its money movement IS the recurring transfer, so it never
                    // takes the existing-vs-new funding branch.
                    funding: funding,
                    sip: sip
                )
            )
            await rebuild(holdings: latestHoldings)
            return nil
        } catch {
            print("Failed to add holding: \(error)")
            return .addFailed
        }
    }

    /// Matches web's EditHolding.save(): quantity/avg-cost/current-value/
    /// annual-rate only.
    public func updateHolding(
        id: String, quantityText: String, avgCostMajorText: String,
        currentValueMajorText: String, annualRateText: String, currency: String
    ) async -> InvestmentFormError? {
        guard let holding = latestHoldings.first(where: { $0.id == id }) else { return .holdingNotFound }
        let cls = AssetClass.fromKey(holding.assetClass ?? holding.instrumentType)
        let isLump = cls == .fd
        guard let qty = isLump ? 1.0 : Double(quantityText) else { return .invalidQuantity }
        let avgCostMinor = Double(avgCostMajorText).map { fromMajor($0, currency).amount }
        let currentValueMinor = Double(currentValueMajorText).map { fromMajor($0, currency).amount }
        let annualRate = Double(annualRateText)
        do {
            try await investmentsRepository.updateHolding(id: id, quantity: qty, avgCost: avgCostMinor, currentValue: currentValueMinor, annualRate: annualRate)
            await rebuild(holdings: latestHoldings)
            return nil
        } catch {
            print("Failed to save holding: \(error)")
            return .saveFailed
        }
    }

    /// Web's remove(): kills the SIP with the holding, or it keeps debiting
    /// forever for an investment that no longer exists.
    public func deleteHolding(_ id: String) {
        Task {
            do {
                try await investmentsRepository.deleteHolding(id: id, plannedId: latestHoldings.first(where: { $0.id == id })?.plannedId)
                await rebuild(holdings: latestHoldings)
            } catch {
                print("Failed to delete holding: \(error)")
            }
        }
    }

    /// Web's Stop SIP chip: cancel the recurring item, then clear the holding's
    /// own SIP fields so nothing still reads as running. The holding itself
    /// stays -- the units already bought are still owned.
    public func stopSip(_ id: String) {
        Task {
            do {
                try await investmentsRepository.stopSipForHolding(plannedId: latestHoldings.first(where: { $0.id == id })?.plannedId)
                try await investmentsRepository.clearSipFields(id: id)
                await rebuild(holdings: latestHoldings)
            } catch {
                print("Failed to stop SIP: \(error)")
            }
        }
    }
}

private extension Holding {
    func toHoldingRow() -> HoldingRow {
        HoldingRow(
            id: id, accountId: accountId, symbol: symbol, exchange: exchange, quantity: quantity,
            avgCost: avgCost, currency: currency, offList: offList, name: name, assetClass: assetClass,
            currentValue: currentValue
        )
    }
}
