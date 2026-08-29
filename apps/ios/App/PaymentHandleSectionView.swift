import Data
import Domain
import SwiftUI

/**
 "Your UPI ID" — the Settings form's section.

 Ports `apps/web/src/payments/PaymentHandlePanel.tsx`. The heading and the intro
 paragraph are the section's header and footer, which is exactly the `<strong>`
 + muted `<p>` web opens its `<section>` with; what is inside is everything
 underneath.

 Deliberately honest about the security tier, which is also why the disclosure
 log is part of this section rather than a screen of its own: unlike the
 passphrase-protected personal fields, this value is readable by our server — it
 has to be, because the point of it is handing it to someone who owes you money.
 Web's copy says so and lists exactly who has fetched it; so does this.

 Not to be confused with "Pay anyone", which was struck from the product on
 2026-08-29 (docs/mobile/ABSENT-BY-DECISION.md). This section is about saving
 and disclosing your OWN handle, and it stays.

 Mirrors Android's PaymentHandlePanel.kt.
 */
struct PaymentHandleSection: View {

    @State private var viewModel = PaymentHandleViewModel()
    @State private var value = ""
    @State private var showLog = false

    /// Web's `normalized` / `looksValid` / `canSubmit`, computed on every render
    /// exactly as they are there. An empty box is not an error, it is just empty.
    private var normalized: String { normalizeVpa(value) }
    private var looksValid: Bool { normalized.isEmpty || isValidVpa(normalized) }
    private var canSubmit: Bool { !viewModel.busy && !normalized.isEmpty && isValidVpa(normalized) }

    var body: some View {
        Section(header: Text(S.Payments.settingsTitle), footer: Text(S.Payments.settingsIntro)) {
            // One Group, so the `.task` below keeps its identity as the section
            // switches branches and the disclosure subscription is not torn
            // down and stood back up every time something changes.
            Group {
                if viewModel.loading {
                    // Never render the empty form — or the guest refusal —
                    // before we know. Flashing "add a UPI ID" at someone who has
                    // one reads as though it was lost (web's own comment);
                    // flashing "create an account" at an account holder reads
                    // worse, and web is only spared that by a localStorage
                    // session cache the phone has no equivalent of.
                    ProgressView()
                } else if !viewModel.canSave {
                    Text(S.Payments.settingsGuestBlocked)
                        .font(.footnote)
                        .foregroundStyle(Color.text2)
                } else {
                    savedHandle
                    editor
                    privacyAndLog
                }
            }
            .task { await viewModel.start() }
        }
    }

    // MARK: - The handle already saved

    @ViewBuilder
    private var savedHandle: some View {
        if let hint = viewModel.hint {
            VStack(alignment: .leading, spacing: 4) {
                Text(S.Payments.settingsCurrent).font(.caption).foregroundStyle(Color.text2)
                HStack(spacing: 10) {
                    // Monospaced because web renders the mask in a <code>: the
                    // dots and the handle then line up between the saved value
                    // and the "others will see" preview below it.
                    Text(hint)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.text)
                    Spacer(minLength: 8)
                    Button(S.Payments.settingsRemove) {
                        Task { await viewModel.forget() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.busy)
                }
            }
        }
    }

    // MARK: - The form

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.hint != nil ? S.Payments.settingsReplace : S.Payments.settingsLabel)
                .font(.caption)
                .foregroundStyle(Color.text2)
            // Web sets `inputMode="email"` and turns autocomplete,
            // autocapitalisation and spellcheck off. A VPA is `name@bank`, so
            // the email keyboard puts "@" on the first row; the repository
            // lower-cases on the way out either way, but a capitalised first
            // letter in the box would still look wrong to the person typing it.
            TextField(S.Payments.settingsPlaceholder, text: $value)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }

        if !looksValid {
            Text(S.Payments.settingsInvalid).font(.caption).foregroundStyle(Color.negative)
        }
        if !normalized.isEmpty && looksValid {
            Text(S.Payments.settingsWillShow(masked: maskVpa(normalized)))
                .font(.caption)
                .foregroundStyle(Color.text2)
        }

        // The server's own words, verbatim — see PaymentHandleViewModel.
        if let error = viewModel.error {
            Text(error).font(.footnote).foregroundStyle(Color.negative)
        }

        HStack(spacing: 8) {
            Button {
                Task {
                    // Web clears the box inside the same `try` that saved it, so
                    // a failed save keeps what the user typed.
                    if await viewModel.save(normalizedVpa: normalized) { value = "" }
                }
            } label: {
                Text(viewModel.hint != nil ? S.Payments.settingsUpdate : S.Payments.settingsSave)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            // Web puts a Spinner inside the button beside the unchanged label.
            // A `ProgressView` inside a `.borderedProminent` button is tinted
            // by the button's own style and disappears into the fill, so it
            // sits beside it instead.
            if viewModel.busy { ProgressView() }
        }
    }

    // MARK: - The honest bit, and who has looked

    @ViewBuilder
    private var privacyAndLog: some View {
        Text(S.Payments.settingsPrivacy).font(.caption2).foregroundStyle(Color.text2)

        if !viewModel.disclosures.isEmpty {
            Button(
                showLog
                    ? S.Payments.settingsHideLog
                    : S.Payments.settingsShowLog(count: String(viewModel.disclosures.count))
            ) {
                showLog.toggle()
            }
            .buttonStyle(.bordered)
            .font(.caption)

            if showLog {
                ForEach(viewModel.disclosures) { disclosure in
                    HStack(spacing: 6) {
                        // Nil when neither profile table knows this viewer —
                        // named HERE, in the user's language, rather than in
                        // `Data`.
                        Text(disclosure.viewerName ?? S.Payments.settingsSomeone)
                        // Web's `{" · "}` separator. A middot is punctuation,
                        // not copy -- it is the same glyph in all three locales,
                        // so it stays a literal rather than becoming a key.
                        Text(midDot)
                        // Web formats `created_at` with the device's locale in
                        // the device's time zone; `isoLabel` reads the date part
                        // as the civil date the database wrote, which is what
                        // every other timestamp label in this app does. Agreeing
                        // with the rest of the app beats agreeing with the
                        // browser on the one day a disclosure lands either side
                        // of local midnight.
                        Text(isoLabel(disclosure.createdAtIso, "d MMM yy"))
                    }
                    .font(.caption)
                    .foregroundStyle(Color.text2)
                }
            }
        }
    }
}

/// Web's `{" · "}` between a viewer and the date they looked.
private let midDot = "\u{00B7}"
