import Domain
import SwiftUI
import UIKit

/**
 Send feedback — ported from `apps/web/src/ui/BugReport.tsx`.

 The "Feedback" entry in the More sheet and the side nav was wired to a closure
 that closed the sheet and did nothing else, on BOTH platforms: a visible
 control that lied, and the app's only error-report channel.

 Two things are deliberately not web's:

  * **Every string is translated.** Web's modal is hardcoded English end to end
    — 30-odd strings, in an app that ships in three languages. The catalogue
    entries added for this port are there for web to adopt.
  * **The area picker is a chip grid, not a `<select>`.** Fourteen options in a
    native picker is a wheel; chips show the whole vocabulary at once, which is
    what the web `<select>` effectively does on a desktop.

 What IS web's, exactly: the default-on log toggle, the promise about what is
 captured, the bug/suggestion split (and with it the severity row, which a
 suggestion does not get), and the thank-you screen including the beta-tester
 reward copy.

 Mirrors Android's FeedbackSheet.
 */
struct FeedbackSheet: View {
    let route: String
    let online: Bool
    let onClose: () -> Void

    @State private var viewModel = FeedbackViewModel()

    var body: some View {
        Group {
            if viewModel.done {
                donePanel
            } else {
                form
            }
        }
    }

    // MARK: - form

    private var form: some View {
        @Bindable var vm = viewModel
        return VStack(alignment: .leading, spacing: 12) {
            SanvyaH2(S.Feedback.title)
            SanvyaMuted(S.Feedback.intro, style: SanvyaType.body.resized(12))

            HStack(spacing: 6) {
                SanvyaChip(S.Feedback.kindBug, isActive: viewModel.isBug) {
                    vm.kind = "bug"
                    viewModel.clearError()
                }
                SanvyaChip(S.Feedback.kindSuggestion, isActive: !viewModel.isBug) {
                    vm.kind = "suggestion"
                    viewModel.clearError()
                }
                Spacer(minLength: 0)
            }

            // A suggestion has no severity — web hides the whole row, and the
            // repository writes nil, so the triage queue is not sorted by an
            // urgency nobody chose.
            if viewModel.isBug {
                SanvyaMuted(S.Feedback.severityLabel, style: SanvyaType.body.resized(12))
                chipFlow(feedbackSeverities, selected: viewModel.severity) { severity in
                    vm.severity = severity
                } label: { feedbackLabel(feedbackSeverityKey($0)) }
            }

            SanvyaMuted(S.Feedback.areaLabel, style: SanvyaType.body.resized(12))
            chipFlow(feedbackAreas, selected: viewModel.area) { area in
                // Tapping the chosen one again clears it: web's select has an
                // empty first option and this has no equivalent row to offer.
                vm.area = viewModel.area == area ? "" : area
            } label: { feedbackLabel(feedbackAreaKey($0)) }

            SanvyaInput(text: $vm.title, placeholder: S.Feedback.titlePlaceholder)
            TextField(
                viewModel.isBug ? S.Feedback.bugPlaceholder : S.Feedback.suggestionPlaceholder,
                text: $vm.descriptionText,
                axis: .vertical
            )
            .lineLimit(4...8)
            .sanvyaStyle(SanvyaType.body)
            .foregroundStyle(Color.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: 1)
            }
            .onChange(of: viewModel.descriptionText) { _, _ in viewModel.clearError() }

            Toggle(isOn: $vm.includeLog) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(S.Feedback.includeLog)
                        .sanvyaStyle(SanvyaType.body.resized(13))
                        .foregroundStyle(Color.text)
                    SanvyaMuted(S.Feedback.includeLogHint, style: SanvyaType.body.resized(11))
                }
            }
            .tint(Color.accent)

            SanvyaMuted(S.Feedback.autoIncluded, style: SanvyaType.body.resized(11))

            if let key = viewModel.errorKey {
                Text(feedbackLabel(key))
                    .sanvyaStyle(SanvyaType.body.resized(13))
                    .foregroundStyle(Color.negative)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                SanvyaButton(ghost: true, action: { onClose(); viewModel.reset() }) {
                    Text(S.Feedback.cancel)
                }
                SanvyaButton(action: send) {
                    Text(sendLabel)
                }
                .disabled(!viewModel.canSubmit)
            }
        }
    }

    private var sendLabel: String {
        if viewModel.busy { return S.Feedback.sending }
        return viewModel.isBug ? S.Feedback.sendBug : S.Feedback.sendSuggestion
    }

    private func send() {
        let screen = UIScreen.main.bounds.size
        viewModel.submit(
            route: route,
            // Web stores `navigator.userAgent`; the honest equivalent is the
            // device and OS, which is what that string is read FOR.
            userAgent: "iOS \(UIDevice.current.systemVersion); \(UIDevice.current.model)",
            viewport: "\(Int(screen.width))x\(Int(screen.height))",
            online: online
        )
    }

    // MARK: - done

    /// Web's post-submit panel, reward copy and all.
    private var donePanel: some View {
        VStack(spacing: 10) {
            Text(verbatim: "🙏").font(.system(size: 34))
            SanvyaH2(viewModel.isBug ? S.Feedback.thanksBug : S.Feedback.thanksSuggestion)
            SanvyaMuted(
                viewModel.isBug ? S.Feedback.thanksBugBody : S.Feedback.thanksSuggestionBody,
                style: SanvyaType.body.resized(14)
            )
            .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                SanvyaButton(ghost: true, action: { viewModel.reset() }) {
                    Text(S.Feedback.sendAnother)
                }
                SanvyaButton(action: { onClose(); viewModel.reset() }) {
                    Text(S.Feedback.done)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - chips

    /// A wrapping chip row. `Layout` would be tidier; this is `ViewThatFits`-free
    /// on purpose, because a fixed three-per-row grid is predictable at every
    /// Dynamic Type size and a self-measuring flow is not.
    @ViewBuilder
    private func chipFlow(
        _ options: [String],
        selected: String,
        onTap: @escaping (String) -> Void,
        label: @escaping (String) -> String
    ) -> some View {
        let rows = stride(from: 0, to: options.count, by: 3).map {
            Array(options[$0..<min($0 + 3, options.count)])
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { option in
                        SanvyaChip(label(option), isActive: selected == option) { onTap(option) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /**
     A `feedback` namespace key, resolved.

     The generated `feedbackAreaKey` / `feedbackSeverityKey` return a key rather
     than a string, for the same reason `assistantErrorKey` does: the derivation
     is shared and vector-pinned, the wording is per-locale. This is the one
     place that turns one into the other, and it is exhaustive on purpose — a
     new area in web's list fails here rather than rendering its own key on
     screen.
     */
    private func feedbackLabel(_ key: String) -> String {
        switch key {
        case "sevFatal": return S.Feedback.sevFatal
        case "sevHigh": return S.Feedback.sevHigh
        case "sevMedium": return S.Feedback.sevMedium
        case "sevLow": return S.Feedback.sevLow
        case "areaDashboard": return S.Feedback.areaDashboard
        case "areaTransactions": return S.Feedback.areaTransactions
        case "areaAccountsCards": return S.Feedback.areaAccountsCards
        case "areaBudgets": return S.Feedback.areaBudgets
        case "areaGoals": return S.Feedback.areaGoals
        case "areaInvestments": return S.Feedback.areaInvestments
        case "areaFriendsSplits": return S.Feedback.areaFriendsSplits
        case "areaSubscriptions": return S.Feedback.areaSubscriptions
        case "areaLoans": return S.Feedback.areaLoans
        case "areaAskSanvya": return S.Feedback.areaAskSanvya
        case "areaInsights": return S.Feedback.areaInsights
        case "areaSettingsBilling": return S.Feedback.areaSettingsBilling
        case "areaSyncOffline": return S.Feedback.areaSyncOffline
        case "areaOther": return S.Feedback.areaOther
        case "errNeedBug": return S.Feedback.errNeedBug
        case "errNeedSuggestion": return S.Feedback.errNeedSuggestion
        default: return S.Feedback.errSubmit
        }
    }
}
