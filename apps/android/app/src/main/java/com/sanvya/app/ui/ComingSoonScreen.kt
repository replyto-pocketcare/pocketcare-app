package com.sanvya.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.sanvya.app.theme.LocalSanvyaColors

/**
 * Shared placeholder for drawer destinations with no real screen yet --
 * mirrors iOS's `PlaceholderView` in `PlaceholderViews.swift` exactly
 * (same "this feature is coming soon" copy), so a tap on an unbuilt drawer
 * item behaves identically on both platforms instead of doing nothing or
 * crashing. Swapped for the real screen as each one is built
 * (docs/mobile/TODO.md tracks each drawer item).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ComingSoonScreen(title: String) {
    val colors = LocalSanvyaColors.current
    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold, color = colors.text) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("This feature is coming soon.", fontSize = 14.sp, color = colors.text2)
        }
    }
}
