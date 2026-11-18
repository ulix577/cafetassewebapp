# CafeTasseWeb

Reduced web version of CafeTasse, written in Swift and compiled to WebAssembly with
[JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit). It shares its rules with the iOS app
through the `../CafeTasseCore` package.

**Features**
- Café list with an Edit mode (select cafés, move them up or down, or delete them) and an "add café" form (guests enter the café data themselves); the café location comes from
  the guest's position ("I'm here now") or from the typed address (lookup on button tap)
- Café detail with check-in (distance check via browser geolocation) and photo (live in-page camera only: no file or gallery picker)
- Visit history; swipe-to-delete is enabled per café only once it has at least 10 visits

All data stays in the browser (IndexedDB). There is no server and no sync with the iOS app.

## Build

Needs the swift.org 6.4.2 toolchain (via swiftly) and the matching Wasm SDK
(`swift sdk list` should show `swift-6.4.2-RELEASE_wasm`).

```sh
./build.sh release  # or: ./build.sh debug (much larger .wasm)
```

Build files go to `~/Library/Caches/CafeTasseWeb` (set `CAFETASSE_BUILD_DIR` to change), not into this
folder. Reason: inside an iCloud-synced folder such as `~/Documents`, iCloud creates `name 2.swift`
conflict copies in `.build` and the build breaks with "ambiguous for type lookup" errors.

The build uses `--use-cdn`, so the browser loads the WASI shim from jsDelivr at runtime
(internet needed on first load).

## Run locally

```sh
./make-dist.sh                # builds and writes ../docs
cd ../docs && python3 -m http.server 8000
# open http://localhost:8000
```

Geolocation and the camera only work on `https://` or `localhost`.

## Deploy (static hosting, for phones)

```sh
./make-dist.sh
```

This runs a release build and assembles `../docs/` (about 18 MB: `index.html`, `styles.css`, `app/` with
the `.wasm` and its JS runtime). All paths are relative, so it works at the site root or in a sub-path.
In this repo `docs/` is published by GitHub Pages. To use another static HTTPS host, upload the contents of `docs/`, for example:

- **Netlify:** drag the `docs` folder onto https://app.netlify.com/drop
- **Cloudflare Pages:** `npx wrangler pages deploy docs` or upload through the dashboard
- **GitHub Pages:** publish the contents of `docs/` (a `.nojekyll` file is included)

Then open the HTTPS URL in Chrome on Android (or Safari on iPhone). Make sure the host serves the
`.wasm` as `application/wasm` and compressed (all of the above do this by default).

## Notes
- The web check-in radius is `webCheckInRadius` (10 m, same as the iOS default) in `App.swift`. Browser
  GPS is often less precise than that, so check-ins can be refused near the café; raise it if needed.
- The target imports `FoundationEssentials` (not `Foundation`) to avoid bundling ICU data: the release
  `.wasm` is about 18 MB (4.8 MB gzipped) instead of about 60 MB. Keep it that way: `trimmingCharacters`,
  `replacingOccurrences`, `range(of:)`, `LocalizedError` and `DateFormatter` are not available there.
  Serve the `.wasm` with gzip or brotli compression.
- "Find location from address" calls OpenStreetMap's Nominatim service
  (https://operations.osmfoundation.org/policies/nominatim/). It runs only when the user taps the button,
  never automatically, to respect the usage policy (about 1 request per second, no bulk use). The
  address is sent to that service; the UI says so. The result parsing lives in `CafeTasseCore`
  (`GeocodingResponse`) and is unit tested.
- UI text is English only.
- Source layout: `DOM.swift` (DOM helpers), `Browser.swift` (geolocation, photo resizing),
  `Store.swift` (IndexedDB), `App.swift` (state, routing), `Screens.swift` (screens),
  `SwipeRow.swift` (swipe gesture).
