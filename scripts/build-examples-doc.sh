#!/usr/bin/env bash
set -e

swift package --allow-writing-to-directory ./docs \
    generate-documentation \
    --target ExamplesDoc --target TwosCmplt \
    --output-path ./docs/ExamplesDoc \
    --transform-for-static-hosting \
    --hosting-base-path ExamplesDoc
