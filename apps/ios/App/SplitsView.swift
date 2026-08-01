import SwiftUI
import Domain

struct SplitsView: View {
    @State private var selectedTab = 0 // 0: Groups & Trips, 1: Friends
    @State private var showingCreateSheet = false
    @State private var selectedSettleFriend: FriendEdgeUiModel? = nil

    let sampleGroups = [
        SplitGroupUiModel(id: "1", name: "Goa Beach Trip", kind: "trip", memberCount: 4, dateRange: "15 Aug - 20 Aug 2026", netBalanceFormatted: "You are owed ₹2,400", isOwed: true),
        SplitGroupUiModel(id: "2", name: "Flat 302 Roommates", kind: "group", memberCount: 3, dateRange: nil, netBalanceFormatted: "You owe ₹1,150", isOwed: false),
        SplitGroupUiModel(id: "3", name: "Manali Trek 2025", kind: "trip", memberCount: 6, dateRange: "10 Oct - 16 Oct 2025", netBalanceFormatted: "Settled up", isOwed: true)
    ]

    let sampleFriends = [
        FriendEdgeUiModel(id: "1", name: "Rahul Sharma", vpa: "rahul@upi", balanceFormatted: "You owe ₹1,200", isOwed: false),
        FriendEdgeUiModel(id: "2", name: "Ankit Verma", vpa: "ankit@okicici", balanceFormatted: "Owes you ₹850", isOwed: true),
        FriendEdgeUiModel(id: "3", name: "Priya Patel", vpa: "priya@ybl", balanceFormatted: "You owe ₹450", isOwed: false)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Section", selection: $selectedTab) {
                    Text("Groups & Trips").tag(0)
                    Text("Friends").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                ScrollView {
                    if selectedTab == 0 {
                        VStack(spacing: 14) {
                            ForEach(sampleGroups) { grp in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(grp.name)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundColor(Theme.ink)

                                        Text(grp.kind.capitalized)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.clay100)
                                            .cornerRadius(6)

                                        Spacer()

                                        Text("\(grp.memberCount) members")
                                            .font(.caption)
                                            .foregroundColor(Theme.inkSoft)
                                    }

                                    if let dates = grp.dateRange {
                                        Text(dates)
                                            .font(.caption)
                                            .foregroundColor(Theme.inkSoft)
                                    }

                                    Text(grp.netBalanceFormatted)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(grp.isOwed ? Theme.sage : Theme.terracotta)
                                }
                                .padding(18)
                                .background(Theme.cream)
                                .cornerRadius(16)
                            }
                        }
                        .padding(16)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(sampleFriends) { friend in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friend.name)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Theme.ink)

                                        Text(friend.balanceFormatted)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(friend.isOwed ? Theme.sage : Theme.terracotta)
                                    }
                                    Spacer()

                                    if !friend.isOwed {
                                        Button(action: { selectedSettleFriend = friend }) {
                                            Text("Settle Up")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Theme.terracotta)
                                                .foregroundColor(Theme.cream)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Theme.cream)
                                .cornerRadius(12)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Theme.clay50.ignoresSafeArea())
            .navigationTitle("Splits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(Theme.terracotta)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateGroupView()
            }
            .sheet(item: $selectedSettleFriend) { friend in
                PayViaUpiSheet(counterpartyName: friend.name, vpa: friend.vpa ?? "payee@upi", amountMinor: 120000)
            }
        }
    }
}

struct SplitGroupUiModel: Identifiable {
    let id: String
    let name: String
    let kind: String
    let memberCount: Int
    let dateRange: String?
    let netBalanceFormatted: String
    let isOwed: Bool
}

struct FriendEdgeUiModel: Identifiable {
    let id: String
    let name: String
    let vpa: String?
    let balanceFormatted: String
    let isOwed: Bool
}

#Preview {
    SplitsView()
}
