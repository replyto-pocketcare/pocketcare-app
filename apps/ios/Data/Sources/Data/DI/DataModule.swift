import Foundation
import Factory
import Supabase
import PowerSync
import Domain

// MARK: - DataModule (Factory)

public extension Container {
    /// Which backend this build talks to. See Config/SanvyaConfig.swift — the
    /// URL and key below used to be literals right here.
    var sanvyaConfig: Factory<SanvyaConfig> {
        self { BundleSanvyaConfig() }.singleton
    }

    var supabaseClient: Factory<SupabaseClient> {
        self {
            let config = self.sanvyaConfig()
            return SupabaseClient(
                supabaseURL: config.supabaseURL,
                supabaseKey: config.supabaseAnonKey
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
                powerSyncUrl: self.sanvyaConfig().powerSyncURL
            )
        }.singleton
    }

    var authRepository: Factory<AuthRepository> {
        self {
            AuthRepositoryImpl(
                client: self.supabaseClient(),
                config: self.sanvyaConfig()
            )
        }.singleton
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

    // The two catch-up engines. Both take repositories rather than reaching for
    // the database directly for the writes -- createTransaction() carries the
    // overdraft guard and the transfer/items validation, and an engine that
    // bypassed it would post rows the app itself would refuse.
    var recurringRepository: Factory<RecurringRepository> {
        self {
            RecurringRepository(
                db: self.powerSyncDatabase(),
                ledger: self.ledgerRepository(),
                splits: self.splitsRepository()
            )
        }.singleton
    }

    var loanAutoPostRepository: Factory<LoanAutoPostRepository> {
        self {
            LoanAutoPostRepository(db: self.powerSyncDatabase(), ledger: self.ledgerRepository())
        }.singleton
    }

    // Takes the database (the disclosure audit trail is synced and read from
    // local SQLite) and UserDefaults (the masked hint is a device pref, exactly
    // as web keeps it in localStorage) alongside the client the Edge Function
    // calls go through.
    var upiRepository: Factory<UpiRepository> {
        self {
            let auth = self.authRepository()
            return UpiRepository(
                client: self.supabaseClient(),
                db: self.powerSyncDatabase(),
                getUserId: { auth.currentUserId }
            )
        }.singleton
    }

    var invitesRepository: Factory<InvitesRepository> {
        self { InvitesRepository(client: self.supabaseClient()) }.singleton
    }

    var assistantRepository: Factory<AssistantRepository> {
        self {
            AssistantRepository(
                db: self.powerSyncDatabase(),
                client: self.supabaseClient(),
                ledgerRepository: self.ledgerRepository(),
                goalsRepository: self.goalsRepository(),
                budgetRepository: self.budgetRepository(),
                subscriptionsRepository: self.subscriptionsRepository(),
                splitsRepository: self.splitsRepository()
            )
        }.singleton
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

    /// The shell's bell badge and the notifications inbox.
    var notificationsRepository: Factory<NotificationsRepository> {
        self { NotificationsRepository(db: self.powerSyncDatabase()) }.singleton
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

    // Zero-trust field encryption: the key lifecycle, the support grants, and
    // the Keychain that holds an unlock across app termination. The support
    // public key is passed in rather than injected so the repository never
    // learns what SanvyaConfig is.
    var secureKeyStore: Factory<SecureKeyStore> {
        self { SecureKeyStore() }.singleton
    }

    var securityRepository: Factory<SecurityRepository> {
        self {
            let auth = self.authRepository()
            return SecurityRepository(
                db: self.powerSyncDatabase(),
                client: self.supabaseClient(),
                store: self.secureKeyStore(),
                getUserId: { auth.currentUserId },
                supportPublicJwk: self.sanvyaConfig().supportPublicJwk
            )
        }.singleton
    }

    var pushRepository: Factory<PushRepository> {
        self { SupabasePushRepository(client: self.supabaseClient()) }.singleton
    }

    var subscriptionsRepository: Factory<SubscriptionsRepository> {
        self { SubscriptionsRepository(db: self.powerSyncDatabase()) }.singleton
    }

    var feedbackRepository: Factory<FeedbackRepository> {
        self { FeedbackRepository(db: self.powerSyncDatabase()) }.singleton
    }

    // Task #62 (Receipt Scan capture) -- ReceiptsRepository itself already
    // existed (P2.5) but was never registered here, so nothing could ever
    // resolve it via DI. That's why the old ReceiptScanView.swift was a
    // hardcoded fixture with no repository wiring at all.
    var receiptsRepository: Factory<ReceiptsRepository> {
        self {
            let auth = self.authRepository()
            return ReceiptsRepository(
                db: self.powerSyncDatabase(),
                getUserId: { auth.currentUserId ?? "" },
                client: self.supabaseClient()
            )
        }.singleton
    }
}
