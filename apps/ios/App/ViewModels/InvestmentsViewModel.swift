import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

/// Base/display currency for portfolio subtotals -- hardcoded "INR"
/// matching Android's InvestmentsViewModel.kt / this app's own Dashboard
/// convention (no user-facing base-currency setting exists yet).
private let BASE_CURRENCY = "INR"
private let DEMAT_TYPES: Set<String> = ["demat", "stocks", "mutual_funds"]

/// Ported from apps/web/app/investments/page.tsx per
/// docs/mobile/screen-specs/investments.md (task #26). Replaces the
/// previous read-only/ungrouped stub (flat list, no grouping, no
/// add/edit/delete, "+" button was a no-op in InvestmentsView.swift) with
/// a real port mirroring Android's InvestmentsViewModel.kt field-for-field.
///
/// Deferred (see spec's Deferred section): live market quotes/LTP, the
/// instrument catalog picker, SIP recurring-transfer setup, the
/// dividend/projection panels, and the allocation-donut/gain-bar charts.
/// Everything else -- grouped list, drill-in, add/edit/delete with real
/// funding-transaction writes -- is real, matching web's actual
/// money-movement behavior (write.ts's addHolding()), not a mock.
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

    public struct HoldingUiModel: Identifiable, Equatable {
        public let id: String
        public let label: String
        public let metaLine: String
        public let quantityLine: String
        public let valueFormatted: String
        public let costFormatted: String
        public let gainFormatted: String
        public let gainPositive: Bool
        public let offList: Bool
        public let isListedClass: Bool
        public let fdExtra: String?
        public let rawQuantity: Double
        public let rawAvgCostMajor: String
        public let rawCurrentValueMajor: String
        public let rawAnnualRate: String
        public let currency: String
    }

    public struct GroupUiModel: Identifiable, Equatable {
        public var id: String { key }
        public let key: String
        public let label: String
        public let holdingsCount: Int
        public let valueFormatted: String
        public let costFormatted: String
        public let gainFormatted: String
        public let gainPositive: Bool
        public let gainPctFormatted: String
        public let holdings: [HoldingUiModel]
    }

    public var groups: [GroupUiModel] = []
    public var totalValueFormatted: String = "₹0"
    public var totalGainFormatted: String = ""
    public var totalGainPositive: Bool = true
    public var invAccounts: [InvAccountOption] = []
    public var fundingAccounts: [FundingAccountOption] = []

    private var latestHoldings: [Holding] = []
    private var currentUserId: String?

    public init() {
        Task { await startObserving() }
    }

    private func startObserving() async {
        guard let userId = try? await supabaseClient.auth.session.user.id.uuidString else { return }
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

    /// Re-fetches account balances/rates (one-shot on this platform, see
    /// LedgerRepository.swift) and rebuilds the grouped view. Called each
    /// time the holdings stream emits, and again explicitly after any
    /// write (add/update/delete) so funding-account balances reflect the
    /// just-posted transaction immediately.
    private func rebuild(holdings: [Holding]) async {
        let balances = (try? await ledgerRepository.accountBalances()) ?? []
        let rates = (try? await ledgerRepository.rates()) ?? { _, _ in 1.0 }

        invAccounts = balances
            .filter { DEMAT_TYPES.contains($0.account.type) }
            .map { InvAccountOption(id: $0.account.id, name: $0.account.name, currency: $0.account.currency) }

        fundingAccounts = balances
            .filter { !DEMAT_TYPES.contains($0.account.type) }
            .map {
                FundingAccountOption(
                    id: $0.account.id, name: $0.account.name, currency: $0.account.currency,
                    balanceFormatted: formatMoney($0.balance.amount, $0.account.currency),
                    balanceMinor: $0.balance.amount
                )
            }

        let rows = holdings.map { $0.toHoldingRow() }
        let groupsResult = buildGroups(rows) { amount, currency in
            if currency == BASE_CURRENCY { return amount }
            return (try? convert(money(amount, currency), to: BASE_CURRENCY, rate: rates(currency, BASE_CURRENCY)).amount) ?? amount
        }
        var byGroupKey: [String: [Holding]] = [:]
        for h in holdings { byGroupKey[groupKeyOf(h.toHoldingRow()), default: []].append(h) }

        groups = groupsResult.map { g in
            GroupUiModel(
                key: g.key, label: g.label, holdingsCount: g.holdings.count,
                valueFormatted: formatMoney(g.value, BASE_CURRENCY),
                costFormatted: formatMoney(g.cost, BASE_CURRENCY),
                gainFormatted: "\(g.gain >= 0 ? "+" : "")\(formatMoney(g.gain, BASE_CURRENCY)) (\(formatPct(g.gainPct)))",
                gainPositive: g.gain >= 0,
                gainPctFormatted: formatPct(g.gainPct),
                holdings: (byGroupKey[g.key] ?? []).map { self.toUiModel($0) }
            )
        }

        let totals = portfolioTotals(groupsResult)
        totalValueFormatted = formatMoney(totals.value, BASE_CURRENCY)
        totalGainPositive = totals.gain >= 0
        totalGainFormatted = "\(totals.gain >= 0 ? "+" : "")\(formatMoney(totals.gain, BASE_CURRENCY)) (\(formatPct(totals.gainPct)))"
    }

    private func toUiModel(_ h: Holding) -> HoldingUiModel {
        let row = h.toHoldingRow()
        let v = valuation(row)
        let cls = assetClassOf(row)
        var meta = "\(cls.icon) \(cls.label)"
        if cls == .stock, let ex = h.exchange, !ex.isEmpty { meta += " · \(ex)" }
        var qtyLine = ""
        if cls != .fd && cls != .other {
            let qtyText = h.quantity == h.quantity.rounded() ? String(Int64(h.quantity)) : String(h.quantity)
            qtyLine = "\(qtyText) \(cls.unitWord)".trimmingCharacters(in: .whitespaces)
        }
        var fdExtra: String?
        if cls == .fd {
            var parts: [String] = []
            if let r = h.annualRate { parts.append(String(format: "%.1f%% p.a.", r)) }
            if let m = h.maturityDate { parts.append("Matures \(String(m.prefix(10)))") }
            fdExtra = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        return HoldingUiModel(
            id: h.id, label: holdingLabel(row), metaLine: meta, quantityLine: qtyLine,
            valueFormatted: formatMoney(v.value, h.currency), costFormatted: formatMoney(v.cost, h.currency),
            gainFormatted: "\(v.gain >= 0 ? "+" : "")\(formatMoney(v.gain, h.currency))",
            gainPositive: v.gain >= 0, offList: h.offList, isListedClass: isListed(cls), fdExtra: fdExtra,
            rawQuantity: h.quantity,
            rawAvgCostMajor: h.avgCost.map { formatMajorPlain($0) } ?? "",
            rawCurrentValueMajor: h.currentValue.map { formatMajorPlain($0) } ?? "",
            rawAnnualRate: h.annualRate.map { $0 == $0.rounded() ? String(Int64($0)) : String($0) } ?? "",
            currency: h.currency
        )
    }

    /// Matches AddInvestmentDialog's scoped-down submit(): validates,
    /// funds the pool (transfer/adjustment), then inserts the holding row.
    public func addHolding(
        investmentAccountId: String, assetClass: AssetClass, name: String, exchange: String?,
        quantityText: String, avgCostMajorText: String, currentValueMajorText: String, annualRateText: String,
        maturityDate: String?, currency: String, fundingExisting: Bool, fundingSourceAccountId: String?
    ) async -> String? {
        let isLump = assetClass == .fd
        let qty = isLump ? 1.0 : (Double(quantityText) ?? 0)
        if !isLump && qty <= 0 { return "Enter a quantity greater than 0." }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a name." }
        let avgCostMinor = Double(avgCostMajorText).map { fromMajor($0, currency).amount }
        let currentValueMinor = !isListed(assetClass) ? Double(currentValueMajorText).map { fromMajor($0, currency).amount } : nil
        let annualRate = assetClass == .fd ? Double(annualRateText) : nil

        if !fundingExisting && (fundingSourceAccountId?.isEmpty ?? true) { return "Choose an account to fund this from." }
        if !fundingExisting {
            let costTotal = Int64((Double(avgCostMinor ?? 0) * qty).rounded())
            if let source = fundingAccounts.first(where: { $0.id == fundingSourceAccountId }), costTotal > source.balanceMinor {
                return "\(source.name) doesn't have enough available (\(source.balanceFormatted))."
            }
        }

        guard let userId = currentUserId else { return "Couldn't determine the current user." }
        do {
            try await investmentsRepository.addHolding(
                userId: userId,
                input: AddHoldingInput(
                    investmentAccountId: investmentAccountId, assetClass: assetClass.rawValue,
                    symbol: isListed(assetClass) ? name.trimmingCharacters(in: .whitespaces) : "",
                    exchange: assetClass == .stock ? exchange : nil,
                    name: name.trimmingCharacters(in: .whitespaces), quantity: qty, avgCost: avgCostMinor,
                    currency: currency, currentValue: currentValueMinor, annualRate: annualRate,
                    maturityDate: assetClass == .fd ? (maturityDate?.isEmpty == true ? nil : maturityDate) : nil,
                    offList: true, // no catalog picker in this pass -- every holding is manually tracked (deferred: instrument catalog)
                    autoFetch: false,
                    funding: fundingExisting ? .existing : .new(sourceAccountId: fundingSourceAccountId!)
                )
            )
            await rebuild(holdings: latestHoldings)
            return nil
        } catch {
            return "Couldn't add the investment: \(error.localizedDescription)"
        }
    }

    /// Matches web's EditHolding.save(): quantity/avg-cost/current-value/
    /// annual-rate only.
    public func updateHolding(id: String, quantityText: String, avgCostMajorText: String, currentValueMajorText: String, annualRateText: String, currency: String) async -> String? {
        guard let holding = latestHoldings.first(where: { $0.id == id }) else { return "Holding not found." }
        let cls = AssetClass.fromKey(holding.assetClass ?? holding.instrumentType)
        let isLump = cls == .fd
        guard let qty = isLump ? 1.0 : Double(quantityText) else { return "Enter a valid quantity." }
        let avgCostMinor = Double(avgCostMajorText).map { fromMajor($0, currency).amount }
        let currentValueMinor = Double(currentValueMajorText).map { fromMajor($0, currency).amount }
        let annualRate = Double(annualRateText)
        do {
            try await investmentsRepository.updateHolding(id: id, quantity: qty, avgCost: avgCostMinor, currentValue: currentValueMinor, annualRate: annualRate)
            await rebuild(holdings: latestHoldings)
            return nil
        } catch {
            return "Couldn't save changes: \(error.localizedDescription)"
        }
    }

    public func deleteHolding(_ id: String) {
        Task {
            do {
                try await investmentsRepository.deleteHolding(id: id)
                await rebuild(holdings: latestHoldings)
            } catch {
                print("Failed to delete holding: \(error)")
            }
        }
    }

    private func formatMoney(_ minor: Int64, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_IN")
        return formatter.string(from: NSNumber(value: Double(minor) / 100.0)) ?? "\(currency) \(Double(minor) / 100.0)"
    }

    private func formatPct(_ pct: Double) -> String {
        String(format: "%+.1f%%", pct)
    }

    private func formatMajorPlain(_ minor: Int64) -> String {
        let major = Double(minor) / 100.0
        return major == major.rounded() ? String(Int64(major)) : String(major)
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
