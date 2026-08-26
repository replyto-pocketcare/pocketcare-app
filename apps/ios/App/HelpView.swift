import SwiftUI
import Domain

/// Help & FAQ — ported from apps/web/app/help/page.tsx.
///
/// The CONTENT is generated from that file by tools/parity/generate-help.mjs,
/// so a change to web's copy reaches both native apps the next time the parity
/// job runs — and fails the job if it has not. The filter is Domain's,
/// vector-tested.
///
/// It is English here because it is English on web: the FAQ is 33 string
/// literals in that component rather than keys in `packages/core/i18n`. The
/// chrome around it — title, search box, no-match line, footer — is translated.
struct HelpView: View {
    @State private var query = ""
    @State private var open: Set<String> = []

    private var sections: [HelpSection] { filterHelp(helpSectionsAll, query: query) }

    var body: some View {
        ScrollView {
            SanvyaPage(S.Help.title) {
                Text(S.Help.subtitlePre + S.Help.subtitleLink + S.Help.subtitlePost)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)

                SanvyaInput(text: $query, placeholder: S.Help.searchPlaceholder)

                if sections.isEmpty {
                    Text(S.Help.noMatch(query: query))
                        .sanvyaStyle(SanvyaType.body)
                        .foregroundStyle(Color.text2)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            SanvyaIconView(glyph(section.icon), size: 17, tint: .white)
                                .frame(width: 30, height: 30)
                                .background(
                                    Color(hex: section.color) ?? Color.accent,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                            Text(section.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.text)
                        }
                        SanvyaCard(padding: 6) {
                            VStack(spacing: 0) {
                                ForEach(section.items) { item in
                                    row(section: section, item: item)
                                }
                            }
                        }
                    }
                }

                Text(S.Help.footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.text2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private func row(section: HelpSection, item: HelpItem) -> some View {
        // Forced open while searching — otherwise a match inside a collapsed
        // answer would be invisible and the search would look broken. Web's
        // `open.has(key) || !!q`, and the same rule `categoryTree` applies.
        let key = section.title + item.question
        let isOpen = open.contains(key) || !query.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if open.contains(key) { open.remove(key) } else { open.insert(key) }
            } label: {
                HStack(spacing: 10) {
                    Text(item.question)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    SanvyaIconView(SanvyaIcons.chevronRight, size: 18, tint: Color.text2)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .animation(SanvyaMotion.standard(0.15), value: isOpen)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? [.isSelected] : [])
            if isOpen {
                Text(item.answer)
                    .sanvyaStyle(SanvyaType.body)
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 13)
            }
        }
    }

    /// The generated content carries web's own icon name; this resolves it to
    /// the glyph. An unknown name falls back to the help glyph rather than
    /// painting nothing — though `generate-help.mjs` fails the parity job
    /// before one can reach here.
    private func glyph(_ name: String) -> String {
        SanvyaIcons.byWebName[name] ?? SanvyaIcons.help
    }
}

#Preview {
    HelpView()
}
