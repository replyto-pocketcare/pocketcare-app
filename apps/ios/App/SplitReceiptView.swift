import SwiftUI
import Domain
import Data

/// Per-item split assignment — "who had what".
///
/// Ported from `apps/web/app/receipts/split/page.tsx`. One card per line: tap
/// faces to include people, pick how that line divides. Tax, service charge and
/// tip default to `proportional` (allocated by what each person actually ate),
/// which is the fair answer often enough that most people never touch it — but
/// can be overridden per charge, because "the service charge was for the table"
/// is just as common.
///
/// Nothing saves until every line is assigned and every exact/percent split
/// validates, so the expense that reaches the ledger is always balanced. Both
/// the per-line check and the allocation itself are Domain's, under vectors.
struct SplitReceiptView: View {
    let scanId: String
    let groupId: String
    let accountId: String
    let categoryId: String
    let onSaved: (String) -> Void
    let onCancel: () -> Void

    @State private var viewModel = SplitReceiptViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let draft = viewModel.draft {
                    content(draft)
                } else if viewModel.loaded {
                    SanvyaCard(padding: 20) {
                        Text(viewModel.error ?? S.Receipts.splitNotFound)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.text)
                    }
                    .padding(16)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(S.Receipts.splitTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Translation.commonCancel, action: onCancel)
                }
            }
        }
        .task {
            await viewModel.load(scanId: scanId, groupId: groupId, accountId: accountId, categoryId: categoryId)
        }
        .onChange(of: viewModel.savedExpenseId) { _, id in if let id { onSaved(id) } }
    }

    // MARK: - Body

    private func content(_ draft: ReceiptDraft) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(intro)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    quickSet

                    ForEach(draft.lines, id: \.id) { line in
                        lineCard(line)
                    }
                }
                .padding(16)
                // Room for the summary bar, which floats above the scroll.
                .padding(.bottom, 12)
            }

            summaryBar
        }
    }

    private var intro: String {
        let base = S.Receipts.splitIntro
        guard let name = viewModel.group?.name else { return base }
        return "\(base) · \(name)"
    }

    private var quickSet: some View {
        SanvyaCard(padding: 14) {
            // Wraps rather than scrolls: two chips and a label fit on every
            // phone, and a horizontal scroller here would hide the second one.
            FlowLayout(spacing: 8) {
                Text(S.Receipts.splitQuick)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.text2)
                SanvyaChip(S.Receipts.splitEveryoneAll, isActive: false) { viewModel.applyToAll(viewModel.everyone) }
                SanvyaChip(S.Receipts.splitOnlyMe, isActive: false) { viewModel.applyToAll(viewModel.onlyMe) }
            }
        }
    }

    // MARK: - One line

    @ViewBuilder
    private func lineCard(_ line: ReceiptLine) -> some View {
        if let s = viewModel.lineState(line.id) {
            SanvyaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    lineHeader(line)
                    participants(line, s)
                    modes(line, s)
                    if s.mode == "exact" || s.mode == "percent" || s.mode == "quantity" {
                        weightFields(line, s)
                    }
                    resolved(line)
                }
            }
        }
    }

    private func lineHeader(_ line: ReceiptLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.description.isEmpty ? kindLabel(line.kind) : line.description)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.text)
                    .fixedSize(horizontal: false, vertical: true)
                if isCharge(line.kind) || line.quantity != nil {
                    HStack(spacing: 6) {
                        if isCharge(line.kind) {
                            // A plain uppercase caption, not a chip: a chip
                            // reads as tappable and this is a static label.
                            // Web fixed the same thing for the same reason.
                            Text(kindLabel(line.kind).uppercased())
                                .font(.system(size: 11.5, weight: .semibold))
                                .kerning(0.6)
                        }
                        if isCharge(line.kind), line.quantity != nil { Text("·") }
                        if let quantity = line.quantity {
                            Text(S.Receipts.splitQtyLabel(
                                qty: trimmedQty(quantity),
                                unit: line.unit.map { " \($0)" } ?? ""
                            ))
                            .font(.system(size: 11.5))
                        }
                    }
                    .foregroundStyle(Color.text2)
                }
            }
            Spacer(minLength: 0)
            Text(formatMoney(line.amount, viewModel.currency))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.text)
        }
    }

    private func participants(_ line: ReceiptLine, _ s: SplitLineState) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(viewModel.memberIds, id: \.self) { uid in
                SanvyaChip(viewModel.name(of: uid), isActive: s.members.contains(uid)) {
                    viewModel.toggleMember(line.id, uid)
                }
                .accessibilityAddTraits(s.members.contains(uid) ? [.isSelected] : [])
            }
        }
    }

    private func modes(_ line: ReceiptLine, _ s: SplitLineState) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(splitModesFor(line), id: \.self) { m in
                SanvyaChip(modeLabel(m), isActive: s.mode == m) {
                    viewModel.setMode(line.id, m)
                }
            }
        }
    }

    private func weightFields(_ line: ReceiptLine, _ s: SplitLineState) -> some View {
        VStack(spacing: 8) {
            ForEach(s.members, id: \.self) { uid in
                HStack(spacing: 10) {
                    Text(viewModel.name(of: uid))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    TextField(
                        placeholder(s.mode),
                        text: Binding(
                            get: { s.weights[uid] ?? "" },
                            set: { viewModel.setWeight(line.id, uid, $0) }
                        )
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14))
                    .frame(width: 110)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.surface2, in: RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
                    .accessibilityLabel("\(viewModel.name(of: uid)) — \(modeLabel(s.mode))")
                    Text(suffix(s.mode, line.unit))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.text2)
                        .frame(width: 24, alignment: .leading)
                }
            }
        }
    }

    private func placeholder(_ mode: String) -> String {
        mode == "exact" ? majorTextFromMinor(0, viewModel.digits) : "0"
    }

    private func suffix(_ mode: String, _ unit: String?) -> String {
        switch mode {
        case "percent": return "%"
        case "quantity": return unit ?? "×"
        default: return ""
        }
    }

    @ViewBuilder
    private func resolved(_ line: ReceiptLine) -> some View {
        if let problem = viewModel.problem(for: line) {
            Text(problemText(problem))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.negative)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if case .success(let alloc)? = viewModel.allocation {
            FlowLayout(spacing: 10) {
                ForEach(alloc.perLine[line.id] ?? [], id: \.userId) { sh in
                    Text("\(viewModel.name(of: sh.userId)) \(formatMoney(sh.amount, viewModel.currency))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.text2)
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        SanvyaCard(padding: 16) {
            VStack(spacing: 12) {
                if case .success(let alloc)? = viewModel.allocation, !viewModel.hasLineProblem {
                    // Per-person tiles. A row of "Name: ₹x" runs together at a
                    // glance; stacking the label over the amount makes each
                    // person scannable. Web's reasoning, kept.
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.memberIds, id: \.self) { uid in
                            personTile(uid, alloc.byUser[uid] ?? 0)
                        }
                    }
                    Divider().overlay(Color.border)
                    HStack(alignment: .firstTextBaseline) {
                        Text(S.Receipts.splitTotal)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.text2)
                        Spacer()
                        Text(formatMoney(alloc.total, viewModel.currency))
                            .font(.system(size: 17, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.text)
                    }
                } else {
                    Text(summaryProblem)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.negative)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = viewModel.error, viewModel.draft != nil {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.negative)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SanvyaButton { viewModel.save() } label: {
                    Text(S.Receipts.splitSave).frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.canSave)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.bg)
    }

    private var summaryProblem: String {
        if viewModel.hasLineProblem { return S.Receipts.splitFixLines }
        if case .failure(let error)? = viewModel.allocation { return error.localizedDescription }
        return S.Receipts.splitFixLines
    }

    private func personTile(_ uid: String, _ amount: Int64) -> some View {
        let isMe = viewModel.name(of: uid) == S.Receipts.splitYou
        return VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.name(of: uid))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.text2)
                .lineLimit(1)
            Text(formatMoney(amount, viewModel.currency))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 120, alignment: .leading)
        .background(isMe ? Color.accentGhost : Color.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isMe ? Color.accentSoft : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Labels

    /// `mode.*` and `kind.*` are looked up dynamically on web; the generated
    /// accessors here are flat, so these are exhaustive switches over closed
    /// sets rather than a string-keyed map that could silently miss.
    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "equal": return S.Receipts.modeEqual
        case "quantity": return S.Receipts.modeQuantity
        case "percent": return S.Receipts.modePercent
        case "exact": return S.Receipts.modeExact
        default: return S.Receipts.modeProportional
        }
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "tax": return S.Receipts.kindTax
        case "service_charge": return S.Receipts.kindServiceCharge
        case "tip": return S.Receipts.kindTip
        case "discount": return S.Receipts.kindDiscount
        default: return S.Receipts.kindItem
        }
    }

    private func problemText(_ problem: LineProblem) -> String {
        switch problem {
        case .needsSomeone:
            return S.Receipts.splitNeedsSomeone
        case .exactMismatch(let diffMinor):
            return S.Receipts.splitExactMismatch(diff: majorTextFromMinor(diffMinor, viewModel.digits))
        case .percentMismatch(let pct):
            return S.Receipts.splitPercentMismatch(pct: pct)
        case .quantityMismatch(let gotMilli, let wantMilli):
            return S.Receipts.splitQtyMismatch(got: trimmedQty(gotMilli), want: trimmedQty(wantMilli))
        }
    }

    /// Milli-units as the shortest exact decimal: 2000 → "2", 1500 → "1.5".
    /// Web prints the raw JS number, which drops trailing zeros the same way.
    private func trimmedQty(_ milli: Int64) -> String {
        let major = qtyToMajor(milli)
        if major == major.rounded() { return String(Int64(major)) }
        var text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), major)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
