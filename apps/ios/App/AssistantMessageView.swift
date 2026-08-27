import Domain
import SwiftUI

/**
 Rendering an assistant message: markdown prose, then the `<ui>` block.

 Ported from `richMessage.tsx`'s render half. The PARSE half is Domain's and is
 vector-pinned; this file is only how the result is drawn, which is the part
 that is legitimately per-platform.

 Mirrors Android's AssistantMessage.kt.
 */

/**
 A line of inline markdown as one styled string.

 A link renders as underlined accent text rather than a tappable region.
 SwiftUI can make it tappable — `AttributedString` carries a `.link` — but the
 routes the model may emit are the same ones the `<ui>` actions carry, and those
 ARE buttons. Recorded in ABSENT-BY-DECISION rather than half-built.
 */
private func inlineAttributed(_ line: String) -> AttributedString {
    var out = AttributedString()
    for span in assistantInlineSpans(line) {
        var piece = AttributedString(span.text)
        switch span.kind {
        case .text:
            break
        case .bold:
            piece.font = SanvyaType.body.weighted(700).font
        case .italic:
            piece.font = SanvyaType.body.font.italic()
        case .code:
            piece.font = .system(.body, design: .monospaced)
            piece.backgroundColor = Color.surface2
        case .link:
            piece.foregroundColor = Color.accent
            piece.underlineStyle = .single
        }
        out.append(piece)
    }
    return out
}

/// Assistant prose, as blocks.
struct AssistantMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseAssistantBlocks(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantBlock) -> some View {
        switch block {
        case let .heading(level, text):
            // Web's three sizes, keyed off the hash count.
            Text(inlineAttributed(text))
                .sanvyaStyle(SanvyaType.body.resized(level <= 1 ? 17 : level == 2 ? 15.5 : 14).weighted(700))
                .foregroundStyle(Color.text)

        case let .paragraph(lines):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(inlineAttributed(line))
                        .sanvyaStyle(SanvyaType.body)
                        .foregroundStyle(Color.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case let .bullets(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // A task list draws its own box; a plain bullet gets the
                        // dot. Web swaps the whole list style when ANY item is a
                        // task, and so does this by marking each item
                        // individually — the visual result is the same and the
                        // code is smaller.
                        Text(item.task ? (item.checked ? "☑" : "☐") : "•")
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.text2)
                        Text(inlineAttributed(item.text))
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.text)
                            .strikethrough(item.checked)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case let .ordered(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.text2)
                        Text(inlineAttributed(item))
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case let .quote(lines):
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(Color.accentSoft).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(inlineAttributed(line))
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

        case .rule:
            Rectangle().fill(Color.border).frame(height: 1)

        case let .code(text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color.text)
                    .padding(12)
            }
            .background(Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))

        case let .table(header, rows):
            AssistantTableView(header: header, rows: rows)
        }
    }
}

/**
 A markdown table.

 Horizontally scrollable, because the model emits comparison tables with three
 or four money columns and a phone is 390pt wide. Web's own table sits in an
 `overflow-x: auto` box for the same reason.
 */
private struct AssistantTableView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .sanvyaStyle(SanvyaType.body.resized(13).weighted(600))
                            .foregroundStyle(Color.text2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)

                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Rectangle().fill(Color.border).frame(height: 1)
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(header.indices), id: \.self) { col in
                            Text(col < row.count ? row[col] : "")
                                .sanvyaStyle(SanvyaType.body.resized(13).weighted(col == 0 ? 600 : 400))
                                .foregroundStyle(Color.text)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .id(index)
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
    }
}

/// The `<ui>` block: cards, then action chips.
struct AssistantUiBlockView: View {
    let ui: AssistantUi
    let onSend: (String) -> Void
    let onOpen: (String) -> Void
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ui.cards.enumerated()), id: \.offset) { _, card in
                SanvyaCard(padding: 14) { cardBody(card) }
            }
            if !ui.actions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(ui.actions.enumerated()), id: \.offset) { _, action in
                        SanvyaChip(action.label, isActive: false) {
                            guard enabled else { return }
                            // `send` and `href` are mutually exclusive by the
                            // time Domain has validated the action, and `href`
                            // is guaranteed to start with "/".
                            if let send = action.send {
                                onSend(send)
                            } else if let href = action.href {
                                onOpen(href)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cardBody(_ card: AssistantCard) -> some View {
        switch card {
        case let .stat(stat):
            VStack(alignment: .leading, spacing: 4) {
                Text(stat.label)
                    .sanvyaStyle(SanvyaType.body.resized(11.5))
                    .foregroundStyle(Color.text2)
                Text(stat.value)
                    .sanvyaStyle(SanvyaType.h2)
                    .foregroundStyle(toneColor(stat.tone))
                if let sub = stat.sub {
                    Text(sub)
                        .sanvyaStyle(SanvyaType.body.resized(11.5))
                        .foregroundStyle(Color.text2)
                }
            }

        case let .progress(progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.label)
                    .sanvyaStyle(SanvyaType.body.resized(11.5))
                    .foregroundStyle(Color.text2)
                if let value = progress.value {
                    Text(value).sanvyaStyle(SanvyaType.body).foregroundStyle(Color.text)
                }
                AssistantBar(pct: progress.pct)
            }

        case let .breakdown(breakdown):
            VStack(alignment: .leading, spacing: 6) {
                Text(breakdown.label)
                    .sanvyaStyle(SanvyaType.body.resized(11.5))
                    .foregroundStyle(Color.text2)
                ForEach(Array(breakdown.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.label)
                            .sanvyaStyle(SanvyaType.body.resized(13))
                            .foregroundStyle(Color.text)
                        Spacer(minLength: 8)
                        if let value = item.value {
                            Text(value)
                                .sanvyaStyle(SanvyaType.body.resized(13))
                                .foregroundStyle(Color.text2)
                        }
                    }
                    // An ABSENT pct means "no bar" — Domain keeps that
                    // distinction from "a bar at zero" on purpose.
                    if let pct = item.pct { AssistantBar(pct: pct) }
                }
            }

        case let .chart(chart):
            VStack(alignment: .leading, spacing: 6) {
                Text(chart.label)
                    .sanvyaStyle(SanvyaType.body.resized(11.5))
                    .foregroundStyle(Color.text2)
                if let value = chart.value {
                    Text(value).sanvyaStyle(SanvyaType.h2).foregroundStyle(Color.text)
                }
                SanvyaBarsChart(
                    series: chart.points.map { SeriesPoint($0.x, $0.y) },
                    unit: nil,
                    horizontal: false,
                    accent: Color.accent
                )
                .frame(height: 140)
            }
        }
    }

    private func toneColor(_ tone: String) -> Color {
        switch tone {
        case "positive": return Color.positive
        case "negative": return Color.negative
        case "neutral": return Color.text
        default: return Color.accent
        }
    }
}

/// The progress/breakdown bar. 0...100, already clamped by Domain.
struct AssistantBar: View {
    let pct: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surface2)
                Capsule()
                    .fill(Color.accent)
                    .frame(width: geo.size.width * min(max(pct / 100, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
