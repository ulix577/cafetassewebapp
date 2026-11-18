#!/bin/bash
# Builds a release bundle and assembles a self-contained static site in ../docs (served by GitHub Pages)
# that can be uploaded to any static HTTPS host (GitHub Pages, Netlify, Cloudflare Pages, ...).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh release

OUT="${CAFETASSE_BUILD_DIR:-$HOME/Library/Caches/CafeTasseWeb}/Package"  # same default as build.sh
DEST=../docs
rm -rf "$DEST"
mkdir -p "$DEST/app"

# Runtime files only: no TypeScript declarations, Node entry points or package.json.
cp -R "$OUT"/. "$DEST/app"/
find "$DEST/app" -name '*.d.ts' -delete
rm -f "$DEST/app"/package.json "$DEST/app"/platforms/node.js

cp styles.css "$DEST/"
# Same page as index.html, with the import pointing at the copied bundle (relative, so it also
# works from a sub-path such as https://user.github.io/cafetasse/).
sed 's#./.build/plugins/PackageToJS/outputs/Package/index.js#./app/index.js#' index.html > "$DEST/index.html"
touch "$DEST/.nojekyll"

echo
echo "$DEST ready:"
du -sh "$DEST"
find "$DEST" -type f | sort | sed 's/^/  /'
