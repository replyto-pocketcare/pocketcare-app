import SwiftUI

/// Ported from apps/web/app/goals/page.tsx per
/// docs/mobile/screen-specs/goals.md. Was a "Goals & Cashflow" combined
/// tab screen fed by dummy data before this pass (2026-08-06, task #25) --
/// no real repository calls, no EF-lock logic, no allocate/edit/delete.
/// The Cashflow tab is removed entirely (invented UI, see the ViewModel's
/// header comment); this is Goals-only now, matching the real web page.
struct GoalsView: View {
    @State private var showingCreateSheet = false
    @State private var editingGoal: GoalsViewModel.GoalUiModel?
    @State private var allocatingGoal: GoalsViewModel.GoalUiModel?
    @State private var viewModel = GoalsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.goals.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            if let ef = viewModel.goals.first(where: { $0.isEmergencyFund }), !ef.funded {
                                Text("Fund your emergency fund first — other goals unlock once it's fully funded.")
                                    .font(.subheadline)
                                    .foregroundColor(Color.text)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.accent.opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.3)))
                                    .cornerRadius(12)
                            }
                            ForEach(viewModel.goals) { goal in
                                GoalRowCard(
                                    goal: goal,
                                    onEdit: { editingGoal = goal },
                                    onAllocate: { allocatingGoal = goal }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Goals.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateGoalView(viewModel: viewModel)
            }
            .sheet(item: $editingGoal) { goal in
                EditGoalView(goal: goal, viewModel: viewModel)
            }
            .sheet(item: $allocatingGoal) { goal in
                AllocateGoalView(goal: goal, viewModel: viewModel)
            }
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No goals yet").font(.title3).fontWeight(.bold).foregroundColor(Color.text)
            Text("Set a savings target and start blocking funds toward it.")
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
            Button(action: { showingCreateSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Create first goal").fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.accent)
                .foregroundColor(Color.surface)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GoalRowCard: View {
    let goal: GoalsViewModel.GoalUiModel
    var onEdit: () -> Void
    var onAllocate: () -> Void

    var body: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: onEdit) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(goal.name).font(.headline).fontWeight(.bold).foregroundColor(Color.text)
                                if goal.funded {
                                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundColor(Color.accent)
                                    Text(S.Goals.funded).font(.caption).fontWeight(.semibold).foregroundColor(Color.accent)
                                } else if goal.isEmergencyFund {
                                    Text("· liquid").font(.caption).foregroundColor(Color.text2)
                                }
                            }
                            Text("\(goal.savedFormatted) / \(goal.targetFormatted)")
                                .font(.subheadline)
                                .foregroundColor(Color.text2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(Color.text2)
                    }
                }
                .buttonStyle(.plain)

                ProgressView(value: goal.progress)
                    .tint(goal.isEmergencyFund ? Color.positive : Color.accent)
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
                    .padding(.vertical, 4)
                    .opacity(goal.locked ? 0.55 : 1)

                if goal.locked {
                    Text("Locked until the emergency fund is fully funded")
                        .font(.caption)
                        .foregroundColor(Color.text2)
                } else if goal.funded {
                    Text("Goal reached!")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.accent)
                } else {
                    Button(action: onAllocate) {
                        Text("+ \(goal.isEmergencyFund ? "Add funds" : "Block funds")")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.accent)
                    }
                }
            }
        }
        .opacity(goal.locked ? 0.55 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(goal.funded ? Color.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}

#Preview {
    GoalsView()
}
