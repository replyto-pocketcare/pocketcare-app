package com.sanvya.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.sanvya.app.theme.SanvyaMetrics

/**
 * The shape every top-level screen shares.
 *
 * Web gives each page a heading and its primary action on one row, then the
 * content below — and, crucially, **no title bar**. There is no `TopAppBar`
 * anywhere in web's phone layout: the util row is the top of the page, and the
 * heading is page content.
 *
 * Native screens were each wrapping themselves in a `Scaffold` with a
 * `TopAppBar`, which put system chrome above the shell's own. This is the
 * replacement, so the fix is one component rather than fourteen improvisations.
 *
 * ```kotlin
 * SanvyaPage("Budgets", action = { SanvyaButton(onClick = { … }) { … } }) {
 *     …
 * }
 * ```
 */
@Composable
fun SanvyaPage(
    title: String,
    modifier: Modifier = Modifier,
    action: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(SanvyaMetrics.PageHeader.sectionGap),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(SanvyaMetrics.PageHeader.headerGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // An empty title renders no heading at all rather than an empty
            // one — a screen holding a drill-down in local state clears its
            // title on the way in, and an empty H1 would still reserve a line.
            //
            // `compact = true` is web's own choice, not a native concession:
            // globals.css drops h1 to 22px below 860px, and that is the size a
            // phone actually renders.
            if (title.isNotEmpty()) H1(title, compact = true)
            Spacer(modifier = Modifier.weight(1f))
            action()
        }
        content()
    }
}
