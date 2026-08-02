/**
 * @sanvya/receipts — pure logic for scanned receipts and itemized splitting.
 *
 * No DOM, no OCR engine, no database: this package only knows how to describe a
 * parsed receipt, check that it adds up, and divide it among people without
 * losing a minor unit. The browser-side OCR pipeline lives in
 * `apps/web/src/receipts/*` and produces the `ReceiptDraft` this package
 * validates.
 */
export * from "./types.ts";
export * from "./allocate.ts";
export * from "./reconcile.ts";
export * from "./money-text.ts";
export * from "./parse.ts";
