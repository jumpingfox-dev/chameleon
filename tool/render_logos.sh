#!/usr/bin/env bash
# Renders the logo SVGs in assets/images to the PNGs the app draws (480 pixels tall).
# The app shows the PNGs, not the SVGs: on GPUs without multisampling (many TVs), Flutter
# draws a vector's edges jagged. Run this after changing an SVG. Needs ImageMagick with librsvg.
set -euo pipefail
cd "$(dirname "$0")/../assets/images"
for svg in logo logo_color text_logo text_logo_color; do
  magick -background none -density 600 "RSVG:$svg.svg" -resize x480 "PNG32:$svg.png"
done
