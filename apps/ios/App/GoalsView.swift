import SwiftUI

struct GoalUiItem: Identifiable {
    let id: String
    let name: String
    let currentFormatted: String
    let targetFormatted: String
    let targetDate: String
    let progress: Double
}

struct CashflowUiItem: Identifiable {
    let id: String
    let title: String
    let amountFormatted: String
    let expectedDate: String
    let isIncome: Bool
    let status: String
}

struct GoalsView: View {
    @Binding var isDrawerOpen: Bool
    @State private var selectedTab = 0 // 0: Goals, 1: Cashflow
    @State private var showingCreateSheet = false

    @State private var viewModel = GoalsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Section", selection: $selectedTab) {
                    Text("Goals").tag(0)
                    Text("Cashflow").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                ScrollView {
                    if selectedTab == 0 {
                        VStack(spacing: 14) {
                            ForEach(viewModel.goals) { goal in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(goal.name)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.text)
                                        Spacer()
                                        Text("Target: \(goal.targetDate)")
                                            .font(.caption)
                                            .foregroundColor(Color.text2)
                                    }

                                    ProgressView(value: min(Double(goal.progress), 1.0))
                                        .tint(Color.accent)
                                        .scaleEffect(x: 1, y: 1.5, anchor: .center)
                                        .padding(.vertical, 4)

                                    HStack {
                                        Text("Saved: \(goal.currentFormatted)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Color.positive)
                                        Spacer()
                                        Text("Goal: \(goal.targetFormatted)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Color.text)
                                    }
                                }
                                .padding(18)
                                .background(Color.surface)
                                .cornerRadius(16)
                            }
                        }
                        .padding(16)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.cashflows) { cf in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(cf.title)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Color.text)
                                        Text("Expected: \(cf.expectedDate)")
                                            .font(.caption)
                                            .foregroundColor(Color.text2)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(cf.amountFormatted)
                                            .font(.body)
                                            .fontWeight(.bold)
                                            .foregroundColor(cf.isIncome ? Color.positive : Color.accent)

                                        Text(cf.status.capitalized)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(cf.status == "completed" ? Color.positive.opacity(0.3) : Color.surface2)
                                            .cornerRadius(6)
                                    }
                                }
                                .padding(16)
                                .background(Color.surface)
                                .cornerRadius(12)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Goals & Cashflow")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring()) {
                            isDrawerOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(Color.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateGoalView()
            }
        }
    }
}

#Preview {
    GoalsView(isDrawerOpen: .constant(false))
}
