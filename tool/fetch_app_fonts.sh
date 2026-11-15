#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/google_fonts

fetch() {
  local query="$1" output="$2" url
  url=$(curl -fsS -A 'Mozilla/5.0 (Windows NT 6.1; WOW64)' \
    "https://fonts.googleapis.com/css?family=${query}" |
    grep -o 'https://fonts.gstatic.com[^)]*\.ttf' | head -n 1)
  if [ -z "$url" ]; then
    echo "No TTF returned for ${query}" >&2
    exit 1
  fi
  curl -fsS "$url" -o "assets/google_fonts/${output}.ttf"
  printf '%s: %s bytes\n' "$output" "$(wc -c < "assets/google_fonts/${output}.ttf")"
}

# Every family the Linux reader can select. Output names must not contain
# spaces: google_fonts looks for `<FamilyWithoutSpaces>-<Variant>.ttf`.
fetch 'Merriweather'                 'Merriweather-Regular'
fetch 'Lora'                         'Lora-Regular'
fetch 'Playfair+Display'             'PlayfairDisplay-Regular'
fetch 'Crimson+Text'                 'CrimsonText-Regular'
fetch 'EB+Garamond'                  'EBGaramond-Regular'
fetch 'PT+Serif'                     'PTSerif-Regular'
fetch 'Source+Serif+4'               'SourceSerif4-Regular'
fetch 'Libre+Baskerville'            'LibreBaskerville-Regular'
fetch 'Roboto'                       'Roboto-Regular'
fetch 'Open+Sans'                    'OpenSans-Regular'
fetch 'Lato'                         'Lato-Regular'
fetch 'Noto+Sans'                    'NotoSans-Regular'

# Weights the app chrome asks for in theme_utils.dart and the screens.
fetch 'Lato:700'                     'Lato-Bold'
fetch 'Lato:italic'                  'Lato-Italic'
fetch 'Playfair+Display:600'         'PlayfairDisplay-SemiBold'
fetch 'Playfair+Display:700'         'PlayfairDisplay-Bold'
fetch 'Playfair+Display:italic'      'PlayfairDisplay-Italic'
