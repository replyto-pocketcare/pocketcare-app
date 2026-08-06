package com.sanvya.app.ui

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver

/**
 * Shared `rememberSaveable` [Saver] for `List<String>` form state (category-
 * id / label-name multi-selects). `rememberSaveable`'s default/auto saver
 * only whitelists a fixed set of directly-Bundleable types, and a plain
 * Kotlin `List<String>` from `listOf(...)` doesn't reliably qualify (it's
 * not an `ArrayList`) -- so selection state built with a bare
 * `remember { mutableStateOf(listOf<String>()) }` silently resets on any
 * configuration change (fold/unfold, rotation), the exact class of bug
 * this file exists to close (see docs/plans/native-mobile-apps.md's R1 /
 * LIFE-1..2, retrofitted onto Budgets/Goals 2026-08-06 -- P3.19).
 *
 * `listSaver` stores/restores as a plain `List<String>`, which Compose's
 * Bundle-backed registry can hold directly.
 */
val StringListSaver: Saver<List<String>, Any> = listSaver(
    save = { list: List<String> -> list },
    restore = { saved: List<String> -> saved },
)
