package care.pocket.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

data class CreditCardUiModel(
    val id: String,
    val cardName: String,
    val bankNetwork: String,
    val last4: String,
    val outstandingFormatted: String,
    val availableLimitFormatted: String,
    val dueDate: String,
    val gradientColors: List<Color>
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreditCardsScreen(
    onPayCardClick: (CreditCardUiModel) -> Unit = {}
) {
    val sampleCards = remember {
        listOf(
            CreditCardUiModel(
                id = "1",
                cardName = "HDFC Regalia Gold",
                bankNetwork = "HDFC Bank • Visa",
                last4 = "4821",
                outstandingFormatted = "₹28,450",
                availableLimitFormatted = "₹2,71,550",
                dueDate = "15 Aug 2026",
                gradientColors = listOf(Color(0xFF2C3E50), Color(0xFF1A252F))
            ),
            CreditCardUiModel(
                id = "2",
                cardName = "ICICI Amazon Pay",
                bankNetwork = "ICICI Bank • RuPay",
                last4 = "9102",
                outstandingFormatted = "₹6,120",
                availableLimitFormatted = "₹1,43,880",
                dueDate = "22 Aug 2026",
                gradientColors = listOf(Terracotta, Color(0xFF7A3E29))
            )
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Credit Cards", fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            items(sampleCards) { card ->
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // CSS CreditCard face mirror
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp)
                            .clip(RoundedCornerShape(18.dp))
                            .background(Brush.linearGradient(card.gradientColors))
                            .padding(20.dp)
                    ) {
                        Column(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(card.bankNetwork, fontWeight = FontWeight.Bold, fontSize = 14.sp, color = Color.White)
                                Text(")))", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.8f))
                            }

                            // EMV Chip Icon
                            Surface(
                                modifier = Modifier.size(width = 40.dp, height = 30.dp),
                                shape = RoundedCornerShape(6.dp),
                                color = Color(0xFFE8D4A8)
                            ) {}

                            Text(
                                "••••  ••••  ••••  ${card.last4}",
                                fontSize = 18.sp,
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.Bottom
                            ) {
                                Column {
                                    Text("CARD HOLDER", fontSize = 9.sp, color = Color.White.copy(alpha = 0.7f), fontWeight = FontWeight.Bold)
                                    Text(card.cardName, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    Text("DUE DATE", fontSize = 9.sp, color = Color.White.copy(alpha = 0.7f), fontWeight = FontWeight.Bold)
                                    Text(card.dueDate, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
                                }
                            }
                        }
                    }

                    // Card statement & payoff bar
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text("Outstanding: ${card.outstandingFormatted}", fontWeight = FontWeight.Bold, fontSize = 15.sp, color = Terracotta)
                                Spacer(modifier = Modifier.height(2.dp))
                                Text("Available limit: ${card.availableLimitFormatted}", fontSize = 12.sp, color = InkSoft)
                            }

                            Button(
                                onClick = { onPayCardClick(card) },
                                shape = RoundedCornerShape(10.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
                            ) {
                                Text("Pay Bill", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Cream)
                            }
                        }
                    }
                }
            }
        }
    }
}
