# Contributing

Small, focused issues and pull requests are welcome. English and Russian are both fine.

## Before changing code

- Check existing issues and explain the observed problem, not only a proposed fix.
- Keep this a small native menu bar utility. New network access, telemetry, background services, dependencies or startup behavior need an explicit design discussion.
- Preserve the refusal to overwrite another active accessibility color filter.

## Development checks

```bash
bash scripts/test.sh
bash scripts/build.sh --universal
```

Run real-display tests only on your own interactive Mac, when changing the display briefly is acceptable. Never add `--native` to hosted CI. Do not claim physical display coverage from preference readback alone.

For behavior changes, add a regression test, demonstrate its failure, then implement the change. Explain how you checked it. Current tests are small Swift executables and do not require XCTest or external packages.

## Pull requests

State the problem, scope, checks actually run, and remaining limitations. Do not include build outputs, local logs, credentials, signing identities or personal paths. Contributions are provided under this project's MIT license.
