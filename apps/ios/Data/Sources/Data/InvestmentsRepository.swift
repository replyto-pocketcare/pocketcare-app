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
/// One `market_dividends` row (global, read-only market-sync table).
public struct DividendRow: Sendable {
    public let symbol: String
    public let exchange: String?
    public let exDate: String
    public let payDate: String?
    public let amount: Int64
    public let currency: String
}

/// One `market_quotes` row (global, read-only).
public struct QuoteRow: Sendable {
    public let symbol: String
    public let exchange: String?
    public let price: Int64
    public let currency: String
}

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
    /// Amount-based SIP fields (migration 0061). `plannedId` alone is not
    /// enough to tell a live SIP from a stopped one -- it can still point at a
    /// recurring row that was already cancelled -- so web gates the SIP UI on
    /// `planned_id && sip_amount > 0` and so does mobile.
    public let sipAmount: Int64?
    public let sipDay: Int64?
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

/// A SIP the user is setting up alongside the holding -- web's
/// `AddHoldingInput.sip`, mirroring Android's `SipSetup`.
///
/// `firstDue` is the date the recurring engine posts the first instalment and
/// `startDate` is when the plan began; web sends the same value for both from
/// one date field, and they are kept separate here because the COLUMNS are
/// separate (`recurring_items.next_due` moves every time the engine posts,
/// `holdings.sip_start_date` never does).
///
/// `day` is the day-of-month, already clamped to 1-28 by Domain's
/// `clampSipDay` -- the repository does not re-clamp, so there is exactly one
/// place the rule lives.
public struct SipSetup: Sendable {
    public let amount: Int64
    public let frequency: String
    public let firstDue: String
    public let sourceAccountId: String
    public let startDate: String
    public let day: Int

    public init(amount: Int64, frequency: String, firstDue: String, sourceAccountId: String, startDate: String, day: Int) {
        self.amount = amount; self.frequency = frequency; self.firstDue = firstDue
        self.sourceAccountId = sourceAccountId; self.startDate = startDate; self.day = day
    }
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
    /// Present only when the user is starting a SIP. See `SipSetup`.
    public let sip: SipSetup?

    public init(investmentAccountId: String, assetClass: String, symbol: String, exchange: String?, name: String, quantity: Double, avgCost: Int64?, currency: String, currentValue: Int64?, annualRate: Double?, maturityDate: String?, offList: Bool, autoFetch: Bool, funding: HoldingFunding, sip: SipSetup? = nil) {
        self.investmentAccountId = investmentAccountId; self.assetClass = assetClass; self.symbol = symbol
        self.exchange = exchange; self.name = name; self.quantity = quantity; self.avgCost = avgCost
        self.currency = currency; self.currentValue = currentValue; self.annualRate = annualRate
        self.maturityDate = maturityDate; self.offList = offList; self.autoFetch = autoFetch
        self.funding = funding; self.sip = sip
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
            plannedId: try cursor.getStringOptional(name: "planned_id"),
            sipAmount: try cursor.getInt64Optional(name: "sip_amount"),
            sipDay: try cursor.getInt64Optional(name: "sip_day")
        )
    }

    public func watchHoldings(userId: String) throws -> AsyncThrowingStream<[Holding], Error> {
        try db.watch(
            sql: "SELECT * FROM holdings WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at DESC",
            parameters: [userId],
            mapper: holdingMapper
        )
    }

    /// Global, read-only market-sync tables -- no user_id/deleted_at filter,
    /// matches web's own unscoped queries exactly. Added 2026-08-06 for
    /// Insights' dividend_income/portfolio_projection cards (task #28), the
    /// first mobile reader of either table (mirrors Android's
    /// InvestmentsRepository.kt watchDividends()/watchQuotes() added the
    /// same session).
    public func watchDividends() throws -> AsyncThrowingStream<[DividendRow], Error> {
        try db.watch(
            sql: "SELECT symbol, exchange, ex_date, pay_date, amount, currency FROM market_dividends",
            parameters: []
        ) { cursor in
            DividendRow(
                symbol: try cursor.getString(name: "symbol"), exchange: try cursor.getStringOptional(name: "exchange"),
                exDate: try cursor.getString(name: "ex_date"), payDate: try cursor.getStringOptional(name: "pay_date"),
                amount: try cursor.getInt64(name: "amount"), currency: try cursor.getString(name: "currency")
            )
        }
    }

    /// The same rows as `watchDividends`, read once.
    ///
    /// The Investments view model rebuilds on the holdings stream and pulls
    /// balances and rates one-shot at that moment (see its `rebuild`); a
    /// second live stream would put it on two clocks, and the dividend table
    /// is refreshed by a once-a-day market sync, so there is nothing to watch
    /// between rebuilds. Mirrors LedgerRepository's `accountBalances()`.
    public func dividendsOnce() async throws -> [DividendRow] {
        try await db.getAll(
            sql: "SELECT symbol, exchange, ex_date, pay_date, amount, currency FROM market_dividends",
            parameters: [],
            mapper: { cursor in
                DividendRow(
                    symbol: try cursor.getString(name: "symbol"), exchange: try cursor.getStringOptional(name: "exchange"),
                    exDate: try cursor.getString(name: "ex_date"), payDate: try cursor.getStringOptional(name: "pay_date"),
                    amount: try cursor.getInt64(name: "amount"), currency: try cursor.getString(name: "currency")
                )
            }
        )
    }

    public func watchQuotes() throws -> AsyncThrowingStream<[QuoteRow], Error> {
        try db.watch(
            sql: "SELECT symbol, exchange, price, currency FROM market_quotes",
            parameters: []
        ) { cursor in
            QuoteRow(
                symbol: try cursor.getString(name: "symbol"), exchange: try cursor.getStringOptional(name: "exchange"),
                price: try cursor.getInt64(name: "price"), currency: try cursor.getString(name: "currency")
            )
        }
    }

    /// Adds a holding -- matches write.ts's addHolding() exactly: funds the
    /// invested pool first (transfer from a source account, or an adjustment
    /// on the investment account itself for an already-owned holding),
    /// creates the SIP's recurring transfer if there is one, then inserts the
    /// `holdings` row.
    ///
    /// The SIP half was missing until now, and its absence was not cosmetic:
    /// `planned_id` was hardcoded null and `sip_amount`/`sip_day` were never
    /// written, so a SIP could not be created on a phone AT ALL and the Stop
    /// SIP control could only ever appear for a holding created on web
    /// (PARITY_AUDIT 2026-08-28, item 9).
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

        // The SIP is a recurring `saving` transfer: source account -> this
        // investment account, auto-posting on its own schedule.
        //
        // This is the ONLY place a recurring saving item is created on either
        // platform, exactly as on web. Recurring savings are not browsable
        // under Recurring, so a SIP belongs to the holding that funds it and
        // is created and stopped there (see stopSipForHolding). It still posts
        // through the shared engine and still shows in the "Due now" strip.
        //
        // One row, not a template + rule pair: `recurring_items` carries both
        // the schedule and the transaction detail (migration 0064).
        // Written through `insertRow`, not the hand-rolled SQL the rest of this
        // function still uses: it is the documented convention (WriteHelpers),
        // it fills id/user_id/timestamps, and it routes through `withLoading`
        // so the sync indicator sees the write.
        var plannedId: String? = nil
        if let sip = input.sip, sip.amount > 0, !sip.sourceAccountId.isEmpty {
            plannedId = try await insertRow(
                db: db, table: "recurring_items", userId: userId,
                // The columns web sends as an explicit null (category_id, note,
                // labels, split_*, last_generated, source_*) are simply not
                // listed: an omitted column on an INSERT is NULL, and a
                // heterogeneous Swift dictionary literal cannot carry a bare
                // `nil` without a contextual type. Same rows result.
                //
                // Int64, not Int: this schema's integers bind as Int64
                // everywhere else in :data (see RecurringRepository.Input.row),
                // and a bare literal would infer Int.
                values: [
                    "direction": "saving",
                    "name": input.name.isEmpty ? (input.symbol.isEmpty ? "SIP" : input.symbol) : input.name,
                    "amount": sip.amount,
                    "currency": input.currency,
                    "frequency": sip.frequency,
                    // Web hardcodes 1 here too -- every interval the UI offers
                    // is "every 1 <frequency>".
                    "interval_count": Int64(1),
                    "next_due": sip.firstDue,
                    "account_id": sip.sourceAccountId,
                    "to_account_id": input.investmentAccountId,
                    "auto_post": Int64(1),
                    "active": Int64(1),
                    "description": "SIP",
                ]
            )
        }

        let id = newId()
        // A SIP's money movement IS the recurring transfer, so its source
        // account is the debit account, not a one-off funding account -- web
        // resolves it in the same order.
        let fundingSourceId: String? = { if case .new(let s) = input.funding { return s }; return nil }()
        let sourceAccountId: String? = input.sip?.sourceAccountId ?? fundingSourceId
        let instrumentType: String? = input.assetClass == "mf" ? "mf" : (input.assetClass == "stock" ? "stock" : nil)
        // Amount-based SIP fields (migration 0061). Written together with
        // `planned_id`: the UI reads a live SIP as
        // `planned_id != nil && sip_amount > 0`, and half of that pair is what
        // made every mobile-created holding look SIP-less.
        let sipAmount: Int64? = plannedId == nil ? nil : input.sip?.amount
        let sipStartDate: String? = plannedId == nil ? nil : input.sip?.startDate
        let sipDay: Int64? = plannedId == nil ? nil : input.sip.map { Int64($0.day) }
        try await db.execute(
            sql: """
                INSERT INTO holdings
                 (id,user_id,account_id,symbol,exchange,name,quantity,avg_cost,currency,asset_class,instrument_type,
                  current_value,annual_rate,maturity_date,source_account_id,planned_id,off_list,auto_fetch,
                  sip_amount,sip_start_date,sip_day,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [
                id, userId, input.investmentAccountId, input.symbol, input.exchange,
                input.name.isEmpty ? nil : input.name, input.quantity, input.avgCost, input.currency,
                input.assetClass, instrumentType, input.currentValue, input.annualRate, input.maturityDate,
                sourceAccountId, plannedId, input.offList ? 1 : 0, input.autoFetch ? 1 : 0,
                sipAmount, sipStartDate, sipDay, ts, ts,
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

    /// Stop the SIP attached to a holding -- web's `stopSipForHolding()`.
    ///
    /// The recurring transfer is a standing debit on a real account, and
    /// recurring savings are not browsable under Recurring, so if this is
    /// skipped there is nowhere left for the user to go and cancel it: the
    /// money keeps leaving every month for an investment that no longer
    /// exists. No-op when the holding never had one.
    public func stopSipForHolding(plannedId: String?) async throws {
        guard let plannedId else { return }
        try await softDelete(db: db, table: "recurring_items", id: plannedId)
    }

    /// Clears the holding's own SIP fields, so `sipAmount > 0` stops reporting
    /// a live SIP once the recurring row is gone. Matches web's
    /// `updateRow("holdings", id, { sip_amount: null, sip_day: null })`.
    public func clearSipFields(id: String) async throws {
        try await db.execute(
            sql: "UPDATE holdings SET sip_amount = NULL, sip_day = NULL, updated_at = ? WHERE id = ?",
            parameters: [nowIso(), id]
        )
    }

    /// Matches web's remove(): soft-delete the holding row, and kill its SIP
    /// first -- the funding transaction is deliberately NOT reversed (same
    /// accepted asymmetry as Goals' allocation-delete-doesn't-cascade,
    /// documented in docs/mobile/screen-specs/goals.md), but a live standing
    /// debit is not an asymmetry, it is money still moving.
    public func deleteHolding(id: String, plannedId: String?) async throws {
        try await stopSipForHolding(plannedId: plannedId)
        try await softDelete(db: db, table: "holdings", id: id)
    }
}
