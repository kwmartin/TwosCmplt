#!/usr/bin/env bash
set -e

swift package --allow-writing-to-directory ./docs \
    generate-documentation \
    --target $1 \
    --output-path ./docs/$1 \
    --transform-for-static-hosting \
    --hosting-base-path $1
