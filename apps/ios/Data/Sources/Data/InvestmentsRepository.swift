import Foundation
import PowerSync

public struct Holding: Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let accountId: String
    public let symbol: String
    public let exchange: String
    public let quantity: Double
    public let avgCost: Int64
    public let currency: String
    public let autoFetch: Bool
    public let instrumentType: String
    public let name: String?
    public let assetClass: String?
    public let currentValue: Int64?
    public let annualRate: Double?
    public let maturityDate: String?
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
            exchange: try cursor.getString(name: "exchange"),
            quantity: try cursor.getDouble(name: "quantity"),
            avgCost: try cursor.getInt64(name: "avg_cost"),
            currency: try cursor.getString(name: "currency"),
            autoFetch: (try cursor.getBooleanOptional(name: "auto_fetch")) ?? false,
            instrumentType: try cursor.getString(name: "instrument_type"),
            name: try cursor.getStringOptional(name: "name"),
            assetClass: try cursor.getStringOptional(name: "asset_class"),
            currentValue: try cursor.getInt64Optional(name: "current_value"),
            annualRate: try cursor.getDoubleOptional(name: "annual_rate"),
            maturityDate: try cursor.getStringOptional(name: "maturity_date")
        )
    }

    public func watchHoldings(userId: String) throws -> AsyncThrowingStream<[Holding], Error> {
        try db.watch(
            sql: "SELECT * FROM holdings WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at DESC",
            parameters: [userId],
            mapper: holdingMapper
        )
    }
}
