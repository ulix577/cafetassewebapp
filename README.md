# CafeTasse Web App

A reduced web version of the CafeTasse iOS app, written in Swift and compiled to WebAssembly.

**Live:** https://ulix577.github.io/cafetassewebapp/

- Café list and "add café" form
- Café detail with check-in (browser geolocation distance check) and photo (camera or library)
- Visit history; swipe-to-delete unlocks per café once it has at least 10 visits

All data stays in the visitor's browser (IndexedDB). There is no server.

| Folder | Contents |
|---|---|
| `CafeTasseCore/` | Pure-Swift shared rules (coordinates and distance, check-in policy, delete policy, DTOs) with tests. Builds for macOS and WebAssembly. |
| `CafeTasseWeb/` | The web app (JavaScriptKit UI, IndexedDB storage). See its README for build instructions. |
| `docs/` | Built static site, published with GitHub Pages. Regenerate with `CafeTasseWeb/make-dist.sh`. |
