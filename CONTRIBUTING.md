# Contributing

- Build: `swift build` (Command Line Tools are enough). Run the overlay with `.build/debug/annotate daemon`.
- Try changes: `annotate demo display=mouse`, then `annotate quit` before testing a new build.
- Release: bump `annotatorVersion` in `Sources/annotate/Daemon.swift` and the versions in `.claude-plugin/`,
  run `./scripts/build-release.sh` (refreshes `bin/annotate` and `dist/`), and add a CHANGELOG entry.
- Keep it dependency-free and keep drawing permission-free.
