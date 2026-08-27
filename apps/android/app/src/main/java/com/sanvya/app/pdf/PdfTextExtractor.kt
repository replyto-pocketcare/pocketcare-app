package com.sanvya.app.pdf

import com.sanvya.app.domain.statements.PdfGlyph

/**
 * Positioned text out of a PDF — the one platform-specific half of statement
 * PDF parsing.
 *
 * Everything downstream of this ([groupPdfGlyphs] onwards) is shared Domain code
 * under vector test, so an implementation's whole job is to hand back ordered
 * glyphs with a TOP-DOWN y. Nothing else about the platform's PDF library leaks
 * past this interface, which is what makes the library replaceable: swapping
 * PDFBox for something else is one new class and one Koin line.
 *
 * Mirrors iOS's PdfTextExtracting.
 */
interface PdfTextExtractor {
    /**
     * False when the underlying library isn't present or usable in this build.
     *
     * A real state, not defensive noise: a minified build can strip a reflective
     * dependency, and a library can be removed outright. The analyzer checks
     * this before it offers PDFs at all, so the user is told to use the CSV
     * export instead of being handed a file picker that always fails.
     */
    val isAvailable: Boolean

    /**
     * @return glyphs in reading order, or throws [PdfPasswordRequired] /
     *   [PdfExtractionFailed].
     */
    suspend fun extract(bytes: ByteArray, password: String? = null): List<PdfGlyph>
}

/** The PDF is encrypted and the supplied password (if any) was wrong. */
class PdfPasswordRequired : Exception("password required")

/** Anything else — a corrupt file, a scanned image, a library that broke. */
class PdfExtractionFailed(cause: Throwable?) : Exception(cause?.message, cause)

/** Used when no extractor is installed: always unavailable, never throws on construction. */
object NoPdfTextExtractor : PdfTextExtractor {
    override val isAvailable = false
    override suspend fun extract(bytes: ByteArray, password: String?): List<PdfGlyph> =
        throw PdfExtractionFailed(null)
}
