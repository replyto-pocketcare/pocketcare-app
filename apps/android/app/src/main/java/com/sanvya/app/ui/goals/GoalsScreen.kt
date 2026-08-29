package com.sanvya.app.ui.goals

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.components.SanvyaPage
import kotlin.math.roundToInt

/**
 * Ported from apps/web/app/goals/page.tsx per
 * docs/mobile/screen-specs/goals.md. Was completely unbuilt before this
 * pass (2026-08-06, task #25) -- GoalsViewModel.kt existed but no Screen
 * consumed it and no nav route reached it (drawer routed to a
 * "coming_soon/Goals" placeholder).
 *
 * Web's create form is an inline card at the bottom of the same page, and
 * editing happens in-place within a goal's own card -- this uses separate
 * Create/EditGoalScreen routes instead, matching this app's own
 * established Accounts/Transactions/Budgets pattern (translate the logic,
 * not the exact widget shape).
 *
 * 2026-08-29: reaching a goal now earns web's celebration
 * (`GoalCelebration`), and the English literals this screen had inline --
 * the EF banner, the locked note, "Goal reached!", "Add funds"/"Block
 * funds", the empty state -- are the same `goals` keys web reads.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalsScreen(
    onBack: () -> Unit = {},
    onAddGoal: () -> Unit = {},
    onEditGoal: (String) -> Unit = {},
    viewModel: GoalsViewModel = viewModel(),
) {
    val goals by viewModel.goals.collectAsState()
    val celebrating by viewModel.celebrating.collectAsState()
    val colors = LocalSanvyaColors.current
    // Holds just the id (Bundle-savable), not the GoalUiModel itself (a
    // plain data class isn't directly saveable) -- resolved back to the
    // live model from `goals` below, so the allocate dialog stays open
    // with the right goal across a configuration change. See
    // docs/plans/native-mobile-apps.md's R1 / LIFE-2, retrofitted
    // 2026-08-06 (P3.19).
    var allocatingGoalId by rememberSaveable { mutableStateOf<String?>(null) }
    val allocatingGoal = goals.find { it.id == allocatingGoalId }

    SanvyaPage(
        title = S.Goals.title(sRes()),
        action = {
            IconButton(onClick = onAddGoal) {
                Icon(Icons.Default.Add, contentDescription = S.Goals.newGoal(sRes()), tint = colors.accent)
            }
        },
    ) {
        if (goals.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        S.Goals.noGoals(sRes()),
                        fontSize = 14.sp,
                        color = colors.text2,
                        textAlign = TextAlign.Center,
                    )
                    Button(onClick = onAddGoal, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(S.Goals.createFirst(sRes()))
                    }
                }
            }
        } else {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                val ef = goals.firstOrNull { it.isEmergencyFund }
                if (ef != null && !ef.funded) {
                    Card(colors = CardDefaults.cardColors(containerColor = colors.accent.copy(alpha = 0.12f)), shape = RoundedCornerShape(SanvyaRadius.radius)) {
                        Text(
                            S.Goals.efFirst(sRes()),
                            modifier = Modifier.padding(14.dp),
                            fontSize = 13.sp,
                            color = colors.text,
                        )
                    }
                }
                goals.forEach { goal ->
                    GoalRowCard(
                        goal = goal,
                        onClick = { onEditGoal(goal.id) },
                        onAllocate = { allocatingGoalId = goal.id },
                    )
                }
            }
        }
    }

    allocatingGoal?.let { goal ->
        AllocateGoalDialog(goal = goal, viewModel = viewModel, onDismiss = { allocatingGoalId = null })
    }

    // Deliberately OUTSIDE the list: the celebration is about the goal, not
    // about the row, and a row that scrolls off screen mid-animation must not
    // take the moment with it.
    celebrating?.let { name ->
        GoalCelebration(name = name, onDismiss = { viewModel.dismissCelebration() })
    }
}

@Composable
private fun GoalRowCard(goal: GoalUiModel, onClick: () -> Unit, onAllocate: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val tint = if (goal.isEmergencyFund) colors.positive else colors.accent
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).alpha(if (goal.locked) 0.55f else 1f),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(goal.name, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    if (goal.funded) {
                        Icon(Icons.Default.CheckCircle, contentDescription = null, tint = colors.accent, modifier = Modifier.size(14.dp))
                        Text(S.Goals.funded(sRes()), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
                    } else if (goal.isEmergencyFund) {
                        // The separator is web's own " · " between the goal
                        // name and its tag.
                        Text("· ${S.Goals.efLiquid(sRes())}", fontSize = 12.sp, color = colors.text2)
                    }
                }
                Text("${(goal.progress * 100).roundToInt()}%", fontSize = 12.sp, color = colors.text2)
            }
            Text("${goal.savedFormatted} / ${goal.targetFormatted}", fontSize = 13.sp, color = colors.text2)
            Box(
                modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)).background(colors.border),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(fraction = goal.progress.coerceIn(0.0, 1.0).toFloat())
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(50))
                        .background(tint),
                )
            }
            when {
                goal.locked -> Text(S.Goals.lockedUntil(sRes()), fontSize = 12.sp, color = colors.text2)
                goal.funded -> Text(S.Goals.goalReached(sRes()), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
                else -> TextButton(onClick = onAllocate) {
                    Text(
                        "+ ${if (goal.isEmergencyFund) S.Goals.addFunds(sRes()) else S.Goals.blockFunds(sRes())}",
                        color = colors.accent,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 13.sp,
                    )
                }
            }
        }
    }
}
