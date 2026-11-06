#!/bin/sh
# Builds the browser front end into web/: compiles src/web to JavaScript
# (release mode) and copies it next to web/index.html.
set -eu
cd "$(dirname "$0")/.."
moon build --target js --release
cp _build/js/release/build/web/web.js web/moon_nes.js
echo "built web/moon_nes.js; serve the web/ directory, e.g.:"
echo "  npx serve web    or    python -m http.server -d web"
