# Receipt Scan — mobile screen spec (task #62)

Source: `apps/web/app/receipts/new/page.tsx` (capture), `.../review/page.tsx`
(review), `.../split/page.tsx` (itemized split). Pipeline: `apps/web/src/
receipts/scan.ts`, `draft.ts`. Domain: `@sanvya/receipts`, already fully
ported and golden-vector-tested on both platforms before this pass —
`ReceiptsTypes/Parse/Reconcile/MoneyText/Allocate.{kt,swift}`. Persistence:
`ReceiptsRepository.{kt,swift}` (receipt_scans table), also already built.
This spec covers what was still missing: actual capture, OCR, and a review
UI, on both platforms.

## Entry point

Web's entry point is `AddSpeedDial` on the Dashboard only (`apps/web/app/
AppShell.tsx`, `pathname === "/"`): a two-item speed dial, "Add transaction"
and "Scan bill / receipt". Neither mobile Dashboard had ANY quick-add
control before this pass (verified by grep — no FAB/SpeedDial symbol
existed on either platform). Added here, matching web exactly: a FAB on
Dashboard with those two actions, nothing on any other screen.

## Scope for this pass (documented cuts, not oversights)

1. **Capture is camera-only.** No PDF upload, no gallery upload. Web
   supports both; the camera path is the one every mobile user actually
   wants, and PDF text-layer extraction (`extractPdfRows`, pdf.js) has no
   mobile equivalent to port. A future pass can add "import from Files".
2. **No "Improve with AI" escalation.** Web's fallback sends the photo to
   an edge function gated by `useEntitlement`'s monthly quota. That's a
   second subsystem (entitlements + edge function invocation) this pass
   doesn't touch. When OCR doesn't reconcile, mobile offers only "Edit it
   myself" / "Retake" — a strict subset of web's options, never a dead end.
3. **OCR is text-only, not geometry-based.** Web prefers `groupIntoLines`
   (rebuilding lines from per-word bounding boxes) and only falls back to
   flat-text `parseReceiptText` when the OCR engine returns zero word boxes
   — a real, already-supported degraded path in the actual web source, not
   an invented one. Neither ML Kit's `TextRecognizer` (Android) nor Vision's
   `VNRecognizeTextRequest` (iOS) hand back a per-word box list in the shape
   `groupIntoLines` expects without materially more integration work, so v1
   mobile always takes web's own fallback path: join recognized text lines
   with `\n` and feed `parseReceiptText`. `parseReceipt`/`groupIntoLines`
   stay fully ported and unit-tested for a future pass that wires up boxes.
4. **No image persistence, stricter than web.** Web's `image_path` column
   is always null (documented in `receipt_scans`); the photo is held in
   memory only for the current tab. Mobile goes further: the captured frame
   is decoded in memory, handed to the OCR engine, and never touches disk or
   the camera roll at all. Android: `ImageCapture.OnImageCapturedCallback`'s
   in-memory `ImageProxy` (CameraX). iOS: `UIImagePickerController`
   (`sourceType = .camera`) rather than a hand-rolled `AVCaptureSession`
   preview — first camera feature in this app, and the picker hands back an
   in-memory `UIImage` via its delegate with no `Photos`/`MediaStore` write
   unless the user explicitly taps "Save to Photos" in the OS camera UI,
   which this flow never triggers.
5. **"Split this bill" is visible but disabled**, with a note that it's
   coming with automatic split detection (task #63/64). Web's itemized
   split-assignment screen (`/receipts/split`, per-line participant + mode
   picker) is real and substantial, and `SplitsRepository`'s own header
   comment already deferred the itemized write path (`expense_items`/
   `expense_item_shares`) pending "a future pass ... once a ReceiptsRepository
   exists to pair with it" — that repository now exists, but the BLE
   proximity feature the user asked for next will drive its own
   participant-selection UI (auto-detected people, not manual per-item
   taps), and building the manual web-parity screen now risks throwing it
   away once that design lands. "Just record it" (save as transaction) is
   fully built; itemized split-write ships with task #64.
6. **No category auto-suggest yet.** Web's review screen calls
   `suggestCategory` (the learned classifier) to prefill a category from the
   merchant name. That classifier isn't ported to mobile yet — it's task
   #65 (Auto-categorization), tracked separately. This review screen shows
   the category picker (manual selection works today) and will pick up the
   auto-suggest for free once #65 lands, since it reads the same
   `categoryId` state.

Everything else — editable merchant/date/account/category, the editable
line table (add item/add charge/remove/edit description-qty-kind-amount),
the reconciliation banner with both one-tap fixes (`balanceWithLine`/
`adoptComputedTotal`, already ported), and "Save transaction" — is full
parity with web's review screen.

## Flow

1. **Capture** (`ReceiptCaptureView`/`Screen`). Live camera preview, one
   shutter button. On capture: `preparing → reading → understanding → done`
   progress states (mirrors `ScanStage` minus the AI stage). OCR runs
   on-device (ML Kit / Vision). Result goes through `parseReceiptText` with
   `today` = current date and `currency` = the user's base currency
   fallback. If `reconcile(draft).ok`, the scan is saved immediately
   (`ReceiptsRepository.saveScan`) and the screen navigates to Review — no
   extra tap, matching web's "a clean read needs no decision from the
   user". If not reconciled, show the mismatch reason (`no_lines` /
   `missing_total` / `mismatch`, same copy as web's `describeMismatch`) with
   "Edit it myself" (saves the unreconciled draft anyway, same as web) and
   "Retake".
2. **Review** (`ReceiptReviewView`/`Screen`). Loads the scan by id, parses
   `parsed_json` back into a `ReceiptDraft` (hand-rolled JSON encode/decode
   — the ported domain structs are plain value types, not
   `Codable`/`@Serializable`, and this pass doesn't retrofit golden-vector-
   tested code to add that). Editable header fields, editable line table,
   reconciliation strip, "Save transaction" (disabled until balanced, same
   gate as web: `canSave = balanced && accountId && !saving`). Saves via
   `LedgerRepository.createTransaction` with `items` = the draft's lines
   (description folds in qty/unit exactly like web's `describeItem`), then
   `ReceiptsRepository.linkScan(transactionId:)`.

## Files

- Android: `ui/receipts/ReceiptCaptureViewModel.kt`,
  `ReceiptCaptureScreen.kt`, `ReceiptReviewViewModel.kt`,
  `ReceiptReviewScreen.kt`. Routes `"receipts/new"`,
  `"receipts/review/{scanId}"` in `SanvyaNavHost.kt`. CameraX
  (`camera-core`/`camera-camera2`/`camera-lifecycle`/`camera-view`) + ML Kit
  `text-recognition` added to the version catalog — first use of either in
  this app.
- iOS: `ReceiptCaptureView.swift` (replaces the old hardcoded-fixture
  `ReceiptScanView.swift` entirely — that file showed a fake "Olive Garden"
  bill with static line items and no camera, OCR, or repository wiring at
  all), `ReceiptReviewView.swift`, `ViewModels/ReceiptCaptureViewModel.swift`,
  `ViewModels/ReceiptReviewViewModel.swift`. Presented via
  `.fullScreenCover` from `DashboardView`'s new speed dial (matches the
  in-place list/detail convention's spirit — a capture flow is inherently
  its own modal task, not a drawer tab). `NSCameraUsageDescription` added to
  `Generated/Sanvya-Info.plist` (first camera-using feature in the app — no
  prior entry existed to reuse).
