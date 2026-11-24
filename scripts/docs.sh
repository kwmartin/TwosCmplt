#!/usr/bin/env bash
# Build or view the TwosCmplt DocC documentation (see docs/README.md).
#   scripts/docs.sh serve   start a local web server (if not running) and open the examples page
#   scripts/docs.sh build   rebuild every DocC site into docs/<Target>/
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=8123
URL="http://localhost:$PORT/ExamplesDoc/documentation/examplesdoc/"

case "${1:-serve}" in
  serve)
    if ! curl -s -o /dev/null -f "$URL"; then
      nohup python3 -m http.server "$PORT" --directory "$ROOT/docs" \
        >/dev/null 2>&1 &
      sleep 1
      echo "Docs server started on port $PORT (stop: pkill -f 'http.server $PORT')"
    fi
    echo "$URL"
    xdg-open "$URL" >/dev/null 2>&1 || true
    ;;
  build)
    cd "$ROOT"
    ./scripts/build-examples-doc.sh
    for t in TwosCmplt SharedTypes CoeffMltply; do
      ./scripts/build-doc.sh "$t"
    done
    ;;
  *)
    echo "usage: $0 [serve|build]" >&2; exit 1 ;;
esac
