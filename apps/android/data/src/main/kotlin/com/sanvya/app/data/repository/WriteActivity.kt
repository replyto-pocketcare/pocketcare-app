package com.sanvya.app.data.repository

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * How many synced-row writes are in flight.
 *
 * Kotlin mirror of the counter inside `apps/web/src/ui/GlobalLoader.tsx`, which
 * `write.ts` wraps every INSERT/UPDATE in via `withLoading()`. The shell reads
 * it and shows a small spinner in the corner while anything is being written.
 *
 * **This is deliberately global mutable state, and that is worth saying out
 * loud.** Web's is a module-level `let count = 0` with a `Set` of listeners. A
 * per-screen loading flag would be the cleaner design, but it is not the design
 * being ported: the whole point of web's indicator is that it fires for writes
 * the current screen did not start -- a background auto-post, a sync repair, a
 * settlement confirmed from a notification -- and a per-screen flag cannot see
 * those. A single counter in the layer that performs every write can.
 *
 * It is confined to the three helpers in WriteHelpers.kt, so there is exactly
 * one place that increments it and exactly one that decrements it.
 *
 * Mirrors iOS's WriteActivity.swift.
 */
object WriteActivity {
    private val state = MutableStateFlow(0)

    /** Writes currently in flight. Zero means idle. */
    val inFlight: StateFlow<Int> = state.asStateFlow()

    /**
     * Run [block] with the counter raised, lowering it however it ends.
     *
     * `finally` rather than a success path: a failed write still has to clear
     * the spinner, or one thrown exception leaves it turning forever.
     */
    suspend fun <T> withLoading(block: suspend () -> T): T {
        state.update { it + 1 }
        try {
            return block()
        } finally {
            // coerceAtLeast mirrors web's `Math.max(0, count - 1)`. It should
            // be unreachable; it is here because a stuck-at-negative counter
            // would silently disable the indicator for the rest of the session.
            state.update { (it - 1).coerceAtLeast(0) }
        }
    }
}
