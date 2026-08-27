package com.sanvya.app.di

import com.sanvya.app.pdf.NoPdfTextExtractor
import com.sanvya.app.pdf.PdfBoxTextExtractor
import com.sanvya.app.pdf.PdfTextExtractor
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

/**
 * `:app`-layer bindings — platform capabilities that are neither a repository
 * nor UI, and so have no business in `dataModule`.
 *
 * Mirrors iOS's Container extensions in PdfTextExtractor.swift.
 */
val appModule = module {
    /**
     * The PDF extractor, or a stub that reports itself unavailable.
     *
     * Constructing the real one cannot throw — it only captures a Context and
     * defers everything else to a `lazy` — but the runCatching is here anyway so
     * that a library so broken it fails at class-load still leaves the app with
     * a working analyzer rather than a DI crash at startup.
     */
    single<PdfTextExtractor> {
        runCatching { PdfBoxTextExtractor(androidContext()) as PdfTextExtractor }
            .getOrDefault(NoPdfTextExtractor)
    }
}
