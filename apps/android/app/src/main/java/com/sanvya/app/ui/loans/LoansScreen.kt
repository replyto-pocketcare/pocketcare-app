package com.sanvya.app.ui.loans

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.ui.components.SanvyaPage

/**
 * Ported from apps/web/app/loans/page.tsx per
 * docs/mobile/screen-specs/loans.md (task #27). Was completely unbuilt
 * before this pass (2026-08-06) -- LoansViewModel.kt existed but was dead
 * code (constructor-injected, no consuming Screen, no nav route,
 * nonsense "Day N" next-due placeholder text -- see UiModels.kt's old
 * header comment), same "reported DONE, actually never real" pattern
 * already found and fixed for Budgets/Goals/Investments.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoansScreen(
    onBack: () -> Unit = {},
    onAddLoan: () -> Unit = {},
    onOpenLoan: (String) -> Unit = {},
    viewModel: LoansViewModel = viewModel(),
) {
    val loans by viewModel.loans.collectAsState()
    val totalEmi by viewModel.totalEmiFormatted.collectAsState()
    val colors = LocalSanvyaColors.current

    SanvyaPage(
        title = S.Loans.title(sRes()),
        action = {
            IconButton(onClick = onAddLoan) {
                Icon(Icons.Default.Add, contentDescription = "New loan", tint = colors.accent)
            }
        },
    ) {
        if (loans.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("≈", fontSize = 26.sp)
                    Text(S.Loans.noLoansTitle(sRes()), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(
                        "Track EMIs, interest, and payoff progress for any loan.",
                        fontSize = 14.sp,
                        color = colors.text2,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                    Button(onClick = onAddLoan, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Add first loan")
                    }
                }
            }
        } else {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = colors.surface),
                    shape = RoundedCornerShape(SanvyaRadius.radiusLg),
                ) {
                    Row(
                        modifier = Modifier.padding(20.dp).fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        Column {
                            Text(S.Loans.totalEmisMonth(sRes()), fontSize = 13.sp, color = colors.text2)
                            Text(totalEmi, fontSize = 28.sp, fontWeight = FontWeight.Bold, color = colors.text)
                        }
                        Text("${loans.size} loan${if (loans.size == 1) "" else "s"}", fontSize = 13.sp, color = colors.text2)
                    }
                }

                loans.forEach { loan ->
                    LoanRowCard(loan = loan, onClick = { onOpenLoan(loan.id) })
                }
            }
        }
    }
}

@Composable
private fun LoanRowCard(loan: LoanUiModel, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
                Text(loan.lender, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.text)
                Box(
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(if (loan.active) colors.positive.copy(alpha = 0.15f) else colors.border)
                        .padding(horizontal = 9.dp, vertical = 3.dp),
                ) {
                    Text(if (loan.active) S.Loans.active(sRes()) else S.Loans.closed(sRes()), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = if (loan.active) colors.positive else colors.text2)
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(loan.rangeOrRate, fontSize = 12.sp, color = colors.text2)
                Text(loan.paidCountText, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
            }
            if (loan.hasTenure) {
                Box(modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)).background(colors.border)) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(fraction = loan.progress.coerceIn(0.0, 1.0).toFloat())
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(50))
                            .background(if (loan.active) colors.accent else colors.positive),
                    )
                }
            }
            HorizontalDivider()
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text(S.Loans.loanAmount(sRes()), fontSize = 11.sp, color = colors.text2)
                    Text(loan.principalFormatted, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(S.Loans.emiAmount(sRes()), fontSize = 11.sp, color = colors.text2)
                    Text(loan.emiFormatted, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                }
            }
        }
    }
}
