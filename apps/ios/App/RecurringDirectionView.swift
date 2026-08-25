import SwiftUI
import Domain

/// One side of the recurring picture: Income or Expense.
///
/// Ported from `apps/web/app/recurring/[direction]/page.tsx`. This is what made
/// the direction rows on the Recurring screen tappable — until now they were
/// deliberately inert because there was nowhere for them to go.
///
/// **Absent, and recorded in ABSENT-BY-DECISION.md:**
/// - **The category donut.** Both platforms already have a `DonutChart`, but
///   each is `private` inside its Insights screen; sharing one is a refactor of
///   two working screens, not part of this port. The chips below carry the
///   names and the percentages — the information — and web's own comment calls
///   a single-slice donut "decoration, not information".
/// - ~~Add and Edit~~ — **built 2026-08-25** (`RecurringFormView`).
/// - **The shell's contextual "+".** Web registers this screen's Add into the
///   bottom bar via `useRegisterAddAction`. Both native shells have the
///   mechanism (`AddAction`) but no screen registers into it, and iOS's
///   `.button` case is `break` — a no-op. Until that channel is wired, Add is
///   an in-page button here, which is what Android already does.
struct RecurringDirectionView: View {
    let slug: RecurringDirectionSlug
    var onBack: () -> Void

    @State private var viewModel: RecurringDirectionViewModel
    @State private var confirmingRemoval: String?
    @State private var adding = false
    @State private var editing: EditTarget?

    /// `.sanvyaFormPresentation(item:)` needs an `Identifiable`, and a bare
    /// `String` is not one.
    private struct EditTarget: Identifiable { let id: String }

    init(slug: RecurringDirectionSlug, onBack: @escaping () -> Void) {
        self.slug = slug
        self.onBack = onBack
        _viewModel = State(initialValue: RecurringDirectionViewModel(slug: slug))
    }

    private var isIncome: Bool { slug == .income }
    private var tint: Color { isIncome ? Color.positive : Color.negative }
    private var sign: String { isIncome ? "+" : "−" }

    var body: some View {
        ScrollView {
            SanvyaPage(isIncome ? S.Recurring.incomes : S.Recurring.payments) {
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        Text(S.Translation.commonBack).foregroundStyle(Color.text2)
                    }
                    SanvyaButton { adding = true } label: {
                        Text(S.Recurring.add)
                    }
                }
            } content: {
                summaryCard
                if viewModel.items.isEmpty {
                    Text(isIncome ? S.Recurring.emptyIncome : S.Recurring.emptyPayment)
                        .sanvyaStyle(SanvyaType.body)
                        .foregroundStyle(Color.text2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(viewModel.items) { item in itemCard(item) }
                }
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { viewModel.start() }
        .sanvyaFormPresentation(isPresented: $adding) {
            RecurringFormView(slug: slug)
        }
        .sanvyaFormPresentation(item: $editing) { target in
            RecurringFormView(slug: slug, editingId: target.id)
        }
        // Removal is confirmed, matching web. It is a soft delete and therefore
        // recoverable in the database, but not by the user from this screen.
        .alert(
            S.Recurring.removeTitle,
            isPresented: Binding(
                get: { confirmingRemoval != nil },
                set: { if !$0 { confirmingRemoval = nil } }
            )
        ) {
            Button(S.Recurring.cancel, role: .cancel) { confirmingRemoval = nil }
            Button(S.Recurring.remove, role: .destructive) {
                if let id = confirmingRemoval { viewModel.remove(id: id) }
                confirmingRemoval = nil
            }
        } message: {
            Text(removalName)
        }
    }

    private var removalName: String {
        viewModel.items.first { $0.id == confirmingRemoval }?.name ?? ""
    }

    private var summaryCard: some View {
        SanvyaCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    SanvyaEyebrow(S.Recurring.perMonthLabel)
                    Text(sign + viewModel.monthlyFormatted)
                        .sanvyaStyle(SanvyaType.statValue)
                        .foregroundStyle(tint)
                }
                // Web only draws the mix once there is more than one slice; a
                // single chip restating the total above it is noise.
                if viewModel.categories.count > 1 {
                    categoryChips
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var categoryChips: some View {
        // A wrapping row of chips. `FlowLayout` does not exist below iOS 16's
        // Layout protocol in a form this codebase already uses, so this is a
        // plain wrap via a fixed-ish grid: chips are short, and the alternative
        // is a horizontal scroller that hides slices off-screen.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.categories) { slice in
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorForId(slice.id))
                        .frame(width: 9, height: 9)
                    Text(slice.isUncategorised ? S.Cashflow.noCategory : slice.name)
                        .sanvyaStyle(SanvyaType.chip)
                        .foregroundStyle(Color.text)
                    Text("\(slice.sharePct)%")
                        .sanvyaStyle(SanvyaType.chip)
                        .foregroundStyle(Color.text2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.surface2)
                .clipShape(Capsule())
            }
        }
    }

    private func itemCard(_ item: RecurringDirectionViewModel.ItemUiModel) -> some View {
        SanvyaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.text)
                            .lineLimit(1)
                        Text(item.subtitle)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(sign + item.amountFormatted)
                        .sanvyaStyle(SanvyaType.body)
                        .foregroundStyle(tint)
                }
                // Three plain buttons rather than web's kebab menu: hiding
                // three actions behind a third tap is worse than showing them
                // on a card that has room.
                HStack(spacing: 8) {
                    SanvyaButton(ghost: true) { editing = EditTarget(id: item.id) } label: {
                        Text(S.Recurring.edit)
                    }
                    SanvyaButton(ghost: true) { viewModel.recordNow(id: item.id) } label: {
                        Text(S.Recurring.postNow)
                    }
                    SanvyaButton(ghost: true) { confirmingRemoval = item.id } label: {
                        Text(S.Recurring.remove)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
