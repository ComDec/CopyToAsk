# Contributing

Thanks for contributing to CopyToAsk.

## Development

Prereqs:

- macOS 13+
- Xcode Command Line Tools (`swiftc`)

Build + run:

```bash
./build.sh
open build/CopyToAsk.app
```

## Permissions & Signing (Important)

macOS privacy permissions (TCC: Accessibility / Input Monitoring) are tied to the app's code signature.

For local development, create a stable self-signed identity once:

```bash
./scripts/setup_local_codesign_identity.sh
```

Then rebuild. `build.sh` will prefer `CopyToAsk Local Dev` when present.

## Selftests / Debugging

Smoke-run without manual interaction:

```bash
COPYTOASK_SELFTEST=all build/CopyToAsk.app/Contents/MacOS/CopyToAsk
```

UI trace log (writes to `/tmp/copytoask_ui.log`):

```bash
rm -f /tmp/copytoask_ui.log
COPYTOASK_TRACE_UI=1 open build/CopyToAsk.app
```

## Pull Request Checklist

- [ ] `./build.sh` succeeds locally
- [ ] No secrets committed (API keys, tokens, local files)
- [ ] UI strings work with Interface language = English / 中文
- [ ] CI passes
