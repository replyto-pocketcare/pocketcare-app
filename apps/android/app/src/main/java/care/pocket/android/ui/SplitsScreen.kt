package care.pocket.android.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

data class SplitGroupUiModel(
    val id: String,
    val name: String,
    val kind: String, // "trip" or "group"
    val memberCount: Int,
    val dateRange: String?,
    val netBalanceFormatted: String,
    val isOwed: Boolean
)

data class FriendEdgeUiModel(
    val id: String,
    val name: String,
    val vpa: String?,
    val balanceFormatted: String,
    val isOwed: Boolean
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SplitsScreen(
    onAddGroupClick: () -> Unit = {},
    onSettleUpClick: (FriendEdgeUiModel) -> Unit = {}
) {
    var selectedTab by remember { mutableStateOf(0) } // 0: Groups & Trips, 1: Friends

    val sampleGroups = remember {
        listOf(
            SplitGroupUiModel("1", "Goa Beach Trip", "trip", 4, "15 Aug - 20 Aug 2026", "You are owed ₹2,400", true),
            SplitGroupUiModel("2", "Flat 302 Roommates", "group", 3, null, "You owe ₹1,150", false),
            SplitGroupUiModel("3", "Manali Trek 2025", "trip", 6, "10 Oct - 16 Oct 2025", "Settled up", true)
        )
    }

    val sampleFriends = remember {
        listOf(
            FriendEdgeUiModel("1", "Rahul Sharma", "rahul@upi", "You owe ₹1,200", false),
            FriendEdgeUiModel("2", "Ankit Verma", "ankit@okicici", "Owes you ₹850", true),
            FriendEdgeUiModel("3", "Priya Patel", "priya@ybl", "You owe ₹450", false)
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Splits",
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                },
                actions = {
                    TextButton(onClick = onAddGroupClick) {
                        Text(
                            "+ Group/Trip",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = Terracotta
                        )
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
                .padding(horizontal = 16.dp)
        ) {
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = (selectedTab == 0),
                    onClick = { selectedTab = 0 },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                ) { Text("Groups & Trips") }

                SegmentedButton(
                    selected = (selectedTab == 1),
                    onClick = { selectedTab = 1 },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                ) { Text("Friends") }
            }

            Spacer(modifier = Modifier.height(16.dp))

            if (selectedTab == 0) {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    items(sampleGroups) { grp ->
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(18.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(
                                            grp.name,
                                            fontSize = 16.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Surface(
                                            shape = RoundedCornerShape(6.dp),
                                            color = Clay100
                                        ) {
                                            Text(
                                                grp.kind.replaceFirstChar { it.uppercase() },
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Medium,
                                                color = Ink,
                                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                            )
                                        }
                                    }
                                    Text(
                                        "${grp.memberCount} members",
                                        fontSize = 12.sp,
                                        color = InkSoft
                                    )
                                }

                                grp.dateRange?.let { dates ->
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(dates, fontSize = 12.sp, color = InkSoft)
                                }

                                Spacer(modifier = Modifier.height(12.dp))

                                Text(
                                    grp.netBalanceFormatted,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (grp.isOwed) Sage else Terracotta
                                )
                            }
                        }
                    }
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(sampleFriends) { friend ->
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
                                    Text(
                                        friend.name,
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                    Spacer(modifier = Modifier.height(2.dp))
                                    Text(
                                        friend.balanceFormatted,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (friend.isOwed) Sage else Terracotta
                                    )
                                }

                                if (!friend.isOwed) {
                                    Button(
                                        onClick = { onSettleUpClick(friend) },
                                        shape = RoundedCornerShape(10.dp),
                                        colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
                                    ) {
                                        Text("Settle Up", fontSize = 12.sp, color = Cream)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
