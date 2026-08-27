import SwiftUI
import Data
import Domain

/// First-run walkthrough — ported from apps/web/src/onboarding/Walkthrough.tsx.
///
/// Written for a specific person: a 60+ user who signed up, landed on the
/// dashboard, did not know what to do, and believed "add an account" meant
/// linking their real bank. They stopped there. Three rules follow, and every
/// step obeys them:
///
/// 1. **Say what the app IS, first** — not what to tap. "It is not connected to
///    your bank" is the single most important sentence in this file.
/// 2. **Manual entry is the product, not an apology.**
/// 3. **Do not send them to the real form.** `/accounts/new` offers Savings /
///    Current / Credit card / Demat, which reads as bank onboarding. Step 2
///    asks for a name and a number and defaults the rest.
///
/// Part A (1–4) is setup and ends in a real Finish. Part B (5–7) is opt-in:
/// making onboarding LONGER would be the wrong answer to "I found this
/// overwhelming".
///
/// This replaces a half-built version that was in the repo but wired to
/// nothing, quoted three of its paragraphs as inline English, and had no
/// account or spend creation at all.
struct WalkthroughView: View {
    let onFinish: () -> Void
    let onSkip: () -> Void
    let onNavigateToLogin: () -> Void
    let onNavigateToPlans: () -> Void

    @State private var viewModel = WalkthroughViewModel()

    /// No `NavigationStack`, no `ScrollView`, no background: this is the PANEL
    /// of `.sanvyaModal`, which is the design system's port of web's `Modal`
    /// (centred card, 440pt cap, 24pt padding, its own scroll when the content
    /// is taller than the screen). Adding any of them here would double the
    /// padding and the scrolling.
    var body: some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 18) {
            header
            switch viewModel.step {
            case 1: intro
            case 2: account(vm: $vm)
            case 3: spend(vm: $vm)
            case 4: done
            case 5: insights
            case 6: ask
            default: last
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Chrome

    private var progress: WalkthroughProgress { walkthroughProgress(viewModel.step) }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            SanvyaIconView(stepIcon, size: 24, tint: Color.accent)
                .frame(width: 42, height: 42)
                .background(Color.accentGhost, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 0)
            Text(S.Onboarding.wtProgress(step: progress.step, of: progress.of))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.text2)
        }
    }

    private var stepIcon: String {
        switch viewModel.step {
        case 1: SanvyaIcons.volunteerActivism
        case 2: SanvyaIcons.accountBalance
        case 3: SanvyaIcons.receiptLong
        case 4: SanvyaIcons.check
        case 5: SanvyaIcons.insights
        case 6: SanvyaIcons.autoAwesome
        default: viewModel.isGuest ? SanvyaIcons.person : SanvyaIcons.redeem
        }
    }

    /// Body copy is 15pt, not the app's 12.5–13pt muted default. Web's plan says
    /// why: this is the one screen written for someone who finds the rest small.
    /// Named `copy`, not `body`: a `func body(_:)` alongside `var body: some
    /// View` is legal Swift but reads as a mistake in a `View`.
    private func copy(_ text: String, strong: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 15, weight: strong ? .bold : .regular))
            .foregroundStyle(Color.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(Color.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Stacked, full-width actions — easier to hit, and the primary one is
    /// obvious. Web makes the same choice for the same reason.
    @ViewBuilder
    private func actions(
        primary: String,
        onPrimary: @escaping () -> Void,
        disabled: Bool = false,
        secondary: String? = nil,
        onSecondary: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 10) {
            SanvyaButton(action: onPrimary) {
                Text(primary).frame(maxWidth: .infinity)
            }
            .disabled(disabled)
            if let secondary, let onSecondary {
                Button(secondary, action: onSecondary)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.text2)
                    .frame(minHeight: 44)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.text)
            content()
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let error = viewModel.error {
            Text(error)
                .font(.system(size: 15))
                .foregroundStyle(Color.negative)
        }
    }

    // MARK: - Steps

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(S.Onboarding.wtIntroTitle)
            copy(S.Onboarding.wtIntroP1)
            copy(S.Onboarding.wtIntroP2, strong: true)
            copy(S.Onboarding.wtIntroP3)
            copy(S.Onboarding.wtIntroP4)
            actions(
                primary: S.Onboarding.wtIntroCta, onPrimary: { viewModel.step = 2 },
                secondary: S.Onboarding.wtSkip, onSecondary: onSkip
            )
        }
    }

    @ViewBuilder
    private func account(vm: Bindable<WalkthroughViewModel>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            title(S.Onboarding.wtAccTitle)
            copy(S.Onboarding.wtAccP1)
            copy(S.Onboarding.wtAccP2)
            field(S.Onboarding.wtAccNameLabel) {
                SanvyaInput(
                    text: vm.accountName,
                    placeholder: "\(S.Onboarding.wtAccEg1) · \(S.Onboarding.wtAccEg2)"
                )
            }
            field(S.Onboarding.wtAccBalLabel) {
                VStack(alignment: .leading, spacing: 4) {
                    SanvyaInput(text: vm.accountBalance)
                        .keyboardType(.decimalPad)
                    Text(S.Onboarding.wtAccBalHelp)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text2)
                }
            }
            errorLine
            actions(
                primary: viewModel.busy ? S.Onboarding.wtSaving : S.Onboarding.wtAccCta,
                onPrimary: { viewModel.saveAccount() },
                disabled: viewModel.busy || !viewModel.canSaveAccount,
                secondary: S.Onboarding.wtLater, onSecondary: { viewModel.step = 3 }
            )
        }
    }

    @ViewBuilder
    private func spend(vm: Bindable<WalkthroughViewModel>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            title(S.Onboarding.wtSpendTitle)
            copy(S.Onboarding.wtSpendP1)
            copy(S.Onboarding.wtSpendP2)
            copy(S.Onboarding.wtSpendP3, strong: true)
            field(S.Onboarding.wtSpendWhatLabel) {
                SanvyaInput(text: vm.spendWhat, placeholder: S.Onboarding.wtSpendWhatEg)
            }
            field(S.Onboarding.wtSpendAmountLabel) {
                SanvyaInput(text: vm.spendAmount)
                    .keyboardType(.decimalPad)
            }
            errorLine
            actions(
                primary: viewModel.busy ? S.Onboarding.wtSaving : S.Onboarding.wtSpendCta,
                onPrimary: { viewModel.saveSpend() },
                disabled: viewModel.busy || !viewModel.canSaveSpend,
                secondary: S.Onboarding.wtLater, onSecondary: { viewModel.step = 4 }
            )
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(S.Onboarding.wtDoneTitle)
            where_(SanvyaIcons.spaceDashboard, S.Onboarding.wtDoneDashTitle, S.Onboarding.wtDoneDashBody)
            where_(SanvyaIcons.swapHoriz, S.Onboarding.wtDoneTxnTitle, S.Onboarding.wtDoneTxnBody)
            where_(SanvyaIcons.donutSmall, S.Onboarding.wtDoneBudgetTitle, S.Onboarding.wtDoneBudgetBody)
            Text(S.Onboarding.wtDonePrivacy)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
            actions(
                primary: S.Onboarding.wtDoneCta, onPrimary: onFinish,
                secondary: S.Onboarding.wtDoneMore, onSecondary: { viewModel.step = 5 }
            )
        }
    }

    private var insights: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(S.Onboarding.wtInsightsTitle)
            copy(S.Onboarding.wtInsightsP1)
            SanvyaCard(padding: 12) {
                Text(S.Onboarding.wtInsightsEg)
                    .font(.system(size: 14).italic())
                    .foregroundStyle(Color.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            copy(S.Onboarding.wtInsightsP2)
            actions(
                primary: S.Onboarding.wtNext, onPrimary: { viewModel.step = 6 },
                secondary: S.Onboarding.wtDoneCta, onSecondary: onFinish
            )
        }
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(S.Onboarding.wtAskTitle)
            copy(S.Onboarding.wtAskP1)
            copy(S.Onboarding.wtAskP2)
            Text(S.Onboarding.wtAskPrivacy)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
            actions(
                primary: S.Onboarding.wtNext, onPrimary: { viewModel.step = 7 },
                secondary: S.Onboarding.wtDoneCta, onSecondary: onFinish
            )
        }
    }

    @ViewBuilder
    private var last: some View {
        if viewModel.isGuest {
            VStack(alignment: .leading, spacing: 14) {
                title(S.Onboarding.wtGuestTitle)
                copy(S.Onboarding.wtGuestP1)
                actions(
                    primary: S.Onboarding.wtGuestCta,
                    onPrimary: { onFinish(); onNavigateToLogin() },
                    secondary: S.Onboarding.wtGuestLater, onSecondary: onFinish
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                title(viewModel.onTrial ? S.Onboarding.wtPlanTitleTrial : S.Onboarding.wtPlanTitle)
                if viewModel.onTrial { copy(S.Onboarding.wtPlanTrial) }
                copy(S.Onboarding.wtPlanFree)
                ForEach(FormOptions.plans) { plan in
                    // surface-2, not surface: this card sits INSIDE the modal's
                    // own card, and two identical fills separated by a hairline
                    // read as one block. Web overrides the same token here.
                    SanvyaCard(padding: 14, background: Color.surface2) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(plan.label).font(.system(size: 16, weight: .bold))
                                Spacer(minLength: 10)
                                Text(S.Onboarding.wtPlanPerMonth(amount: plan.monthly))
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(Color.text)
                            Text(S.Onboarding.wtPlanQuota(count: plan.quota))
                                .font(.system(size: 13.5))
                                .foregroundStyle(Color.text2)
                        }
                    }
                }
                actions(
                    primary: S.Onboarding.wtPlanCta, onPrimary: onFinish,
                    secondary: S.Onboarding.wtPlanSee,
                    onSecondary: { onFinish(); onNavigateToPlans() }
                )
            }
        }
    }

    /// "Where to look" row. Trailing underscore because `where` is a keyword.
    private func where_(_ glyph: String, _ heading: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SanvyaIconView(glyph, size: 20, tint: Color.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.text)
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
