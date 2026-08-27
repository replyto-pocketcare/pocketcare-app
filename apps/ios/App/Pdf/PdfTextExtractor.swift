import Foundation
import PDFKit
import Factory
import Domain

/**
 Positioned text out of a PDF — the one platform-specific half of statement PDF
 parsing.

 Everything downstream of this (`groupPdfGlyphs` onwards) is shared Domain code
 under vector test, so an implementation's whole job is to hand back ordered
 glyphs with a TOP-DOWN y. Nothing else about the platform's PDF library leaks
 past this protocol.

 Mirrors Android's PdfTextExtractor.
 */
public protocol PdfTextExtracting: Sendable {
    /**
     False when PDF reading isn't usable in this build.

     Always true on iOS — PDFKit ships with the OS — but the flag exists so both
     platforms' analyzers ask the same question. Android's answer is the one that
     can be false.
     */
    var isAvailable: Bool { get }

    func extract(data: Data, password: String?) throws -> [PdfGlyph]
}

public enum PdfExtractionError: Error {
    /// The PDF is encrypted and the supplied password (if any) was wrong.
    case passwordRequired
    /// Anything else — a corrupt file, or a scan with no text layer.
    case unreadable
}

/**
 `PdfTextExtracting` on PDFKit.

 **Glyph by glyph, not line by line.** PDFKit will happily hand over
 `page.string`, but a flattened string throws away the x-positions the
 column-aware parser needs to tell a Withdrawal from a Deposit — and guessing
 the sign from a flattened line gets every refund and salary credit backwards.
 So this walks `characterBounds(at:)` and lets Domain rebuild the cells, using
 exactly the same rules Android's PDFBox glyphs go through.
 */
public struct PDFKitTextExtractor: PdfTextExtracting {
    public init() {}

    public var isAvailable: Bool { true }

    public func extract(data: Data, password: String?) throws -> [PdfGlyph] {
        guard let doc = PDFDocument(data: data) else { throw PdfExtractionError.unreadable }
        if doc.isLocked {
            guard let password, doc.unlock(withPassword: password) else {
                throw PdfExtractionError.passwordRequired
            }
        }

        var glyphs: [PdfGlyph] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            // PDF page space is bottom-up; PdfGlyph documents top-down, which is
            // what PDFBox's *DirAdj accessors already give Android.
            let height = page.bounds(for: .mediaBox).height
            let text = (page.string ?? "") as NSString
            let count = min(page.numberOfCharacters, text.length)

            for c in 0..<count {
                let bounds = page.characterBounds(at: c)
                // A line break has no glyph box. Left in, its null rect sorts to
                // infinity and shuffles the whole row.
                if bounds.isNull || bounds.isInfinite { continue }
                let ch = text.substring(with: NSRange(location: c, length: 1))
                if ch == "\n" || ch == "\r" { continue }
                glyphs.append(
                    PdfGlyph(
                        x: Double(bounds.minX),
                        y: Double(height - bounds.maxY),
                        width: Double(bounds.width),
                        text: ch
                    )
                )
            }
        }
        if glyphs.isEmpty && doc.pageCount > 0 {
            // A scan: pages exist, text does not. Domain's own "couldn't read
            // any transactions" warning says this better than an error would,
            // so the empty list is handed on rather than thrown.
            return []
        }
        return glyphs
    }
}

public extension Container {
    var pdfTextExtractor: Factory<any PdfTextExtracting> {
        self { PDFKitTextExtractor() }.singleton
    }
}
