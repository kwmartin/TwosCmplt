#!/usr/bin/env bash

set -x

docc convert .build/plugins/Swift-DocC/outputs/$1.doccarchive \
  --output-path docs/$1 \
  --hosting-base-path $1 \
  --allow-arbitrary-catalog-directories
