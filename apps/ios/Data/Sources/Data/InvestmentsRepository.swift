import Foundation
import PowerSync

/// Investments (holdings) repository -- P3.20 (task #26), read/write.
/// Mirrors apps/web/src/investments/write.ts's addHolding() and
/// page.tsx's EditHolding.save()/remove() exactly, and Android's
/// InvestmentsRepository.kt field-for-field. See docs/mobile/
/// screen-specs/investments.md for the full source-verification notes.
///
/// Fixed this pass (2026-08-06): `exchange`/`instrumentType`/`avgCost`
/// were previously mapped as non-nullable via non-optional cursor
/// getters despite web's HoldingRow treating all three as nullable
/// (`exchange: string | null`, `instrument_type: string | null`,
/// `avg_cost: number | null`) -- a real runtime-crash risk for any
/// holding where those columns are actually null (e.g. a freshly-added
/// FD/crypto/other-scheme holding has no exchange). `current_value` was
/// already correctly typed `Int64?` but that's the one column this file
/// already read with the right optional accessor. Also added the three
/// columns the schema already had (PocketCareSchema.swift's `holdings`
/// table) but this repository's `Holding` struct was missing entirely:
/// `off_list` (functionally significant -- gates the "untracked" display,
/// see Domain/InvestmentsModel.swift's `holdingLabel`/`valuation`),
/// `source_account_id`, `planned_id`.
public struct Holding: Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let accountId: String
    public let symbol: String
    public let exchange: String?
    public let quantity: Double
    public let avgCost: Int64?
    public let currency: String
    public let autoFetch: Bool
    public let instrumentType: String?
    public let offList: Bool
    public let name: String?
    public let assetClass: String?
    public let currentValue: Int64?
    public let annualRate: Double?
    public let maturityDate: String?
    public let sourceAccountId: String?
    public let plannedId: String?
}

/// Funding mode for a new holding -- matches web's AddHoldingInput.funding
/// union: an EXISTING holding raises the investment account's invested
/// pool via an `adjustment` entry (money was already in the market); a
/// NEW investment `transfer`s the cost from a chosen account into the
/// investment account (money moves, net worth preserved).
public enum HoldingFunding: Sendable {
    case existing
    case new(sourceAccountId: String)
}

public struct AddHoldingInput: Sendable {
    public let investmentAccountId: String
    public let assetClass: String
    public let symbol: String
    public let exchange: String?
    public let name: String
    public let quantity: Double
    public let avgCost: Int64?
    public let currency: String
    public let currentValue: Int64?
    public let annualRate: Double?
    public let maturityDate: String?
    public let offList: Bool
    public let autoFetch: Bool
    public let funding: HoldingFunding

    public init(investmentAccountId: String, assetClass: String, symbol: String, exchange: String?, name: String, quantity: Double, avgCost: Int64?, currency: String, currentValue: Int64?, annualRate: Double?, maturityDate: String?, offList: Bool, autoFetch: Bool, funding: HoldingFunding) {
        self.investmentAccountId = investmentAccountId; self.assetClass = assetClass; self.symbol = symbol
        self.exchange = exchange; self.name = name; self.quantity = quantity; self.avgCost = avgCost
        self.currency = currency; self.currentValue = currentValue; self.annualRate = annualRate
        self.maturityDate = maturityDate; self.offList = offList; self.autoFetch = autoFetch; self.funding = funding
    }
}

public actor InvestmentsRepository {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    private func holdingMapper(cursor: SqlCursor) throws -> Holding {
        Holding(
            id: try cursor.getString(name: "id"),
            userId: try cursor.getString(name: "user_id"),
            accountId: try cursor.getString(name: "account_id"),
            symbol: try cursor.getString(name: "symbol"),
            exchange: try cursor.getStringOptional(name: "exchange"),
            quantity: try cursor.getDouble(name: "quantity"),
            avgCost: try cursor.getInt64Optional(name: "avg_cost"),
            currency: try cursor.getString(name: "currency"),
            autoFetch: (try cursor.getBooleanOptional(name: "auto_fetch")) ?? false,
            instrumentType: try cursor.getStringOptional(name: "instrument_type"),
            offList: (try cursor.getBooleanOptional(name: "off_list")) ?? false,
            name: try cursor.getStringOptional(name: "name"),
            assetClass: try cursor.getStringOptional(name: "asset_class"),
            currentValue: try cursor.getInt64Optional(name: "current_value"),
            annualRate: try cursor.getDoubleOptional(name: "annual_rate"),
            maturityDate: try cursor.getStringOptional(name: "maturity_date"),
            sourceAccountId: try cursor.getStringOptional(name: "source_account_id"),
            plannedId: try cursor.getStringOptional(name: "planned_id")
        )
    }

    public func watchHoldings(userId: String) throws -> AsyncThrowingStream<[Holding], Error> {
        try db.watch(
            sql: "SELECT * FROM holdings WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at DESC",
            parameters: [userId],
            mapper: holdingMapper
        )
    }

    /// Adds a holding -- matches write.ts's addHolding() exactly: funds
    /// the invested pool first (transfer from a source account, or an
    /// adjustment on the investment account itself for an already-owned
    /// holding), then inserts the `holdings` row. SIP recurring-transfer
    /// setup and the live-catalog instrument picker are deferred (see
    /// screen spec) so there is no `sip` parameter here, unlike web's.
    @discardableResult
    public func addHolding(userId: String, input: AddHoldingInput) async throws -> String {
        let costTotal = Int64((Double(input.avgCost ?? 0) * input.quantity).rounded())
        let ts = nowIso()

        if costTotal > 0 {
            switch input.funding {
            case .new(let sourceAccountId):
                try await db.execute(
                    sql: """
                        INSERT INTO transactions
                         (id,user_id,account_id,type,amount,currency,to_account_id,to_amount,description,occurred_at,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                        """,
                    parameters: [
                        newId(), userId, sourceAccountId, "transfer", costTotal, input.currency,
                        input.investmentAccountId, costTotal,
                        "Invested in \(input.name.isEmpty ? (input.symbol.isEmpty ? "investment" : input.symbol) : input.name)",
                        ts, ts, ts,
                    ]
                )
            case .existing:
                try await db.execute(
                    sql: """
                        INSERT INTO transactions
                         (id,user_id,account_id,type,amount,currency,description,occurred_at,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?,?,?,?)
                        """,
                    parameters: [
                        newId(), userId, input.investmentAccountId, "adjustment", costTotal, input.currency,
                        "Existing investment: \(input.name.isEmpty ? (input.symbol.isEmpty ? "holding" : input.symbol) : input.name)",
                        ts, ts, ts,
                    ]
                )
            }
        }

        let id = newId()
        let sourceAccountId: String? = { if case .new(let s) = input.funding { return s }; return nil }()
        let instrumentType: String? = input.assetClass == "mf" ? "mf" : (input.assetClass == "stock" ? "stock" : nil)
        try await db.execute(
            sql: """
                INSERT INTO holdings
                 (id,user_id,account_id,symbol,exchange,name,quantity,avg_cost,currency,asset_class,instrument_type,
                  current_value,annual_rate,maturity_date,source_account_id,planned_id,off_list,auto_fetch,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [
                id, userId, input.investmentAccountId, input.symbol, input.exchange,
                input.name.isEmpty ? nil : input.name, input.quantity, input.avgCost, input.currency,
                input.assetClass, instrumentType, input.currentValue, input.annualRate, input.maturityDate,
                sourceAccountId, nil, input.offList ? 1 : 0, input.autoFetch ? 1 : 0, ts, ts,
            ]
        )
        return id
    }

    /// Matches web's EditHolding.save(): quantity/avg_cost always
    /// editable; current_value/annual_rate only meaningful for unpriced
    /// holdings but harmless to write through for priced ones (web does
    /// the same -- updateRow always sends all four).
    public func updateHolding(id: String, quantity: Double, avgCost: Int64?, currentValue: Int64?, annualRate: Double?) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE holdings SET quantity = ?, avg_cost = ?, current_value = ?, annual_rate = ?, updated_at = ? WHERE id = ?",
            parameters: [quantity, avgCost, currentValue, annualRate, ts, id]
        )
    }

    /// Matches web's remove(): soft-delete the holding row only -- no
    /// reversal of the funding transaction (same accepted asymmetry as
    /// Goals' allocation-delete-doesn't-cascade, already documented in
    /// docs/mobile/screen-specs/goals.md).
    public func deleteHolding(id: String) async throws {
        try await softDelete(db: db, table: "holdings", id: id)
    }
}
