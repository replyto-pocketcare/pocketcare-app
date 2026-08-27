import SwiftUI
import Data

/// Reflect — ported from apps/web/app/reflect/page.tsx.
///
/// A card stack over untagged expenses. Left is "need", right is "greed", and
/// the buttons do the same thing for anyone who would rather tap.
///
/// **Two deliberate divergences, both away from web's version:**
///
/// 1. Web's buttons are labelled "Need (←)" and "Greed (→)" — keyboard hints on
///    a screen that, on a phone, has no keyboard. The arrows are dropped and
///    the swipe is explained in a line under the stack instead.
/// 2. Web paints the swipe tints and the buttons with raw Material colours
///    (`#4CAF50`, `#F44336`) rather than the design tokens every other surface
///    uses. These use `positive` and `negative`, which is what those colours
///    were reaching for. Recorded in PARITY_AUDIT.
struct ReflectView: View {
    @State private var viewModel = ReflectViewModel()
    @State private var drag: CGSize = .zero

    /// The distance a card must travel before it counts as a judgement. Web's
    /// number, and its velocity escape hatch is the fling below.
    private let commitDistance: CGFloat = 100

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.isLoading {
                Spacer()
                SanvyaSpinner()
                Spacer()
            } else if viewModel.visible.isEmpty {
                Spacer()
                done
                Spacer()
            } else {
                stack
                footer
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }

    private var header: some View {
        HStack {
            Text(S.Reflect.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.text)
            Spacer(minLength: 0)
            Text(S.Reflect.left(count: String(viewModel.visible.count)))
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text2)
        }
        .padding(.bottom, 32)
    }

    private var done: some View {
        VStack(spacing: 8) {
            SanvyaIconView(SanvyaIcons.check, size: 48, tint: Color.positive)
            Text(S.Reflect.doneTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.text)
            Text(S.Reflect.doneBody)
                .sanvyaStyle(SanvyaType.body)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
        }
    }

    private var stack: some View {
        // Three cards at most, the top one last so it draws over the others —
        // web renders the same slice reversed for the same reason.
        let cards = Array(viewModel.visible.prefix(3))
        return ZStack {
            ForEach(Array(cards.enumerated()).reversed(), id: \.element.id) { index, row in
                let isTop = index == 0
                // `.gesture()` takes a Gesture, not an Optional, so the top
                // card is a separate branch rather than a ternary ending in
                // `nil` — which does not type-check.
                Group {
                    if isTop {
                        IntentCard(row: row, offset: drag)
                            .rotationEffect(.degrees(Double(drag.width / 20)))
                            .gesture(swipe(row))
                            .animation(SanvyaMotion.standard(0.3), value: drag == .zero)
                    } else {
                        IntentCard(row: row, offset: .zero)
                            .scaleEffect(1 - CGFloat(index) * 0.05)
                            .offset(y: CGFloat(index) * 15)
                            .allowsHitTesting(false)
                    }
                }
                .zIndex(isTop ? 10 : Double(3 - index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func swipe(_ row: LedgerRepository.IntentQueueRow) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                // Distance OR a fling, which is web's `velocity < -500`. A
                // short, fast flick is a decision too.
                let fling = abs(value.predictedEndTranslation.width) > 250
                if value.translation.width < -commitDistance || (fling && value.translation.width < 0) {
                    judge(row, "need")
                } else if value.translation.width > commitDistance || (fling && value.translation.width > 0) {
                    judge(row, "greed")
                } else {
                    drag = .zero
                }
            }
    }

    private func judge(_ row: LedgerRepository.IntentQueueRow, _ intent: String) {
        drag = .zero
        viewModel.judge(row.id, intent: intent)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text(S.Reflect.hint)
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text2)

            HStack(spacing: 12) {
                SanvyaButton(ghost: true, action: { judgeTop("need") }) {
                    Text(S.Reflect.need).foregroundStyle(Color.positive)
                }
                SanvyaButton(ghost: true, action: { judgeTop("greed") }) {
                    Text(S.Reflect.greed).foregroundStyle(Color.negative)
                }
            }

            HStack {
                SanvyaButton(ghost: true, action: { viewModel.undo() }) {
                    Text(S.Reflect.undo)
                }
                .disabled(!viewModel.canUndo)
                Spacer(minLength: 0)
                SanvyaButton(ghost: true, action: { if let top = viewModel.visible.first { viewModel.skip(top.id) } }) {
                    Text(S.Reflect.skip)
                }
            }
        }
        .padding(.top, 32)
    }

    private func judgeTop(_ intent: String) {
        guard let top = viewModel.visible.first else { return }
        judge(top, intent)
    }
}

/// One card in the stack. Its own view because the stack renders three of them
/// and only the top one is interactive.
private struct IntentCard: View {
    let row: LedgerRepository.IntentQueueRow
    let offset: CGSize

    /// Web's `tx.description || tx.note || "Unknown"`, spelled out. A nested
    /// ternary over two optionals is the shape that crashed this codebase's
    /// Swift type-checker once already — see InsightsViewModel's history.
    private var raw: String {
        if let description = row.description, !description.isEmpty { return description }
        if let note = row.note, !note.isEmpty { return note }
        return S.Reflect.unknown
    }

    var body: some View {
        let title = merchantTitle(raw)
        let tint = avatarColor(title)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(formatMoney(row.amountMinor, row.currency))
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(Color.text)
                .padding(.bottom, 8)
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
            if let account = row.accountName {
                HStack(spacing: 6) {
                    SanvyaIconView(SanvyaIcons.accountBalance, size: 16, tint: .white)
                    Text(account)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(tint, in: Capsule())
                .padding(.bottom, 12)
            }
            HStack(spacing: 16) {
                Text(isoLabel(row.occurredAt, "d MMM y"))
                if let category = row.categoryName {
                    Text("• \(category)")
                }
            }
            .sanvyaStyle(SanvyaType.statLabel)
            .foregroundStyle(Color.text2)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tint, lineWidth: 2)
        }
        // The tint the card takes on as it moves — green left, red right, the
        // same feedback web's two motion layers give.
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(offset.width < 0 ? Color.positive : Color.negative)
                // Explicit Double: `opacity` takes one, and leaning on the
                // CGFloat bridge inside a `min` is more type-checker work than
                // this line is worth.
                .opacity(Swift.min(0.2, Double(abs(offset.width)) / 500))
        }
        .offset(offset)
    }
}
