import Foundation
import Factory
import Supabase
import PowerSync
import Domain

// MARK: - DataModule (Factory)

public extension Container {
    var supabaseClient: Factory<SupabaseClient> {
        self {
            SupabaseClient(
                supabaseURL: URL(string: "https://iagsmqtjadzdhcjdysno.supabase.co")!,
                supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlhZ3NtcXRqYWR6ZGhjamR5c25vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5ODYzODUsImV4cCI6MjA5ODU2MjM4NX0.Yh4VE6Nd_UDAXYfk_qKsm3C6PGhxq6kMxVO53ITw6Qc"
            )
        }.singleton
    }

    var powerSyncDatabase: Factory<PowerSyncDatabaseProtocol> {
        self {
            let powersyncTables = PocketCareSchema.tables.map { tableDef in
                Table(
                    name: tableDef.name,
                    columns: tableDef.columns.map { col in
                        let type: ColumnData
                        switch col.type {
                        case .text: type = .text
                        case .integer: type = .integer
                        case .real: type = .real
                        }
                        return Column(name: col.name, type: type)
                    },
                    indexes: tableDef.indexes.map { idx in
                        Index(
                            name: idx.name,
                            columns: idx.columns.map { idxCol in
                                IndexedColumn(column: idxCol.name, ascending: idxCol.ascending)
                            }
                        )
                    },
                    localOnly: tableDef.localOnly,
                    insertOnly: tableDef.insertOnly
                )
            }
            let schema = Schema(tables: powersyncTables)
            return try! PowerSyncDatabase(schema: schema, dbFilename: "pocketcare.db")
        }.singleton
    }

    var supabaseConnector: Factory<SupabaseConnector> {
        self {
            SupabaseConnector(
                client: self.supabaseClient(),
                powerSyncUrl: "https://6a464d1c68bc6e1f7cad8804.powersync.journeyapps.com"
            )
        }.singleton
    }

    var authRepository: Factory<AuthRepository> {
        self { AuthRepositoryImpl(client: self.supabaseClient()) }.singleton
    }

    var ledgerRepository: Factory<LedgerRepository> {
        self { LedgerRepository(db: self.powerSyncDatabase()) }.singleton
    }

    var budgetRepository: Factory<BudgetRepository> {
        self { BudgetRepository(db: self.powerSyncDatabase()) }.singleton
    }

    var creditCardRepository: Factory<CreditCardRepository> {
        self { CreditCardRepository(db: self.powerSyncDatabase(), transactions: self.ledgerRepository()) }.singleton
    }

    var splitsRepository: Factory<SplitsRepository> {
        self { SplitsRepository(db: self.powerSyncDatabase(), ledger: self.ledgerRepository()) }.singleton
    }

    var upiRepository: Factory<UpiRepository> {
        self { UpiRepository(client: self.supabaseClient()) }.singleton
    }

    var goalsRepository: Factory<GoalsRepository> {
        self { GoalsRepository(db: self.powerSyncDatabase()) }.singleton
    }

    var investmentsRepository: Factory<InvestmentsRepository> {
        self { InvestmentsRepository(db: self.powerSyncDatabase()) }.singleton
    }

    var loansRepository: Factory<LoansRepository> {
        self { LoansRepository(db: self.powerSyncDatabase()) }.singleton
    }

    var prefsRepository: Factory<PrefsRepository> {
        self { PrefsRepository(db: self.powerSyncDatabase()) }.singleton
    }

    var repairRepository: Factory<RepairRepository> {
        self {
            let auth = self.authRepository()
            return RepairRepository(
                db: self.powerSyncDatabase(),
                client: self.supabaseClient(),
                getUserId: { auth.currentUserId ?? "" }
            )
        }.singleton
    }

    var pushRepository: Factory<PushRepository> {
        self { SupabasePushRepository(client: self.supabaseClient()) }.singleton
    }

    var subscriptionsRepository: Factory<SubscriptionsRepository> {
        self { SubscriptionsRepository(db: self.powerSyncDatabase()) }.singleton
    }
}
