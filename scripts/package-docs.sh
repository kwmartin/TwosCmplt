#!/usr/bin/env bash
set -e
swift package generate-documentation
swift package --disable-sandbox preview-documentation --target TwosCmplt
