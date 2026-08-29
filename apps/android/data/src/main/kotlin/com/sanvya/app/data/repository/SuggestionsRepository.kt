package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLong
import com.sanvya.app.domain.suggestions.UsageCounts
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * How much of the app this person has actually used, as one row of counts.
 *
 * Feeds `pickSuggestions()` (`:domain`), which is what decides the dashboard's
 * "Worth a look" strip. Nothing here judges anything -- the rules live in
 * Domain under golden vectors, and this is only the SELECT.
 *
 * **One query with scalar subselects, not twelve watches.** Web says why in
 * `Suggestions.tsx` and it holds harder here: twelve `db.watch` calls would open
 * twelve subscriptions over the same tables to fetch twelve integers, and every
 * write to any of them would wake all twelve.
 *
 * A note on the source. Web's version of this query ends
 * `... AS creditCards,` -- a trailing comma with nothing after it, which is not
 * valid SQL. Its strip therefore never renders. The port fixes the comma rather
 * than reproducing the outage; the defect is recorded in
 * docs/mobile/PARITY_AUDIT.md's web-defects table.
 *
 * A second, separate defect in the same query: it filters `credit_card_details`
 * on `deleted_at`, and that is the one table of the twelve here that does not
 * HAVE that column (see `packages/db/src/index.ts`). SQLite raises `no such
 * column`, so even with the comma fixed the stream would throw on its first
 * evaluation. Both are fixed here, which makes this the first time the ranking
 * has actually run anywhere.
 */
class SuggestionsRepository(private val db: PowerSyncDatabase) {

    fun watchUsageCounts(): Flow<UsageCounts> = db.watch(
        USAGE_SQL,
        mapper = { cursor ->
            UsageCounts(
                accounts = cursor.getLong("accounts").toInt(),
                transactions = cursor.getLong("transactions").toInt(),
                subscriptions = cursor.getLong("subscriptions").toInt(),
                loans = cursor.getLong("loans").toInt(),
                budgets = cursor.getLong("budgets").toInt(),
                goals = cursor.getLong("goals").toInt(),
                splitGroups = cursor.getLong("splitGroups").toInt(),
                receipts = cursor.getLong("receipts").toInt(),
                recurring = cursor.getLong("recurring").toInt(),
                holdings = cursor.getLong("holdings").toInt(),
                creditCards = cursor.getLong("creditCards").toInt(),
                creditCardAccounts = cursor.getLong("creditCardAccounts").toInt(),
            )
        },
        // An unreadable row is NOT "a user with nothing" -- that is exactly the
        // shape that makes the strip suggest a first budget to someone who has
        // five. `pickSuggestions` returns nothing for an all-zero count, so an
        // empty emission is silence rather than a wrong guess.
    ).map { rows -> rows.firstOrNull() ?: UsageCounts() }

    private companion object {
        /**
         * Web's own query, character for character apart from the trailing comma
         * noted above. `IFNULL(kind,'real')` keeps the two virtual split
         * accounts ("Owed to me" / "I owe") out of the account count: someone
         * who has only those has not set anything up.
         */
        const val USAGE_SQL = """
            SELECT
              (SELECT COUNT(*) FROM accounts WHERE deleted_at IS NULL AND IFNULL(kind,'real')='real') AS accounts,
              (SELECT COUNT(*) FROM accounts WHERE deleted_at IS NULL AND type='credit_card') AS creditCardAccounts,
              (SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL) AS transactions,
              (SELECT COUNT(*) FROM subscriptions WHERE deleted_at IS NULL) AS subscriptions,
              (SELECT COUNT(*) FROM loans WHERE deleted_at IS NULL) AS loans,
              (SELECT COUNT(*) FROM budgets WHERE deleted_at IS NULL) AS budgets,
              (SELECT COUNT(*) FROM goals WHERE deleted_at IS NULL) AS goals,
              (SELECT COUNT(*) FROM split_groups WHERE deleted_at IS NULL) AS splitGroups,
              (SELECT COUNT(*) FROM receipt_scans WHERE deleted_at IS NULL) AS receipts,
              (SELECT COUNT(*) FROM recurring_items WHERE deleted_at IS NULL) AS recurring,
              (SELECT COUNT(*) FROM holdings WHERE deleted_at IS NULL) AS holdings,
              (SELECT COUNT(*) FROM credit_card_details) AS creditCards
        """
    }
}
