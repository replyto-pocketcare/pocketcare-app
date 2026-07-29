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
