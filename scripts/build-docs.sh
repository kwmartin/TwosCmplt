#!/usr/bin/env bash
set -e
swift build -Xswiftc -emit-symbol-graph \
            -Xswiftc -emit-symbol-graph-dir \
            -Xswiftc .build/symbol-graphs
swift docc convert Sources/SharedTypes/SharedTypes.docc \
  --output-path Docs \
  --transform-for-static-hosting \
  --additional-symbol-graph-dir .build/symbol-graphs
swift docc convert Sources/TwosCmplt/TwosCmplt.docc \
  --output-path Docs \
  --transform-for-static-hosting \
  --additional-symbol-graph-dir .build/symbol-graphs
