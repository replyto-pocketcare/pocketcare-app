package com.sanvya.app.ui.shell

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.sanvya.app.data.repository.WriteActivity
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.LocalSanvyaShadows
import com.sanvya.app.ui.components.sanvyaShadow
import com.sanvya.app.ui.components.Spinner

/**
 * The corner spinner shown while any synced-row write is in flight -- web's
 * `GlobalLoader`, which `AppShell.tsx` renders once for the whole app.
 *
 * It is deliberately NOT a blocking overlay. Web's is 24px in the top-right
 * corner and the page stays usable underneath, because these writes go to a
 * local database first and sync afterwards: blocking the UI for a write that
 * has already effectively succeeded would make the app feel slower than it is.
 * (`BlockingLoader` in ui/components exists for the opposite case -- a
 * foreground operation the user must wait out -- and is a different control.)
 *
 * Reads [WriteActivity], which the three helpers in WriteHelpers.kt maintain.
 *
 * Mirrors iOS's WriteIndicatorView.swift.
 */
@Composable
fun BoxScope.WriteIndicator() {
    val inFlight by WriteActivity.inFlight.collectAsState()
    AnimatedVisibility(
        visible = inFlight > 0,
        enter = fadeIn(),
        exit = fadeOut(),
        modifier = Modifier
            .align(Alignment.TopEnd)
            .padding(WindowInsets.statusBars.asPaddingValues())
            .padding(16.dp),
    ) {
        val colors = LocalSanvyaColors.current
        Box(
            modifier = Modifier
                .sanvyaShadow(LocalSanvyaShadows.current.shadow, CircleShape)
                .clip(CircleShape)
                .background(colors.surface)
                .padding(6.dp),
        ) {
            Spinner(size = 24.dp)
        }
    }
}
