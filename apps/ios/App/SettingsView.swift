import SwiftUI
import UIKit
import Domain
import Data
import Factory
import Observation

/// Local-only device prefs -- mirrors apps/web/src/prefs.ts/theme.ts's
/// localStorage-backed useAmountsHidden/useTheme/useBaseCurrency (same key
/// names, same defaults). NOT synced (matches web: device preferences, not
/// ledger data). Persisted via UserDefaults, mirroring Android's Prefs.kt
/// SharedPreferences pattern -- previously `amountsHidden` was in-memory
/// only here (lost on relaunch); this pass fixes that while adding
/// theme/baseCurrency alongside it.
@MainActor
class Prefs: ObservableObject {
    static let shared = Prefs()

    private let defaults = UserDefaults.standard
    /// `nonisolated` and internal, not private: MoneyFormat.swift reads these
    /// keys from contexts with no actor at all, so the hide-amounts rule can be
    /// honoured everywhere. The class is `@MainActor` for its `@Published`
    /// state; these two are immutable `String` constants and carry none of it.
    /// One key, one meaning.
    nonisolated static let hideKey = "amountsHidden"
    private static let themeKey = "theme"
    /// Same reasoning as `hideKey`.
    nonisolated static let currencyKey = "baseCurrency"

    @Published var amountsHidden: Bool {
        didSet { defaults.set(amountsHidden, forKey: Prefs.hideKey) }
    }
    @Published var theme: String {
        didSet { defaults.set(theme, forKey: Prefs.themeKey) }
    }
    @Published var baseCurrency: String {
        didSet { defaults.set(baseCurrency, forKey: Prefs.currencyKey) }
    }

    private init() {
        amountsHidden = defaults.bool(forKey: Prefs.hideKey)
        theme = defaults.string(forKey: Prefs.themeKey) ?? "light"
        baseCurrency = defaults.string(forKey: Prefs.currencyKey) ?? FormOptions.defaultCurrency
    }
}

private let currencies = FormOptions.currencies
private let genders: [(String, String)] = FormOptions.genders.map { ($0.value, $0.label) }
private let countries = FormOptions.countries

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var prefs = Prefs.shared

    @State private var viewModel = SettingsViewModel()

    @State private var username = ""
    @State private var confirmSignout = false
    @State private var confirmDelete = false
    @State private var confirmReplay = false
    @State private var replayOpen = false
    /// A guest taking the way out of the deletion warning. `AppShell` owns the
    /// same cover for its guest chips, but this one is presented FROM this
    /// screen, so this screen has to present it.
    @State private var showingLogin = false
    @State private var expandedLog = false
    @State private var profileGenderSel = ""
    @State private var profileCountrySel = ""

    /// Set by the sync-problems banner before it switches tabs; consumed once
    /// the Problems section has actually been laid out. See
    /// Shell/SettingsSectionRequest.swift.
    @StateObject private var sectionRequest = SettingsSectionRequest.shared

    var body: some View {
        NavigationStack {
            // Wraps the Form so the sync-problems banner can jump straight to
            // the panel it is about -- web's `/settings#problems`.
            ScrollViewReader { proxy in
                Form {
                    // MARK: Account
                    Section(header: Text(S.Settings.account)) {
                        if viewModel.session?.isGuest == true {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(guestWarning)
                                    .font(.footnote)
                                // The way out of the warning. Both phones printed
                                // the deadline and then offered nothing to do about
                                // it; web has had this button since the card
                                // existed.
                                Button(S.Settings.createToKeep) { showingLogin = true }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color.accent)
                            }
                        } else {
                            Text("\(S.Settings.signedInAs) \(viewModel.session?.email ?? "—")")
                                .font(.footnote)
                                .foregroundColor(Color.text2)
                        }

                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.syncConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(viewModel.syncConnected ? "Synced" + (viewModel.syncLastSyncedAt.map { " · last \($0)" } ?? "") : "Not connected")
                                .font(.caption)
                                .foregroundColor(Color.text2)
                        }

                        HStack {
                            TextField(S.Settings.yourName, text: $username)
                            Button(viewModel.usernameSaved ? S.Settings.saved : S.Settings.save) { viewModel.saveUsername(username) }
                        }
                    }

                    // MARK: Appearance
                    Section(header: Text(S.Settings.appearance)) {
                        Picker("Theme", selection: $prefs.theme) {
                            Text(S.Settings.light).tag("light")
                            Text(S.Settings.dark).tag("dark")
                        }
                        .pickerStyle(.segmented)
                    }

                    // MARK: Privacy
                    Section(header: Text(S.Settings.privacy), footer: Text("Mask balances and transaction amounts across the app.")) {
                        Toggle("Hide Amounts", isOn: $prefs.amountsHidden)
                            .tint(Color.accent)
                    }

                    // MARK: About you
                    Section(header: Text("About you"), footer: Text("Optional. Helps us tailor offers and beta invites. Private.")) {
                        Picker("Gender", selection: $profileGenderSel) {
                            ForEach(genders, id: \.0) { v, label in Text(label).tag(v) }
                        }
                        Picker("Country", selection: $profileCountrySel) {
                            ForEach(countries, id: \.self) { c in Text(c.isEmpty ? "Not specified" : c).tag(c) }
                        }
                        HStack {
                            Button(S.Settings.save) { viewModel.saveProfile(gender: profileGenderSel, country: profileCountrySel) }
                            if let msg = viewModel.profileMsg {
                                Text(msg).font(.footnote).foregroundColor(Color.text2)
                            }
                        }
                    }

                    // MARK: Notifications
                    //
                    // The push row used to be a plain Toggle that wrote
                    // `push_enabled` and nothing else: no permission ask, no APNs
                    // token, no way to send a test. It was a switch that turned on
                    // a lie. Ported properly from web's NotificationPanel.tsx,
                    // whose hints and test button come with it.
                    if let notif = viewModel.notifPrefs {
                        Section(header: Text(S.Translation.navNotifications), footer: Text("Get alerted about bills, budgets, low balances and unusual spend.")) {
                            let state = pushState(
                                supported: true,
                                permission: viewModel.pushPermission,
                                prefEnabled: notif.push_enabled == 1
                            )
                            if state == .unsupported {
                                Text("This device can't show notifications. In-app alerts still work.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.text2)
                            } else {
                                Toggle(isOn: Binding(
                                    get: { state == .on },
                                    set: { on in
                                        if on { viewModel.enablePush() } else { viewModel.disablePush() }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(viewModel.pushBusy ? "Working\u{2026}" : "Push notifications")
                                        // `.blocked` is not `.off`: once iOS has
                                        // been told no, the prompt can never be
                                        // shown again, so a live switch here would
                                        // be a control that can never do anything.
                                        // The hint sends them to Settings instead.
                                        Text(state == .blocked
                                             ? "Blocked in iOS Settings \u{203A} Notifications"
                                             : "Deliver alerts to this device")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.text2)
                                    }
                                }
                                .tint(Color.accent)
                                .disabled(viewModel.pushBusy || state == .blocked)

                                if let message = viewModel.pushMessage {
                                    Text(message)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Color.text2)
                                }

                                Button("Send test notification") { viewModel.sendTestNotification() }
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.accent)
                            }

                            notifToggle("Upcoming EMIs & bills",
                                        hint: "Alert \(notif.emi_lead_days) days before due",
                                        on: notif.emi_due == 1, keyPath: \.emi_due)
                            notifToggle("Budget limits",
                                        hint: "When you cross 80% and 100% of a budget",
                                        on: notif.budget == 1, keyPath: \.budget)
                            notifToggle("Low balance",
                                        hint: "When an account drops below your floor",
                                        on: notif.low_balance == 1, keyPath: \.low_balance)
                            notifToggle("Unusual transactions",
                                        hint: "Large or out-of-pattern spends",
                                        on: notif.outlier == 1, keyPath: \.outlier)
                            notifToggle("Group activity",
                                        hint: "When someone joins a group or trip you're in",
                                        on: notif.group_invite == 1, keyPath: \.group_invite)
                            notifToggle("Shared expenses",
                                        hint: "When someone adds an expense to split",
                                        on: notif.group_expense == 1, keyPath: \.group_expense)
                        }
                    }

                    // MARK: Security & encryption
                    //
                    // Web renders <SecurityPanel /> here, between
                    // NotificationPanel and the base-currency section, and the
                    // order is the order: this section is about the same thing
                    // the notification one is (what leaves this device), and
                    // burying it below Diagnostics would hide the one control
                    // that makes notes unreadable to us.
                    SecurityPanelSection()

                    // MARK: Base currency
                    Section(header: Text(S.Settings.baseCurrency), footer: Text("Used as the default across new accounts and reports.")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(currencies, id: \.self) { c in
                                    Button(c) { prefs.baseCurrency = c }
                                        .buttonStyle(.bordered)
                                        .tint(c == prefs.baseCurrency ? Color.accent : Color.text2)
                                }
                            }
                        }
                    }

                    // MARK: Categories & labels
                    //
                    // Web's `#categories` section. Neither native Settings screen
                    // had it, so both taxonomy screens were unreachable even once
                    // they existed. `NavigationLink`, because this Form is already
                    // inside a NavigationStack — a sheet would put a second
                    // dismissal gesture on a screen that is a drill-down, not a task.
                    Section(header: Text(S.Settings.catsLabels), footer: Text(S.Settings.catsLabelsDesc)) {
                        NavigationLink(S.Settings.manageCategories) { CategoriesView() }
                        NavigationLink(S.Settings.manageLabels) { LabelsView() }
                    }

                    // MARK: Import & export
                    //
                    // Web's `#data` section. Neither native Settings screen had it,
                    // so the screen was unreachable even once it existed.
                    Section(header: Text(S.Data.title), footer: Text(S.Data.introPre)) {
                        NavigationLink(S.Data.exportBtn) { DataView() }
                    }

                    // MARK: Plan & billing
                    Section(header: Text("Plan & Billing")) {
                        Text("You're on the \(viewModel.entitlement.tier.capitalized) plan.")
                            .font(.subheadline)
                            .foregroundColor(Color.text2)
                        Button(action: { /* No native in-app-purchase flow yet -- see settings.md */ }) {
                            Text(viewModel.entitlement.isPaid ? "Manage Plan" : "Upgrade to Premium")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // MARK: Problems syncing (dead-letter queue; hidden when empty)
                    if !viewModel.failedWrites.isEmpty {
                        Section(
                            header: Text("Problems syncing"),
                            footer: Text("\(viewModel.failedWrites.count) change\(viewModel.failedWrites.count == 1 ? "" : "s") couldn't be saved to the server. Still on this device — nothing has been lost.")
                        ) {
                            ForEach(viewModel.failedWrites, id: \.id) { item in
                                FailedWriteRow(item: item, viewModel: viewModel)
                            }
                            Button(viewModel.problemsBusy == "all" ? "Trying…" : "Try all \(viewModel.failedWrites.count) again") {
                                viewModel.retryAllFailedWrites()
                            }.disabled(viewModel.problemsBusy != nil)
                            // Android has had both halves of this since the
                            // dead-letter queue shipped; iOS had neither, so the
                            // only way off this screen with your data was "Discard".
                            // A change that never reached the server is on this
                            // device and nowhere else — being able to take a copy
                            // of it is the difference between a queue you can clear
                            // and one you have to lose.
                            Button("Copy a copy of everything") {
                                UIPasteboard.general.string = viewModel.exportFailedWritesJson()
                            }
                        }
                        // The anchor the sync-problems banner scrolls to -- web's
                        // `id="problems"`, which its `/settings#problems` link lands
                        // on.
                        .id(SettingsSection.problems)
                    }

                    // MARK: Check for unsynced data
                    Section(header: Text("Check for unsynced data"), footer: Text("Compares this device against the server and re-uploads anything that never made it. Safe to run any time.")) {
                        RepairSectionView(viewModel: viewModel)
                    }

                    // MARK: Diagnostics
                    Section(
                        header: Text("Diagnostics"),
                        footer: Text("If something isn't working, share this with support. Amounts, names and contact details are removed automatically.")
                    ) {
                        HStack {
                            DiagStat(label: "Status", value: viewModel.syncConnected ? "Connected" : "Not connected")
                            DiagStat(label: "Waiting", value: viewModel.queueDepth.map { String($0) } ?? "—", warn: (viewModel.queueDepth ?? 0) > 0)
                            DiagStat(label: "Errors", value: String(viewModel.diagnosticsEntries.filter { $0.level == "error" }.count), warn: viewModel.diagnosticsEntries.contains { $0.level == "error" })
                        }

                        let stuck = viewModel.queueOps.filter { $0.orphaned }
                        if !stuck.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(stuck.count) change\(stuck.count == 1 ? "" : "s") can't be saved")
                                    .font(.subheadline).bold()
                                Text("These refer to something that no longer exists, so they'll never upload — and they're blocking everything queued behind them.")
                                    .font(.caption)
                                Button(viewModel.discardingStuck ? "Working…" : "Discard \(stuck.count) stuck change\(stuck.count == 1 ? "" : "s")") {
                                    viewModel.discardStuck()
                                }.disabled(viewModel.discardingStuck)
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }

                        HStack {
                            Button("Share diagnostics") { shareDiagnostics() }
                            Button(expandedLog ? "Hide log" : "Show log (\(viewModel.diagnosticsEntries.count))") { expandedLog.toggle() }
                        }
                        if expandedLog {
                            let logText = viewModel.diagnosticsEntries.isEmpty
                                ? "Nothing logged yet — that's a good sign."
                                : viewModel.diagnosticsEntries.reversed().map { "\($0.level.uppercased()) [\($0.scope)] \($0.message)" }.joined(separator: "\n")
                            Text(logText).font(.system(size: 11, design: .monospaced))
                        }
                    }

                    // MARK: Help & support
                    Section(header: Text(S.Settings.help)) {
                        Button(S.Settings.contactSupport) {
                            if let url = URL(string: "mailto:support@sanvya.app") { UIApplication.shared.open(url) }
                        }
                        // Web's "Replay the intro". Four translated strings for it
                        // have existed in the catalogue since the deck was ported
                        // and nothing rendered any of them.
                        Button(S.Settings.replayIntro) { confirmReplay = true }
                        Text(S.Settings.helpNote)
                            .font(.caption)
                            .foregroundStyle(Color.text2)
                    }

                    // MARK: Sign out / delete
                    Section {
                        HStack {
                            Spacer()
                            Button(S.Settings.signoutTitle) { confirmSignout = true }
                            Spacer()
                            Button(S.Settings.deleteAccount) { confirmDelete = true }
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
                .navigationTitle(S.Settings.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(S.Translation.commonClose) { dismiss() }.foregroundColor(Color.text2)
                    }
                }
                .background(Color.bg)
                .scrollContentBackground(.hidden)
                .task {
                    await viewModel.start()
                    // Re-read on every entry: the user can revoke notifications
                    // from iOS Settings while the app is backgrounded, and a stale
                    // "on" switch would be the last thing they see before wondering
                    // why nothing arrives.
                    await viewModel.refreshPushPermission()
                }
                .onChange(of: viewModel.session?.username) { _, newValue in
                    if let newValue, username.isEmpty { username = newValue }
                }
                .onChange(of: viewModel.usernameSaved) { _, saved in
                    if saved {
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            viewModel.clearUsernameSaved()
                        }
                    }
                }
                .onChange(of: viewModel.profileGender) { _, v in profileGenderSel = v }
                .onChange(of: viewModel.profileCountry) { _, v in profileCountrySel = v }
                .alert(S.Settings.signoutTitle, isPresented: $confirmSignout) {
                    Button(S.Settings.cancel, role: .cancel) {}
                    // Web puts "Create account" beside Cancel for a guest, and it is
                    // the whole point of the warning below it: signing out as a
                    // guest is a delete, so the dialog has to offer the one action
                    // that prevents it.
                    if viewModel.session?.isGuest == true {
                        Button(S.Settings.createAccount) { showingLogin = true }
                    }
                    Button(S.Settings.signOutAnyway, role: .destructive) { viewModel.signOut() }
                } message: {
                    Text(viewModel.session?.isGuest == true
                        ? S.Settings.guestSignoutWarn
                        : S.Settings.signoutRestore)
                }
                .alert(S.Settings.deleteAccount, isPresented: $confirmDelete) {
                    Button(S.Settings.cancel, role: .cancel) {}
                    Button(viewModel.deleting ? S.Settings.deleting : S.Settings.deleteEverything, role: .destructive) { viewModel.deleteAccount() }
                        .disabled(viewModel.deleting)
                } message: {
                    Text(S.Settings.deleteBody + (viewModel.deleteError.map { "\n\($0)" } ?? ""))
                }
                // `danger: false` on web -- replaying the intro destroys nothing --
                // so no destructive role here either.
                .alert(S.Settings.replayTitle, isPresented: $confirmReplay) {
                    Button(S.Settings.cancel, role: .cancel) {}
                    Button(S.Settings.replayConfirm) { replayOpen = true }
                } message: {
                    Text(S.Settings.replayMsg)
                }
                /*
                 The deck itself, shown here rather than by clearing `onboardingSeen`
                 and signing out.

                 Web can do it the other way round because `signOut()` ends in
                 `window.location.href = "/onboarding"` — a full reload, after which
                 the auth gate re-reads localStorage and the deck is what a
                 signed-out visitor meets. Neither phone reloads: both gates read
                 that flag ONCE, into `@State` / `rememberSaveable` at launch
                 (SanvyaApp.swift, MainActivity.kt), so clearing it afterwards
                 changes nothing until the next cold start and the user would be
                 dropped on the login form having been promised the welcome screens.

                 So the deck is presented and the sign-out happens on the way OUT of
                 it, on whichever of its three exits is taken. The screens the user
                 sees, and the state they end in — signed out, at the login form —
                 are web's.
                 */
                .fullScreenCover(isPresented: $replayOpen) {
                    OnboardingDeckView(onDone: {
                        replayOpen = false
                        viewModel.signOut()
                    })
                }
                // The banner set a section before switching tabs; honour it once the
                // panel it points at has actually been laid out. `failedWrites`
                // starts empty and is filled by `start()` above, so the panel always
                // appears AFTER this screen does — which is why `onAppear` alone
                // would never find it.
                .onAppear { scrollToPendingSection(proxy) }
                .onChange(of: viewModel.failedWrites.count) { _, _ in scrollToPendingSection(proxy) }
                // A request that could not be honoured -- the failed writes cleared
                // before the screen appeared -- dies with the screen rather than
                // waiting to surprise the next visit.
                .onDisappear { sectionRequest.consume() }
            }
        }
        // Attached to the NavigationStack, not to the Form alongside the deck's
        // cover: two `.fullScreenCover` modifiers on the SAME view is the SwiftUI
        // trap where only one of them ever presents.
        .fullScreenCover(isPresented: $showingLogin) { LoginView() }
    }

    /// Web's four fragments in web's order: the lead-in, the bolded word
    /// "guest", the full stop, then the countdown -- omitted entirely when the
    /// sign-up date could not be read, rather than guessed at. There is no
    /// inline bold inside a `Text` built this way, so the three fragments join
    /// into one sentence; the emphasis is the only thing lost and the deadline
    /// is the half that does the work.
    private var guestWarning: String {
        var text = S.Settings.guestPre + S.Settings.guestBold + S.Settings.guestDot
        if let days = viewModel.session?.daysLeft {
            text += " " + S.Settings.guestDelete(count: days)
        }
        return text
    }

    /// Jump to the panel the sync-problems banner is about.
    ///
    /// Consumes the request FIRST so the two callers cannot both act on it, then
    /// scrolls one runloop turn later: `scrollTo` cannot find an id the Form has
    /// not laid out yet, and the change that inserts the section is still being
    /// applied when `onChange` runs.
    private func scrollToPendingSection(_ proxy: ScrollViewProxy) {
        guard sectionRequest.pending == .problems, !viewModel.failedWrites.isEmpty else { return }
        sectionRequest.consume()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation { proxy.scrollTo(SettingsSection.problems, anchor: .top) }
        }
    }

    /// One notification toggle with its explanatory line.
    ///
    /// Web has a hint on every row and iOS had none, which turned "Upcoming
    /// EMIs & bills" into a switch whose meaning you had to guess -- the lead
    /// time it actually uses was invisible.
    @ViewBuilder
    private func notifToggle(
        _ title: String,
        hint: String,
        on: Bool,
        keyPath: WritableKeyPath<NotificationPrefs, Int>
    ) -> some View {
        Toggle(isOn: Binding(
            get: { on },
            set: { viewModel.updatePref(keyPath: keyPath, value: $0) }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.text2)
            }
        }
        .tint(Color.accent)
    }

    private func shareDiagnostics() {
        let text = viewModel.diagnosticsShareText()
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }
}

private struct DiagStat: View {
    let label: String
    let value: String
    var warn: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(Color.text2)
            Text(value).font(.subheadline).bold()
        }
        .padding(8)
        .background(warn ? Color.red.opacity(0.12) : Color.gray.opacity(0.1))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FailedWriteRow: View {
    let item: FailedWriteItem
    let viewModel: SettingsViewModel
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label).font(.subheadline).bold()
            Text(item.explanation).font(.caption)
            HStack(spacing: 8) {
                Button(viewModel.problemsBusy == item.id ? "Trying…" : "Try again") { viewModel.retryFailedWrite(item) }
                    .disabled(viewModel.problemsBusy != nil)
                // Per row, so one stuck change can be rescued without copying
                // the whole queue. Mirrors Android's FailedWriteRow exactly,
                // including the label — the strings in this whole diagnostics
                // section are still untranslated on BOTH platforms, and
                // translating two buttons inside an English section would read
                // as a bug rather than as progress.
                Button("Copy") {
                    UIPasteboard.general.string = viewModel.exportFailedWritesJson([item])
                }
                if confirming {
                    Button("Copy & discard") { viewModel.discardFailedWrite(item) }
                        .foregroundColor(.red)
                        .disabled(viewModel.problemsBusy != nil)
                } else {
                    Button("Discard") { confirming = true }
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private struct RepairSectionView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        switch viewModel.repairStage {
        case "idle":
            Button("Check now") { viewModel.scanForStranded() }
        case "scanning":
            HStack { ProgressView(); Text("Comparing this device with the server…").font(.subheadline) }
        case "clean":
            VStack(alignment: .leading, spacing: 6) {
                Text("Everything is synced.").font(.subheadline).bold()
                if !viewModel.repairUnchecked.isEmpty {
                    Text("Couldn't check: \(viewModel.repairUnchecked.joined(separator: ", ")).").font(.caption).foregroundColor(Color.text2)
                }
                Button("Check again") { viewModel.resetRepair() }
            }
        case "found":
            VStack(alignment: .leading, spacing: 6) {
                Text("\(viewModel.strandedRows.count) item\(viewModel.strandedRows.count == 1 ? "" : "s") never reached the server").font(.subheadline).bold()
                Text("They're safe here but aren't backed up. Save a copy, then upload them.").font(.caption)
                HStack {
                    Button("Copy a copy") { UIPasteboard.general.string = viewModel.exportStrandedJson() }
                    Button("Upload \(viewModel.strandedRows.count) item\(viewModel.strandedRows.count == 1 ? "" : "s")") { viewModel.repairStrandedNow() }
                }
            }
        case "repairing":
            HStack { ProgressView(); Text("Uploading…").font(.subheadline) }
        case "done":
            VStack(alignment: .leading, spacing: 6) {
                Text("Uploaded \(viewModel.repairUploaded) item\(viewModel.repairUploaded == 1 ? "" : "s").").font(.subheadline).bold()
                if !viewModel.repairFailed.isEmpty {
                    Text("\(viewModel.repairFailed.count) still couldn't be uploaded.").font(.caption).foregroundColor(.red)
                }
                Button("Check again") { viewModel.resetRepair() }
            }
        default:
            Button("Try again") { viewModel.resetRepair() }
        }
    }
}
