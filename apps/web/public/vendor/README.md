# Vendored browser bundles

## `qrcode.min.js`

[qrcode](https://github.com/soldair/node-qrcode) **1.4.4**, MIT (© 2012 Ryan Day).
The UMD browser build, which sets `window.QRCode`. Loaded lazily by
`src/payments/qr.ts` and precached by the service worker.

### Why 1.4.4 and not latest

`qrcode` **stopped shipping the `build/` directory in 1.5.x**. Its
`package.json` still lists `"build"` under `files`, but the directory is not in
the published tarball — verify with:

```bash
npm pack qrcode@1.5.4 && tar -tzf qrcode-1.5.4.tgz | grep build/
```

The app previously loaded `cdn.jsdelivr.net/npm/qrcode@1.5.4/build/qrcode.min.js`,
which 404'd, so the pay-by-QR flow never worked for anyone. 1.4.4 is the last
release with the prebuilt browser bundle. QR encoding is a frozen spec, so an
older encoder is not a liability here.

### Why self-hosted rather than CDN

A payment QR is exactly what you need in a restaurant with one bar of signal.
The UPI payload is built locally, so with this file precached the whole flow
works offline. The app's other CDN loads (pdf.js, tesseract, transformers) are
megabyte-scale and genuinely don't belong in the bundle; this is 55 KB.

### Upgrading

If a future release restores a browser build, re-vendor it and confirm it still
exposes `window.QRCode` with a `toDataURL(text, opts)` promise API — that's the
whole surface `src/payments/qr.ts` uses.

## `jsQR.min.js`

[jsQR](https://github.com/cozmo/jsQR) **1.4.0**, Apache-2.0 — a QR *decoder*,
used to read a UPI QR from the camera. Minified with terser (252 KB → 128 KB);
upstream ships only an unminified UMD build. Sets `window.jsQR`.

**Fallback only.** `src/payments/scanQr.ts` uses the browser's native
`BarcodeDetector` where it exists — which includes Chrome on Android, where UPI
actually happens — and only loads this on Safari/iOS and Firefox.

**Deliberately NOT precached by the service worker**, unlike the icon font and
the QR encoder: it's 128 KB most users never fetch, and scanning needs a camera
plus a deliberate tap, so there's no cold-start cost to pay for. The browser
caches it after first use.
