import SwiftUI
import Domain

/// Create / edit a recurring income or payment.
///
/// Ported from `apps/web/src/cashflow/RecurringModal.tsx`. Mirrors
/// `apps/android/.../ui/recurring/RecurringFormScreen.kt` field for field. This
/// is what the "+" on the Recurring screens now opens — until this existed,
/// both platforms were deliberately without one.
///
/// Presented via `.sanvyaFormPresentation`, so W2.1's rule applies for free: a
/// full-screen cover below 600pt, a dialog at 600pt and up.
///
/// **Recurring SAVINGS are not created here**, matching web: a SIP is a
/// transfer into an investment account and is set up in Investments, next to
/// the holding it funds.
///
/// **Absent, recorded in ABSENT-BY-DECISION.md:**
/// - **Preset name chips** ("Salary", "Rent", …). They only fill the name
///   field, so they are pure convenience, and web's own list is hardcoded
///   English — porting it would put untranslated strings in a screen that is
///   otherwise fully localised.
///
/// **Alert time is no longer in that list.** It shipped as a hardcoded null,
/// which is not "absent by decision" — the column is what the engine reads to
/// decide when to nudge, so every item created here was quietly unremindable.
struct RecurringFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RecurringFormViewModel

    init(slug: RecurringDirectionSlug, editingId: String? = nil) {
        _viewModel = State(initialValue: RecurringFormViewModel(slug: slug, editingId: editingId))
    }

    private var isPayment: Bool { viewModel.slug == .expense }

    /// Web's own heading: "Add recurring payment" / "Edit recurring income",
    /// assembled from modalAdd/modalEdit and dirLabel. Not the direction
    /// screen's "Payments" — a form titled the same as the list behind it reads
    /// as the list.
    private var title: String {
        let what = isPayment ? S.Cashflow.dirLabelPayment : S.Cashflow.dirLabelIncome
        return viewModel.editingId == nil
            ? S.Cashflow.modalAdd(what: what)
            : S.Cashflow.modalEdit(what: what)
    }

    var body: some View {
        ScrollView {
            SanvyaPage(title) {
                fields
                autoPostRow
                if let error = viewModel.error {
                    Text(error)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttons
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var fields: some View {
        field(S.Cashflow.name) {
            SanvyaInput(text: $viewModel.name)
                .disabled(viewModel.busy)
        }

        // "Amount (INR)" — web's FloatingInput carries the base currency in its
        // label, which is the only place the form says which currency the
        // number is in.
        field(S.Cashflow.amountCur(base: baseCurrencyNow())) {
            SanvyaInput(text: $viewModel.amount, placeholder: S.Cashflow.amount)
                .keyboardType(.decimalPad)
                .disabled(viewModel.busy)
        }

        // Account — chips, not a Picker. This codebase draws every
        // one-of-a-few choice as chips; a wheel here would be the only one.
        field(isPayment ? S.Cashflow.payFrom : S.Cashflow.depositInto) {
            if viewModel.accounts.isEmpty {
                // Web's disabled placeholder option. Without it an empty chip
                // row is indistinguishable from a row still loading.
                Text(S.Cashflow.selectAccount)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
            }
            chipRow(viewModel.accounts, selected: viewModel.accountId) { viewModel.accountId = $0 }
        }

        // Web attaches a category to payments only; an income category would
        // show up in expense breakdowns.
        if isPayment {
            field(S.Cashflow.categoryOptional) {
                // Web's first <option> is "No category" with an empty value.
                // Here that is a chip: tapping it clears the choice.
                let none = RecurringFormViewModel.PickerOption(id: "", label: S.Cashflow.noCategory)
                chipRow([none] + viewModel.categories, selected: viewModel.categoryId ?? "") {
                    viewModel.categoryId = $0.isEmpty ? nil : $0
                }
            }
        }

        field(S.Cashflow.frequency) {
            FlowLayout(spacing: 8) {
                ForEach(RecurringFormViewModel.frequencies, id: \.self) { freq in
                    SanvyaChip(frequencyLabel(freq), isActive: viewModel.frequency == freq) {
                        if !viewModel.busy { viewModel.frequency = freq }
                    }
                }
            }
        }

        field(S.Cashflow.firstDue) {
            // Plain ISO text, same as Statements and the same as Android.
            // SwiftUI does have a DatePicker, but adopting it on one platform
            // only would put the two screens out of step for a field the user
            // rarely changes. Tracked.
            SanvyaInput(text: $viewModel.firstDue, placeholder: "YYYY-MM-DD")
                .disabled(viewModel.busy)
        }

        // Web's `<input type="time">`. The wheel, not a text field: "HH:MM"
        // typed free-hand is a validation problem the platform already solves,
        // and the budget forms next door solve it the same way — through the
        // same two converters, so there is one clock conversion in the app.
        field(S.Recurring.alertTime) {
            DatePicker(
                S.Recurring.alertTime,
                selection: Binding(
                    get: { timeStringToDate(viewModel.alertTimeLocal) },
                    set: { viewModel.alertTimeLocal = dateToTimeString($0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .tint(Color.accent)
            .disabled(viewModel.busy)
        }
    }

    /// A checkbox, not a chip: web's control is a checkbox with a consequence
    /// line under it, and the consequence is the half that matters — "off" is
    /// not "nothing happens", it is "we ask you first".
    private var autoPostRow: some View {
        Toggle(isOn: $viewModel.autoPost) {
            VStack(alignment: .leading, spacing: 2) {
                Text(S.Cashflow.postAuto)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(Color.text)
                Text(S.Cashflow.postAutoOff)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Color.accent)
        .disabled(viewModel.busy)
    }

    /// Right-aligned, Cancel then Save — web's own `justify-content: flex-end`
    /// and the platform convention for a primary action.
    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            SanvyaButton(ghost: true) { dismiss() } label: {
                Text(S.Cashflow.cancel)
            }
            .disabled(viewModel.busy)

            SanvyaButton {
                viewModel.save { dismiss() }
            } label: {
                // Web: saving ? "Saving…" : edit ? "Save" : "Add".
                Text(saveLabel)
            }
            .disabled(viewModel.busy || !viewModel.canSave)
        }
    }

    private var saveLabel: String {
        if viewModel.busy { return S.Cashflow.savingEllipsis }
        return viewModel.editingId == nil ? S.Cashflow.add : S.Cashflow.save
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SanvyaEyebrow(label)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipRow(
        _ options: [RecurringFormViewModel.PickerOption],
        selected: String?,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                SanvyaChip(option.label, isActive: option.id == selected) {
                    if !viewModel.busy { onSelect(option.id) }
                }
            }
        }
    }

    private func frequencyLabel(_ freq: String) -> String {
        switch freq {
        case "daily": return S.Cashflow.freqDaily
        case "weekly": return S.Cashflow.freqWeekly
        case "yearly": return S.Cashflow.freqYearly
        default: return S.Cashflow.freqMonthly
        }
    }
}
