package com.sanvya.app.data.di

import android.content.Context
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.auth.AuthRepositoryImpl
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
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.repository.SubscriptionsRepository
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

val dataModule = module {
    single<AuthRepository> { AuthRepositoryImpl(get()) }

    single<SupabaseClient> {
        createSupabaseClient(
            supabaseUrl = "https://iagsmqtjadzdhcjdysno.supabase.co",
            supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlhZ3NtcXRqYWR6ZGhjamR5c25vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5ODYzODUsImV4cCI6MjA5ODU2MjM4NX0.Yh4VE6Nd_UDAXYfk_qKsm3C6PGhxq6kMxVO53ITw6Qc"
        ) {
            install(Auth)
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
            powerSyncUrl = "https://6a464d1c68bc6e1f7cad8804.powersync.journeyapps.com"
        )
    }

    single { LedgerRepository(get()) }
    single { BudgetRepository(get()) }
    single { CreditCardRepository(get(), get()) }
    single { GoalsRepository(get()) }
    single { InvestmentsRepository(get()) }
    single { LoansRepository(get()) }
    single { SplitsRepository(get(), get()) }
    single { com.sanvya.app.data.repository.UpiRepository(get()) }
    single { SubscriptionsRepository(get()) }
    single { com.sanvya.app.data.repository.PrefsRepository(get()) }
    // Settings' own data access — keeps SupabaseClient/PowerSyncDatabase out of :app.
    single { com.sanvya.app.data.repository.SettingsRepository(get(), get()) }
    // The shell's bell badge and the notifications inbox.
    single { com.sanvya.app.data.repository.NotificationsRepository(get()) }
    single {
        val auth: AuthRepository = get()
        ReceiptsRepository(db = get(), getUserId = { auth.currentUserId.value ?: "" })
    }
    single<com.sanvya.app.domain.repository.PushRepository> { com.sanvya.app.data.repository.SupabasePushRepository(get()) }
    single {
        val auth: AuthRepository = get()
        RepairRepository(db = get(), client = get(), getUserId = { auth.currentUserId.value ?: "" })
    }
}
