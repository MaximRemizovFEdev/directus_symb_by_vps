#!/bin/sh
set -eu

APP_INDEX="/directus/node_modules/.pnpm/@directus+app@file+app/node_modules/@directus/app/dist/index.html"
APP_DIST="/directus/node_modules/.pnpm/@directus+app@file+app/node_modules/@directus/app/dist"

if [ ! -f "$APP_INDEX" ]; then
  echo "Directus admin index.html not found: $APP_INDEX" >&2
  exit 0
fi

sed -i 's/<html lang="en"/<html lang="ru" class="notranslate"/' "$APP_INDEX"
sed -i 's/\\t<meta name="google" content="notranslate" \/>/        <meta name="google" content="notranslate" \/>/' "$APP_INDEX"

if ! grep -q 'name="google" content="notranslate"' "$APP_INDEX"; then
  sed -i '/<meta charset="utf-8" \/>/a\        <meta name="google" content="notranslate" />' "$APP_INDEX"
fi

if ! grep -q 'translate="no"' "$APP_INDEX"; then
  sed -i 's/<html lang="ru" class="notranslate"/<html lang="ru" class="notranslate" translate="no"/' "$APP_INDEX"
fi

CSS_FILE="/directus/setup/symbolika-admin-ui.css"
JS_FILE="/directus/setup/symbolika-admin-ui.js"
SW_FILE="/directus/setup/symbolika-push-sw.js"

if [ -f "$SW_FILE" ]; then
  cp "$SW_FILE" "$APP_DIST/symbolika-push-sw.js"
fi

if [ -f "$CSS_FILE" ]; then
  awk '
    /<style id="symbolika-admin-ui-css">/ {
      skipping = 1
      next
    }
    skipping == 1 && /<\/style>/ {
      skipping = 0
      next
    }
    skipping == 1 {
      next
    }
    /<\/head>/ && inserted == 0 {
      print "\t\t<style id=\"symbolika-admin-ui-css\">"
      while ((getline line < css_file) > 0) print line
      close(css_file)
      print "\t\t</style>"
      inserted = 1
    }
    { print }
  ' css_file="$CSS_FILE" "$APP_INDEX" > "$APP_INDEX.tmp"
  mv "$APP_INDEX.tmp" "$APP_INDEX"
fi

if [ -f "$JS_FILE" ]; then
  cp "$JS_FILE" "$APP_DIST/symbolika-admin-ui.js"
  JS_VERSION="$(cksum "$JS_FILE" | awk '{print $1}')"

  awk '
    /<script id="symbolika-admin-ui-js">/ {
      skipping = 1
      next
    }
    skipping == 1 && /<\/script>/ {
      skipping = 0
      next
    }
    skipping == 1 {
      next
    }
    /<script id="symbolika-admin-ui-js" src="\.\/symbolika-admin-ui\.js(\?v=[^"]*)?"><\/script>/ {
      next
    }
    /<\/body>/ && inserted == 0 {
      print "\t\t<script id=\"symbolika-admin-ui-js\" src=\"./symbolika-admin-ui.js?v=" js_version "\"></script>"
      inserted = 1
    }
    { print }
  ' js_version="$JS_VERSION" "$APP_INDEX" > "$APP_INDEX.tmp"
  mv "$APP_INDEX.tmp" "$APP_INDEX"
fi
