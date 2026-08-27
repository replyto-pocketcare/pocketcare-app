package com.sanvya.app.pdf

import android.content.Context
import com.sanvya.app.domain.statements.PdfGlyph
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream

/**
 * [PdfTextExtractor] on PDFBox-Android (Apache-2.0).
 *
 * **Why this library.** The realistic Android choices were PDFBox-Android and
 * iText. iText 7 is AGPL-3.0 unless you buy a commercial licence, and AGPL on a
 * closed-source app means publishing the app's source — so "most reliable" here
 * resolves to the only one whose licence permits shipping at all. PDFBox-Android
 * is also the one that can give x-positions, which the column-aware parser needs.
 *
 * **Why it is optional.** Every entry point is guarded and every failure mode —
 * a missing class after minification, a `LinkageError`, an unsupported font, an
 * outright broken release — comes back as an unavailable extractor rather than a
 * crash, and the analyzer falls back to CSV. That keeps the blast radius of the
 * library breaking to "PDFs stop working", not "the app stops working".
 *
 * `Throwable`, not `Exception`, is caught on purpose: `NoClassDefFoundError` and
 * `ExceptionInInitializerError` are Errors, and they are precisely the failures
 * a stripped or half-installed library produces.
 */
class PdfBoxTextExtractor(private val context: Context) : PdfTextExtractor {

    override val isAvailable: Boolean by lazy {
        runCatching {
            Class.forName("com.tom_roush.pdfbox.pdmodel.PDDocument")
            true
        }.getOrDefault(false)
    }

    /**
     * PDFBox needs its font assets unpacked once per process. Idempotent, and
     * cheap after the first call.
     */
    private val loaded: Boolean by lazy {
        runCatching { PDFBoxResourceLoader.init(context.applicationContext); true }.getOrDefault(false)
    }

    override suspend fun extract(bytes: ByteArray, password: String?): List<PdfGlyph> =
        withContext(Dispatchers.IO) {
            if (!isAvailable || !loaded) throw PdfExtractionFailed(null)
            try {
                ByteArrayInputStream(bytes).use { stream ->
                    PDDocument.load(stream, password.orEmpty()).use { doc ->
                        val stripper = GlyphStripper()
                        // The assembled text is thrown away; the glyphs are
                        // collected by writeString below.
                        stripper.getText(doc)
                        stripper.glyphs
                    }
                }
            } catch (e: InvalidPasswordException) {
                throw PdfPasswordRequired()
            } catch (e: Throwable) {
                throw PdfExtractionFailed(e)
            }
        }
}

/**
 * A [PDFTextStripper] that keeps the positions instead of the text.
 *
 * `writeString` is the only hook that receives [TextPosition]s, which is why the
 * stripper is run at all — the assembled string it produces is thrown away.
 * Taking glyphs rather than PDFBox's own words is deliberate: iOS's PDFKit has
 * no word concept, so the two phones would disagree about cell boundaries unless
 * both feed raw glyphs into Domain's shared grouper.
 */
private class GlyphStripper : PDFTextStripper() {
    val glyphs = mutableListOf<PdfGlyph>()

    override fun writeString(text: String, textPositions: MutableList<TextPosition>) {
        for (tp in textPositions) {
            val unicode = tp.unicode ?: continue
            if (unicode.isEmpty()) continue
            glyphs.add(
                PdfGlyph(
                    // *DirAdj: already corrected for the page's rotation, and
                    // y is already top-down — which is the convention PdfGlyph
                    // documents and PDFKit's extractor has to convert into.
                    x = tp.xDirAdj.toDouble(),
                    y = tp.yDirAdj.toDouble(),
                    width = tp.widthDirAdj.toDouble(),
                    text = unicode,
                ),
            )
        }
    }
}
