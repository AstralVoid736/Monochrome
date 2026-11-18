#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:---unit}"
if [[ "$MODE" != "--unit" && "$MODE" != "--native" ]]; then
  printf 'Usage: bash scripts/test.sh [--unit|--native]\n' >&2; exit 2
fi
mkdir -p .build
xcrun swiftc -warnings-as-errors Sources/SingleInstanceLock.swift Tests/SingleInstanceTests.swift -o .build/single-instance-tests
.build/single-instance-tests
xcrun swiftc -warnings-as-errors Sources/GrayscaleController.swift Tests/ControllerTests.swift -o .build/controller-tests
.build/controller-tests
xcrun swiftc -warnings-as-errors Sources/HotKeyController.swift Tests/HotKeyTests.swift -o .build/hotkey-tests
.build/hotkey-tests
xcrun swiftc -warnings-as-errors Sources/GrayscaleController.swift Sources/HotKeyController.swift Sources/StatusBarController.swift Tests/UITests.swift -o .build/ui-tests
.build/ui-tests
if [[ "$MODE" == "--native" ]]; then
  printf 'Native test temporarily changes your real display filter and restores its snapshot.\n'
  xcrun swiftc -warnings-as-errors Sources/GrayscaleController.swift Sources/NativeGrayscaleBackend.swift Tests/FilterFixture.swift Tests/NativeSmoke.swift -o .build/native-smoke
  .build/native-smoke --allow-display-change
fi
