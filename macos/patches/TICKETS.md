# Scribus bug reports — drafts for bugs.scribus.net

All patches are against **trunk r27875** (git mirror `3ed5222d9`, 1.7.4.svn) and were produced with `git format-patch`.

Common environment for every report:

- **OS:** macOS 26.6 (Tahoe), Apple Silicon (arm64)
- **Qt:** 6.11.2 (Homebrew)
- **Scribus:** 1.7.4.svn, trunk r27875, built with CMake + Ninja

How to apply:

- `git apply <file>`, or `git am --keep-cr <file>`. `scribus/canvasmode_edit.cpp` uses CRLF line endings, so plain `git am` rejects 0001.
- 0006 depends on 0005. All other patches apply independently on r27875.
- All nine apply in order on a clean trunk, which was checked with `git am --keep-cr`.

Before filing, search Mantis for duplicates. Related tickets that are already known: #17705, #17926, #17952.

---

## Submission status (2026-10-01)

| Mantis | Ticket | Patches | Status |
|---|---|---|---|
| [#17988](https://bugs.scribus.net/view.php?id=17988) | macOS system light/dark switch | 0004, 0005, 0006 | sent |
| [#17989](https://bugs.scribus.net/view.php?id=17989) | Image frame drag after text editing | 0001 | sent |
| [#17990](https://bugs.scribus.net/view.php?id=17990) | Dictionary warning flood | 0002 | sent |
| [#17991](https://bugs.scribus.net/view.php?id=17991) | `--prefs` moves 1.5/1.6 prefs | — | duplicate of #17992, created without the attachment when Mantis' rate limit blocked the upload |
| [#17992](https://bugs.scribus.net/view.php?id=17992) | `--prefs` moves 1.5/1.6 prefs | 0003 | sent |
| [#17993](https://bugs.scribus.net/view.php?id=17993) | Optional PoDoFo effectively required | 0007, 0008 | sent |
| [#17994](https://bugs.scribus.net/view.php?id=17994) | GraphicsMagick link | 0009 | sent |

---

## 1. Dragging an image frame right after editing text moves the image inside the frame

- **Patch:** `0001-Edit-mode-clicking-an-image-frame-from-text-editing-.patch`
- **Category:** User Interface
- **Severity:** minor

**Steps to reproduce**

1. Create a text frame and an image frame with an image loaded.
2. Double-click the text frame and type something.
3. Without pressing Esc, click the image frame and drag it.

**Expected:** the image frame moves.

**Actual:** the image is moved inside the frame, which changes its offset. The frame stays where it was.

**Cause:** `CanvasMode_Edit::mousePressEvent()` handles a click outside the frame currently being edited by calling `SeleItem()`. If the new item is a text frame *or an image frame*, it stays in `modeEdit`. `CanvasMode_Edit::mouseMoveEvent()` then calls `moveImageInFrame()` for image frames. The patch keeps `modeEdit` only for text frames. Image frames go through the same path as other items: switch to `modeNormal` and forward the press. Editing image content is still entered with a double click.

**Tested:** the 5-step scenario above on macOS. Dragging moves the frame; a double click still edits the image offset; clicking text→text still continues editing.

---

## 2. "Dictionary files not found for language" printed on every spell-check pass

- **Patch:** `0002-Spell-check-warn-once-and-cache-misses-for-missing-H.patch`
- **Category:** General
- **Severity:** minor (console noise, repeated disk access)

**Steps to reproduce:** use a document language with no Hunspell dictionary installed (for example `es`), then type in a text frame.

**Actual:** the console fills with `Dictionary files not found for language: "es"`. One session printed it 33 times.

**Cause:** `HunspellManager::getDictEntry()` (spellcheckfunctions.cpp) caches the dictionaries it finds but not the ones it cannot find. Every pass re-runs several `QFile::exists()` calls over all spell directories, for the language and its alternative abbreviation, and warns again.

**Fix:** remember misses for 30 s and warn once per language per session. Misses expire, so a dictionary installed during the session (for example from the Resource Manager) is still picked up.

**Tested:** 33 warnings before, 1 after, in an equivalent session.

---

## 3. `--prefs <dir>` moves the user's 1.5/1.6 preferences out of the default profile

- **Patch:** `0003-Prefs-copy-instead-of-move-legacy-prefs-into-a-prefs.patch`
- **Category:** General
- **Severity:** major (another installed Scribus version loses its settings)

**Steps to reproduce (macOS)**

1. Have Scribus 1.6.x settings in `~/Library/Preferences/Scribus/`: `scribus150.rc` and `prefs150.xml`.
2. Start 1.7 with `--prefs /some/empty/dir`.

**Actual:** `scribus150.rc` and `prefs150.xml` are *moved* into `/some/empty/dir`. The next start of Scribus 1.6.x comes up with default settings.

**Cause:** `PrefsManager::copyOldAppConfigAndData()` migrates legacy files with `moveFile()` into `m_prefsLocation`. With `--prefs` that location is a separate profile.

**Fix:** when a custom prefs dir is in use, copy the legacy files instead. Migration into the default profile is unchanged.

**Tested:** in a sandboxed `HOME` with dummy `*150` files. The source files remain and the `--prefs` profile receives byte-identical copies (checked with `cmp`).

---

## 4. ScribusProxyStyle's event filter swallows QEvent::ThemeChange

- **Patch:** `0004-ScribusProxyStyle-don-t-swallow-QEvent-ThemeChange-o.patch`
- **Category:** User Interface
- **Related:** #17705, which introduced the filter
- **Severity:** minor

**Cause:** `ScribusProxyStyle::eventFilter()` returns `true` for every `ThemeChange` sent to `qApp`. In Qt 6, `QGuiApplicationPrivate::processThemeChanged()` sends `ThemeChange` only to `qApp`. `QGuiApplication::event()` then forwards it to the style hints and to every window, and `QWidgetWindow` passes it on to its widget, which re-polishes itself and sends `StyleChange` (qwidget.cpp, `QWidget::event`). Consuming the event means no widget is ever notified of a theme change, whether it comes from the system or from Preferences.

**Fix:** keep the Scribus handling (follow the system palette in "auto" mode) but let the event propagate.

**Tested:** a temporary trace in `ScribusMainWindow::changeEvent()` showed 0 `ThemeChange` events before the patch and 4 per appearance switch after it. On macOS there was no visual difference, because existing stylesheet workarounds already cover most widgets.

---

## 5. After a system light/dark switch, dock tabs keep the ADS stylesheet instead of the Scribus one

- **Patch:** `0005-Reapply-the-Scribus-stylesheet-after-a-palette-chang.patch`
- **Category:** User Interface
- **Related:** #17926 (same symptom, fixed there only for Preferences)
- **Severity:** minor

**Steps to reproduce (macOS, theme "auto")**

1. Start in dark mode.
2. Switch the system appearance to light, then back to dark.

**Actual:** the active dock tabs (Arrange Pages, Properties…) are grey in dark mode, and in light mode they blend into the tab bar.

**Cause:** Qt emits `QStyleHints::colorSchemeChanged` *before* it updates the application palette (`QGuiApplicationPrivate::handleThemeChanged`). The existing workaround in `initScMW()` reapplies the Scribus stylesheet from that signal, so it uses the old palette. `ApplicationPaletteChange` then reaches the top-level main window as a *posted* event (`QGuiApplication::event`). `QApplicationPrivate::handlePaletteChanged` sends it synchronously only to non-window widgets. The ADS dock manager's filter on the main window reacts to that event by reloading ADS's bundled stylesheet over the Scribus one. Queueing the reapply from `colorSchemeChanged` is not enough; I tried it and it still runs before ADS.

**Fix:** reapply the Scribus stylesheet from `ScribusMainWindow::changeEvent(PaletteChange)`, queued. That event arrives right after the `ApplicationPaletteChange` has gone through the ADS filter. The call is skipped until `initScMW()` has created the styled widgets, because the splash screen processes events earlier.

**Tested:** dark → light → dark. Tabs match the startup styling in both modes, and CPU stays idle (no refresh loop).

---

## 6. Default scratch space colour does not follow a system theme switch (and the MDI title bar can stay dark)

- **Patch:** `0006-Follow-system-theme-changes-with-the-default-scratch.patch` (**apply after 0005**)
- **Category:** User Interface
- **Related:** #17952 (fixed there only for a theme set in Preferences)
- **Severity:** minor

**Steps to reproduce (macOS, theme "auto")**

1. Open a document in dark mode.
2. Switch the system appearance to light.

**Actual:** the canvas background around the page and the page palette grid stay dark. Both use `displayPrefs.scratchColor`.

**Cause:** by the time `ScribusProxyStyle::setApplicationTheme()` runs from the `ThemeChange` filter, Qt has already replaced the palette. The old Window colour is therefore no longer available to recognise the default scratch colour, and nothing repaints the views or the page grid.

**Fix:** in the same `PaletteChange` handler as patch 0005, remember the previous Window colour. If the scratch colour still matches it (or already matches the new one), switch it to the new Window colour and repaint the page grid and the document views, as `slotPrefsOrg()` does. A custom scratch colour is left alone.

The patch also resends `PaletteChange` to each `QMdiSubWindow`. It caches its title bar palette on `PaletteChange` (`QMdiSubWindowPrivate::titleBarPalette`), and after starting in dark and switching to light the document title bar otherwise stayed dark, even though the subwindow palette itself was correct (verified with a trace).

**Tested:** started both in dark and in light mode, then switched both ways. Canvas background, page grid and document title bar follow the theme, and CPU stays idle.

**Not covered:** a scratch colour saved in dark mode is still used when the next session starts in light mode, because there is no previous palette to compare with at startup.

---

## 7. Build: optional PoDoFo is effectively required

- **Patches:**
  - `0007-FindLIBPODOFO-don-t-make-pkg-config-lookup-of-PoDoFo.patch`
  - `0008-importai-only-add-PoDoFo-include-dir-when-PoDoFo-is-.patch`
- **Category:** Build System
- **Severity:** minor

**Steps to reproduce:** configure on a system without PoDoFo, with the default `WITH_PODOFO=ON`.

**Actual:**

1. `None of the required 'libpodofo;podofo' found` (FindLIBPODOFO.cmake uses `pkg_search_module(... REQUIRED ...)`, although `find_package(LIBPODOFO)` is not REQUIRED).
2. Once (1) is fixed, generation fails with `Found relative path while evaluating include directories of "importai": "LIBPODOFO_INCLUDE_DIR-NOTFOUND"`. The AI plugin adds `${LIBPODOFO_INCLUDE_DIR}` unconditionally, on top of its existing `if(HAVE_PODOFO)` block.

**Fix:** `QUIET` instead of `REQUIRED`, and drop the unconditional include entry.

**Tested:**

- Clean configure without PoDoFo: succeeds, with "PoDoFo NOT found - Disabling support for PDF embedded in AI".
- Clean configure and full build with PoDoFo 1.1.2: `HAVE_PODOFO 1`, links.

---

## 8. Build: GraphicsMagick only links from default linker paths

- **Patch:** `0009-Link-GraphicsMagick-by-full-path-from-pkg-config.patch`
- **Category:** Build System
- **Severity:** minor

**Steps to reproduce:** `-DWANT_GRAPHICSMAGICK=1` with GraphicsMagick outside the default linker paths (for example Homebrew in `/opt/homebrew/lib`).

**Actual:** `ld: library 'GraphicsMagick' not found` when linking the executable.

**Cause:** the executable links `${GMAGICK_LIBRARIES}`, which `pkg_check_modules()` fills with bare names. The intended `link_directories(${GMAGICK_LIBRARY})` uses a variable that `pkg_check_modules()` never sets.

**Fix:** link `${GMAGICK_LINK_LIBRARIES}` (full paths, CMake >= 3.12; Scribus requires 3.16) and drop the ineffective `link_directories()`.

**Tested:** clean full build without extra linker flags. The executable links `/opt/homebrew/opt/graphicsmagick/lib/libGraphicsMagick.3.dylib`.

---

*The patches include a `Co-Authored-By: Claude` trailer: they were prepared with AI assistance (Claude Code) and reviewed and tested by the submitter.*
