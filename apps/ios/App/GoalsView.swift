import SwiftUI

/// Ported from apps/web/app/goals/page.tsx per
/// docs/mobile/screen-specs/goals.md. Was a "Goals & Cashflow" combined
/// tab screen fed by dummy data before this pass (2026-08-06, task #25) --
/// no real repository calls, no EF-lock logic, no allocate/edit/delete.
/// The Cashflow tab is removed entirely (invented UI, see the ViewModel's
/// header comment); this is Goals-only now, matching the real web page.
///
/// 2026-08-29: reaching a goal now earns web's celebration
/// (`GoalCelebrationView`), and the English literals this screen had inline --
/// the EF banner, the locked note, "Goal reached!", "Add funds"/"Block funds",
/// the empty state -- are the same `goals` keys web reads.
struct GoalsView: View {
    @State private var showingCreateSheet = false
    @State private var editingGoal: GoalsViewModel.GoalUiModel?
    @State private var allocatingGoal: GoalsViewModel.GoalUiModel?
    @State private var viewModel = GoalsViewModel()

    var body: some View {
        SanvyaPage(S.Goals.title) {
            Button(action: { showingCreateSheet = true }) {
                Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
            }
        } content: {
            Group {
                if viewModel.goals.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            if let ef = viewModel.goals.first(where: { $0.isEmergencyFund }), !ef.funded {
                                Text(S.Goals.efFirst)
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
            .sanvyaFormPresentation(isPresented: $showingCreateSheet) {
                CreateGoalView(viewModel: viewModel)
            }
            .sanvyaFormPresentation(item: $editingGoal) { goal in
                EditGoalView(goal: goal, viewModel: viewModel)
            }
            .sanvyaFormPresentation(item: $allocatingGoal) { goal in
                AllocateGoalView(goal: goal, viewModel: viewModel)
            }
            // Deliberately NOT attached to a row: the celebration is about the
            // goal, not about the card, and a row that scrolls off screen
            // mid-animation must not take the moment with it.
            .fullScreenCover(
                isPresented: Binding(
                    get: { viewModel.celebrating != nil },
                    set: { if !$0 { viewModel.dismissCelebration() } }
                )
            ) {
                if let name = viewModel.celebrating {
                    GoalCelebrationView(name: name) { viewModel.dismissCelebration() }
                        .presentationBackground(.clear)
                }
            }
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.cancel() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(S.Goals.noGoals)
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
            Button(action: { showingCreateSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(S.Goals.createFirst).fontWeight(.semibold)
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
                                    // The separator is web's own " · " between
                                    // the goal name and its tag.
                                    Text("· \(S.Goals.efLiquid)").font(.caption).foregroundColor(Color.text2)
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
                    Text(S.Goals.lockedUntil)
                        .font(.caption)
                        .foregroundColor(Color.text2)
                } else if goal.funded {
                    Text(S.Goals.goalReached)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.accent)
                } else {
                    Button(action: onAllocate) {
                        Text("+ \(goal.isEmergencyFund ? S.Goals.addFunds : S.Goals.blockFunds)")
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
