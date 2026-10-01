# macOS (Apple Silicon) work on Scribus

This directory lives only on the `macos/tooling` branch of this fork. It is not meant for upstream.

- `build-macos.sh`: builds Scribus 1.7 (trunk, Qt 6) on macOS arm64 with Homebrew, CMake and Ninja. Run `macos/build-macos.sh deps`, then `macos/build-macos.sh podofo` (optional), then `macos/build-macos.sh all`. `build/`, `install/` and `deps/` are created next to the clone.
- `patches/`: the fixes submitted to the Scribus bug tracker (bugs.scribus.net #17988–#17994) as `git format-patch` files against trunk r27875, plus `TICKETS.md` with the report texts. The same commits are on the `macos/ui-fixes` branch.
- `AUDITORIA_MACOS.md` (Spanish): build notes, dependency analysis and the investigation behind each fix.
