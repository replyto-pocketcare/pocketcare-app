package com.sanvya.app.data.di

import android.content.Context
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.auth.AuthRepositoryImpl
import com.sanvya.app.data.config.SanvyaConfig
import com.sanvya.app.data.config.sanvyaConfig
import com.powersync.PowerSyncDatabase
import com.sanvya.app.data.db.DatabaseManager
import com.sanvya.app.data.sync.SupabaseConnector
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.functions.Functions
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.BudgetRepository
import com.sanvya.app.data.repository.CreditCardRepository
import com.sanvya.app.data.repository.GoalsRepository
import com.sanvya.app.data.repository.InvestmentsRepository
import com.sanvya.app.data.repository.LoansRepository
import com.sanvya.app.data.repository.ReceiptsRepository
import com.sanvya.app.data.repository.RepairRepository
import com.sanvya.app.data.repository.LoanAutoPostRepository
import com.sanvya.app.data.repository.RecurringRepository
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.repository.SubscriptionsRepository
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

val dataModule = module {
    // Which backend this build talks to. See config/SanvyaConfig.kt -- the
    // URLs and keys below used to be literals right here.
    single<SanvyaConfig> { sanvyaConfig() }

    single<AuthRepository> { AuthRepositoryImpl(get()) }

    single<SupabaseClient> {
        val config: SanvyaConfig = get()
        createSupabaseClient(
            supabaseUrl = config.supabaseUrl,
            supabaseKey = config.supabaseAnonKey,
        ) {
            install(Auth) {
                // The custom-scheme callback the OAuth provider returns to.
                // supabase-kt builds `<scheme>://<host>` from these and hands
                // it to the provider; MainActivity forwards the resulting
                // Intent back in via handleDeeplinks(). Both halves read the
                // same config, and the manifest intent filter is generated
                // from the same two Gradle properties, so the three cannot
                // drift out of agreement.
                scheme = config.authRedirectScheme
                host = config.authRedirectHost
            }
            install(Postgrest)
            install(Functions)
        }
    }

    single<PowerSyncDatabase> {
        DatabaseManager.createDatabase(androidContext())
    }

    single<SupabaseConnector> {
        SupabaseConnector(
            client = get(),
            powerSyncUrl = get<SanvyaConfig>().powerSyncUrl,
        )
    }

    single { LedgerRepository(get()) }
    single { BudgetRepository(get()) }
    single { CreditCardRepository(get(), get()) }
    single { GoalsRepository(get()) }
    single { InvestmentsRepository(get()) }
    single { LoansRepository(get()) }
    single { SplitsRepository(get(), get()) }
    // The two catch-up engines. Both take repositories rather than reaching for
    // the database directly for the writes -- createTransaction() carries the
    // overdraft guard and the transfer/items validation, and an engine that
    // bypassed it would post rows the app itself would refuse.
    single { RecurringRepository(db = get(), ledger = get(), splits = get()) }
    single { LoanAutoPostRepository(db = get(), ledger = get()) }
    single { com.sanvya.app.data.repository.UpiRepository(get()) }
    single { com.sanvya.app.data.repository.InvitesRepository(get()) }
    single { com.sanvya.app.data.repository.FeedbackRepository(get()) }
    single {
        com.sanvya.app.data.repository.AssistantRepository(
            db = get(),
            client = get(),
            ledgerRepository = get(),
            goalsRepository = get(),
            budgetRepository = get(),
            subscriptionsRepository = get(),
            splitsRepository = get(),
        )
    }
    single { SubscriptionsRepository(get()) }
    single { com.sanvya.app.data.repository.PrefsRepository(get()) }
    // Settings' own data access — keeps SupabaseClient/PowerSyncDatabase out of :app.
    single { com.sanvya.app.data.repository.SettingsRepository(get(), get()) }
    // The dashboard's "Worth a look" strip -- one row of counts, one query.
    single { com.sanvya.app.data.repository.SuggestionsRepository(get()) }
    // The app's ONE sync status: online + connected + hasSynced + lastSyncedAt,
    // on a single poll loop. Replaces four independent 400 ms pollers and the
    // shell's private connectivity callback -- see SyncStatusRepository.kt.
    single { com.sanvya.app.data.sync.SyncStatusRepository(androidContext(), get()) }
    // The thing that actually connects PowerSync to the server. Until this
    // existed, `SupabaseConnector` was built here and handed to nothing --
    // see SyncBootstrap.kt.
    single { com.sanvya.app.data.sync.SyncBootstrap(get(), get(), get()) }
    // The shell's bell badge and the notifications inbox.
    single { com.sanvya.app.data.repository.NotificationsRepository(get()) }
    single {
        val auth: AuthRepository = get()
        ReceiptsRepository(db = get(), getUserId = { auth.currentUserId.value ?: "" }, client = get())
    }
    single<com.sanvya.app.domain.repository.PushRepository> { com.sanvya.app.data.repository.SupabasePushRepository(get()) }
    single {
        val auth: AuthRepository = get()
        RepairRepository(db = get(), client = get(), getUserId = { auth.currentUserId.value ?: "" })
    }
}
