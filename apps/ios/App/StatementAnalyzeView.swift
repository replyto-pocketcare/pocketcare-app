import SwiftUI
import Domain
import Data
import UniformTypeIdentifiers

/// Statement parser and analyzer, on the device.
///
/// Ported from `apps/web/app/statements/analyze/page.tsx`. Pick a bank or
/// credit-card export, parse it locally, categorise the spends, analyse them,
/// reconcile against what is already recorded, and import what is missing.
/// **Nothing leaves the device** — the claim web's header makes, and the reason
/// every step here is Domain plus a repository rather than an endpoint.
///
/// **CSV only.** Web also parses PDFs with pdf.js; iOS could do it with PDFKit
/// in a few lines but Android has no built-in PDF text extraction at all, so
/// shipping it here alone would split the two apps on this screen's headline
/// feature. Recorded in docs/mobile/ABSENT-BY-DECISION.md.
struct StatementAnalyzeView: View {
    @State private var viewModel = StatementAnalyzeViewModel()
    @State private var showImporter = false

    var body: some View {
        ScrollView {
            if let parsed = viewModel.parsed {
                results(parsed)
            } else {
                picker
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(S.StatementsAnalyze.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            // `.plainText` and `.text` alongside `.commaSeparatedText`: plenty
            // of banks hand out a .csv the system types as plain text, and a
            // picker that greys out the file the user came to import is a dead
            // end. Same reasoning as the Data screen's importer.
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { outcome in handlePicked(outcome) }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(S.StatementsAnalyze.introPre + S.StatementsAnalyze.introBold + S.StatementsAnalyze.introMid)
                .font(.system(size: 13))
                .foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)

            SanvyaCard(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    field(S.StatementsAnalyze.statementType) {
                        HStack(spacing: 6) {
                            SanvyaChip(S.StatementsAnalyze.bank, isActive: viewModel.kind == "bank") {
                                viewModel.kind = "bank"
                            }
                            SanvyaChip(S.StatementsAnalyze.card, isActive: viewModel.kind == "card") {
                                viewModel.kind = "card"
                            }
                        }
                    }

                    field(S.StatementsAnalyze.accountToReconcile) {
                        FlowLayout(spacing: 6) {
                            SanvyaChip(S.StatementsAnalyze.chooseLater, isActive: viewModel.accountId.isEmpty) {
                                viewModel.accountId = ""
                                viewModel.accountChanged()
                            }
                            ForEach(viewModel.accounts, id: \.id) { a in
                                SanvyaChip(a.name, isActive: viewModel.accountId == a.id) {
                                    viewModel.accountId = a.id
                                    viewModel.accountChanged()
                                }
                            }
                        }
                    }

                    SanvyaButton { showImporter = true } label: {
                        Text(viewModel.busy ?? S.StatementsAnalyze.chooseFile)
                    }
                    .disabled(viewModel.busy != nil)

                    if let error = viewModel.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.negative)
                    }

                    Text(S.StatementsAnalyze.tipPre + S.StatementsAnalyze.tipBold + S.StatementsAnalyze.tipPost)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.text2)
            content()
        }
    }

    private func handlePicked(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case .failure(let error):
            viewModel.setError(error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            // A document picked from Files is outside the app's sandbox, so it
            // has to be opened inside a security-scoped access window. Without
            // this the read fails with a permission error on a real device and
            // works fine in the simulator, which is the worst kind of bug.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                viewModel.setError(S.StatementsAnalyze.readFail)
                return
            }
            // A bank export is not reliably UTF-8; several Indian banks emit
            // Windows-1252. Falling back keeps a mojibake merchant name rather
            // than refusing the file outright.
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
            guard let text else {
                viewModel.setError(S.StatementsAnalyze.readFail)
                return
            }
            viewModel.parse(
                text: text,
                parsingLabel: S.StatementsAnalyze.parsing,
                categorisingLabel: S.StatementsAnalyze.categorising,
                readFailMessage: S.StatementsAnalyze.readFail
            )
        }
    }

    // MARK: - Results

    private func results(_ parsed: ParsedStatement) -> some View {
        let cur = viewModel.currency
        let summary = summarize(parsed.txns)
        let cats = byCategory(parsed.txns)
        let days = byDay(parsed.txns)
        let flagged = outliers(parsed.txns)
        // Irregular patterns are dropped and the list is capped at six: a
        // "recurring" suggestion the user has to think about is worse than none,
        // and web caps it identically.
        let recurring = Array(recurringCandidates(parsed.txns).filter { $0.cadence != "irregular" }.prefix(6))

        return VStack(alignment: .leading, spacing: 20) {
            header(parsed)
            if !parsed.warnings.isEmpty { warnings(parsed.warnings) }
            stats(parsed, summary, cur)
            if parsed.kind == "card" { cardMeta(parsed, cur) }
            charts(cats, days, cur)
            if !flagged.isEmpty { outlierCard(flagged, cur) }
            if !recurring.isEmpty { recurringCard(recurring, cur) }
            reconcileCard()
            transactionList(parsed, cur)
        }
        .padding(16)
    }

    private func header(_ parsed: ParsedStatement) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(parsed.label)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.text)
                Text(subtitle(parsed))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.text2)
            }
            Spacer(minLength: 0)
            SanvyaButton(ghost: true) { viewModel.reset() } label: {
                Text(S.StatementsAnalyze.newStatement)
            }
        }
    }

    private func subtitle(_ parsed: ParsedStatement) -> String {
        var parts: [String] = []
        if let from = parsed.period.from, let to = parsed.period.to { parts.append("\(from) → \(to)") }
        parts.append(S.StatementsAnalyze.transactions(count: parsed.txns.count))
        if !viewModel.accountName.isEmpty { parts.append(viewModel.accountName) }
        return parts.joined(separator: " · ")
    }

    private func warnings(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items, id: \.self) { w in
                Text("⚠ \(w)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentGhost, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentSoft, lineWidth: 1)
        )
    }

    private func stats(_ parsed: ParsedStatement, _ s: StatementSummary, _ cur: String) -> some View {
        FlowLayout(spacing: 12) {
            stat(S.StatementsAnalyze.moneyIn, formatMoney(s.credits, cur), Color.positive)
            stat(S.StatementsAnalyze.moneyOut, formatMoney(s.debits, cur), Color.negative)
            stat(
                S.StatementsAnalyze.net,
                (s.net >= 0 ? "+" : "−") + formatMoney(abs(s.net), cur),
                s.net >= 0 ? Color.positive : Color.negative
            )
            if let closing = parsed.closingBalance {
                stat(S.StatementsAnalyze.closingBalance, formatMoney(closing, cur), Color.text)
            }
        }
    }

    @ViewBuilder
    private func cardMeta(_ parsed: ParsedStatement, _ cur: String) -> some View {
        // The CSV parser never fills `card`; web only reads it off a PDF header.
        // The section is here so it lights up the day PDF lands, and stays
        // invisible until then rather than showing three empty stats.
        if let card = parsed.card, card.totalDue != nil || card.dueDate != nil {
            SanvyaCard(padding: 18) {
                FlowLayout(spacing: 24) {
                    if let total = card.totalDue { stat(S.StatementsAnalyze.totalDue, formatMoney(total, cur), Color.text) }
                    if let min = card.minDue { stat(S.StatementsAnalyze.minimumDue, formatMoney(min, cur), Color.text) }
                    if let due = card.dueDate { stat(S.StatementsAnalyze.payBy, due, Color.negative) }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        SanvyaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.text2)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private func charts(_ cats: [CategoryTotal], _ days: [DayTotal], _ cur: String) -> some View {
        VStack(spacing: 12) {
            chartCard(S.StatementsAnalyze.whereItWent) {
                if cats.isEmpty {
                    chartEmpty
                } else {
                    // Top seven, matching web. An eighth slice on a phone-width
                    // donut is a sliver with an unreadable label.
                    SanvyaDonutChart(
                        series: cats.prefix(7).enumerated().map { i, c in
                            SeriesPoint(c.name, Double(c.total), FormOptions.chartColors[i % FormOptions.chartColors.count])
                        },
                        centerLabel: formatMoney(cats.reduce(Int64(0)) { $0 + $1.total }, cur),
                        centerSub: nil,
                        accent: Color.accent
                    )
                    .frame(height: 220)
                }
            }
            chartCard(S.StatementsAnalyze.dailySpend) {
                if days.isEmpty {
                    chartEmpty
                } else {
                    SanvyaBarsChart(
                        // Month-day only: a full ISO date under every bar on a
                        // 30-day statement is unreadable. Web slices the same
                        // five characters off.
                        series: days.map { SeriesPoint(String($0.date.dropFirst(5)), Double($0.debit)) },
                        unit: nil,
                        horizontal: false,
                        accent: Color.accent
                    )
                    .frame(height: 220)
                }
            }
        }
    }

    private func chartCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        SanvyaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.text2)
                content()
            }
        }
    }

    private var chartEmpty: some View {
        Text(S.StatementsAnalyze.noSpends)
            .font(.system(size: 13))
            .foregroundStyle(Color.text3)
            .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func outlierCard(_ items: [StatementOutlier], _ cur: String) -> some View {
        SanvyaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(S.StatementsAnalyze.outliersTitle.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.text2)
                ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, o in
                    HStack(spacing: 10) {
                        Text("\(o.txn.description) · \(o.txn.date)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        Text(formatMoney(o.amount, cur))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.negative)
                    }
                }
            }
        }
    }

    private func recurringCard(_ items: [RecurringCandidate], _ cur: String) -> some View {
        SanvyaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(S.StatementsAnalyze.looksRecurring.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.text2)
                ForEach(items, id: \.key) { r in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.label)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Color.text)
                                .lineLimit(1)
                            Text(S.StatementsAnalyze.recurringMeta(
                                amount: formatMoney(r.amount, cur),
                                cadence: cadenceLabel(r.cadence),
                                count: r.count
                            ))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.text2)
                        }
                        Spacer(minLength: 0)
                        if viewModel.addedRecurring.contains(r.key) {
                            Text(S.StatementsAnalyze.added)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.positive)
                        } else {
                            SanvyaChip(S.StatementsAnalyze.addAsRecurring, isActive: false) {
                                viewModel.addRecurring(r)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cadenceLabel(_ cadence: String) -> String {
        switch cadence {
        case "weekly": return S.StatementsAnalyze.cadenceWeekly
        case "yearly": return S.StatementsAnalyze.cadenceYearly
        default: return S.StatementsAnalyze.cadenceMonthly
        }
    }

    private func reconcileCard() -> some View {
        SanvyaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(S.StatementsAnalyze.reconcileTitle.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.text2)
                if viewModel.accountId.isEmpty || viewModel.reconciliation == nil {
                    Text(S.StatementsAnalyze.pickAccountReconcile)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.text2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let rec = viewModel.reconciliation {
                    FlowLayout(spacing: 16) {
                        tally("\(rec.matched.count)", S.StatementsAnalyze.matchedLabel, Color.positive)
                        tally("\(rec.missingOnPlatform.count)", S.StatementsAnalyze.missingLabel, Color.accent)
                        tally("\(rec.onlyOnPlatform.count)", S.StatementsAnalyze.onlyPlatformLabel, Color.text2)
                    }
                    if !rec.missingOnPlatform.isEmpty && !viewModel.imported {
                        SanvyaButton { viewModel.importMissing() } label: {
                            Text(S.StatementsAnalyze.importMissing(
                                count: rec.missingOnPlatform.count,
                                account: viewModel.accountName
                            ))
                            .multilineTextAlignment(.leading)
                        }
                    }
                    if viewModel.imported {
                        Text(S.StatementsAnalyze.importedDone)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.positive)
                    }
                }
            }
        }
    }

    private func tally(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.text2)
        }
    }

    private func transactionList(_ parsed: ParsedStatement, _ cur: String) -> some View {
        let shown = viewModel.showAllTransactions ? parsed.txns : Array(parsed.txns.prefix(12))
        return VStack(alignment: .leading, spacing: 8) {
            Text(S.StatementsAnalyze.transactionsTitle(count: parsed.txns.count).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Color.text2)
            SanvyaCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, t in
                        if i > 0 { Divider().overlay(Color.border) }
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.description)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Color.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(t.category.map { "\(t.date) · \($0)" } ?? t.date)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.text2)
                            }
                            Spacer(minLength: 0)
                            Text((t.amount >= 0 ? "+" : "−") + formatMoney(abs(t.amount), cur))
                                .font(.system(size: 13.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(t.amount >= 0 ? Color.positive : Color.text)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
            if parsed.txns.count > 12 {
                SanvyaChip(
                    viewModel.showAllTransactions
                        ? S.StatementsAnalyze.showLess
                        : S.StatementsAnalyze.showAll(count: parsed.txns.count),
                    isActive: false
                ) { viewModel.showAllTransactions.toggle() }
            }
        }
    }
}
