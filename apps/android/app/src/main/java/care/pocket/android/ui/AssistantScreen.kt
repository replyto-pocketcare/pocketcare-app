package care.pocket.android.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

data class ChatMessageUiModel(
    val id: String,
    val text: String,
    val isUser: Boolean,
    val timeFormatted: String,
    val richInsight: RichInsightUiModel? = null
)

data class RichInsightUiModel(
    val title: String,
    val mainStat: String,
    val subtitle: String,
    val isPositive: Boolean
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssistantScreen(
    onDismiss: () -> Unit = {}
) {
    var inputText by remember { mutableStateOf("") }
    var isRecording by remember { mutableStateOf(false) }

    val messages = remember {
        mutableStateListOf(
            ChatMessageUiModel(
                id = "1",
                text = "Hello! I'm your PocketCare AI financial assistant. Ask me anything about your spending, splits, budgets, or net worth.",
                isUser = false,
                timeFormatted = "10:14 AM"
            ),
            ChatMessageUiModel(
                id = "2",
                text = "How much did I spend on dining out this month?",
                isUser = true,
                timeFormatted = "10:15 AM"
            ),
            ChatMessageUiModel(
                id = "3",
                text = "You've spent ₹6,400 on Food & Dining in July 2026 across 14 transactions. That's 80% of your ₹8,000 monthly dining budget.",
                isUser = false,
                timeFormatted = "10:15 AM",
                richInsight = RichInsightUiModel(
                    title = "Monthly Dining Budget Status",
                    mainStat = "₹6,400 / ₹8,000",
                    subtitle = "80% used • 5 days remaining in period",
                    isPositive = true
                )
            )
        )
    }

    val quickPrompts = listOf(
        "Who owes me money?",
        "Show my net worth",
        "Am I over budget on groceries?",
        "Upcoming bill dates"
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("✨ PocketCare AI Assistant", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    }
                },
                navigationIcon = {
                    TextButton(onClick = onDismiss) {
                        Text("Close", color = InkSoft)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                items(messages) { msg ->
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = if (msg.isUser) Alignment.End else Alignment.Start
                    ) {
                        Surface(
                            shape = RoundedCornerShape(
                                topStart = 16.dp,
                                topEnd = 16.dp,
                                bottomStart = if (msg.isUser) 16.dp else 4.dp,
                                bottomEnd = if (msg.isUser) 4.dp else 16.dp
                            ),
                            color = if (msg.isUser) Terracotta else MaterialTheme.colorScheme.surface,
                            modifier = Modifier.widthIn(max = 280.dp)
                        ) {
                            Column(modifier = Modifier.padding(14.dp)) {
                                Text(
                                    msg.text,
                                    fontSize = 14.sp,
                                    color = if (msg.isUser) Cream else MaterialTheme.colorScheme.onSurface
                                )

                                msg.richInsight?.let { insight ->
                                    Spacer(modifier = Modifier.height(10.dp))
                                    Card(
                                        shape = RoundedCornerShape(10.dp),
                                        colors = CardDefaults.cardColors(containerColor = Clay100)
                                    ) {
                                        Column(modifier = Modifier.padding(10.dp)) {
                                            Text(insight.title, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = InkSoft)
                                            Spacer(modifier = Modifier.height(2.dp))
                                            Text(insight.mainStat, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Terracotta)
                                            Spacer(modifier = Modifier.height(2.dp))
                                            Text(insight.subtitle, fontSize = 11.sp, color = Ink)
                                        }
                                    }
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(2.dp))
                        Text(msg.timeFormatted, fontSize = 10.sp, color = InkSoft)
                    }
                }
            }

            // Quick Prompts row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                quickPrompts.take(2).forEach { prompt ->
                    SuggestionChip(
                        onClick = {
                            inputText = prompt
                        },
                        label = { Text(prompt, fontSize = 11.sp) }
                    )
                }
            }

            // Composer bar with MicButton
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.surface,
                shadowElevation = 8.dp
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // Mic Button
                    IconButton(
                        onClick = { isRecording = !isRecording },
                        modifier = Modifier
                            .size(40.dp)
                            .background(if (isRecording) Terracotta else Clay100, CircleShape)
                    ) {
                        Text(if (isRecording) "⏹" else "🎙", fontSize = 18.sp)
                    }

                    OutlinedTextField(
                        value = inputText,
                        onValueChange = { inputText = it },
                        placeholder = { Text("Ask PocketCare AI…", fontSize = 13.sp) },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                        shape = RoundedCornerShape(20.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Terracotta,
                            unfocusedBorderColor = Clay200
                        )
                    )

                    Button(
                        onClick = {
                            if (inputText.isNotBlank()) {
                                messages.add(
                                    ChatMessageUiModel(
                                        id = System.currentTimeMillis().toString(),
                                        text = inputText,
                                        isUser = true,
                                        timeFormatted = "Just now"
                                    )
                                )
                                inputText = ""
                            }
                        },
                        shape = CircleShape,
                        contentPadding = PaddingValues(0.dp),
                        modifier = Modifier.size(40.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
                    ) {
                        Text("➔", color = Cream, fontSize = 16.sp)
                    }
                }
            }
        }
    }
}
