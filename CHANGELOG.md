# Changelog

## 0.4.25 — 2026-10-07

- Expanded the top of `tmux-integration/screen-compat.c` into a maintainer-oriented architecture guide with fixed-width control-flow diagrams, a complete one-line-per-function purpose index, and a second complete one-line-per-function usage/caller index. The header also records the mapping-policy and tmux/BSD-C style contracts that future changes should preserve.
- Split the remaining mixed-purpose native-C command families along semantic boundaries: pane/display operations are separate from session/client lifecycle commands, copy/buffer operations are separate from logging/monitoring, and saved-layout translation is separate from display/status inspection. This keeps the mapping branches flat and auditable while reducing the largest command-family functions.
- Added small parser helpers for consuming required operands and replacing deferred unsupported-option diagnostics, removing repeated cursor/buffer-management mechanics from the short-option parser without hiding Screen's option grammar behind a generic framework.
- Strengthened focused regressions so both top-of-file function indexes must exactly cover every `screen_compat_*` definition, and updated the readable-phase regression for the new semantic command families. Focused regressions are now 156 PASS.

## 0.4.24 — 2026-10-07

- Refactored `tmux-integration/screen-compat.c` for readability without changing the compatibility policy. The former ~1,260-line `screen_compat_xcommand()` is now a small dispatcher over named command families (`window`, `pane`, `data`, `config`, `status`, `access`, and `inspect`), and the former ~760-line top-level parser is separated into option decoding plus list, attach/detach, startup-policy, external-endpoint, and session-creation phases.
- Replaced shell-origin C state names such as `Aflag`, `Uflag`, `mflag`, and `xflag` with descriptive names, introduced enums for translator mode/detach/attach-strength states, centralized repeated optional tmux argument construction in `screen_compat_cmd_add_option()`, and centralized the repeated info-format string. Added comments describing the translation layers and the purpose of each command family.
- Added a focused regression locking the readable native-C phase structure, descriptive state naming, 80-column limit, and trailing-whitespace cleanliness. Updated the executable-mapping fall-through regression to accept helper functions that return a handled status. Focused regressions are now 155 PASS.
- Revalidated the refactor against the independent shell implementation: 683/683 native-C dry-run placement variants have zero divergences, and a separate normal-execution differential passes all 228 canonical cases.

## 0.4.23 — 2026-10-07

- Hide successful INVALID-series (`Z001`-`Z010`) rows from the aggregate interface-equivalence console by default while continuing to execute the full strict validity corpus and include it in summaries, exit status, and detailed equivalence logs.
- Add `--show-invalid-test-series` to restore the successful INVALID rows. A failed INVALID-series case is always surfaced even when the success rows are hidden so validation failures cannot disappear from the terminal.
- Added a focused regression that locks the runner flag, environment handoff, and equivalence-display filtering contract. Focused regressions are now 154 PASS.

## 0.4.22 — 2026-10-07

- Hide successful built patched tmux integration-check sections by default. `--show-integration-checks` restores the full section; any failure automatically reveals the section banner, failed check row, and its indented diagnostics while the complete integration log is still written.
- Hide successful tmux behavior-test sections by default. `--show-behavior-test` restores full behavior output; failures automatically reveal only the banner and failed check rows/diagnostics while dedicated behavior logs remain complete.
- Render project-owned paths relative to the repository root on the terminal (`./logs/...`, `./build/...`, and so on) while preserving absolute paths in the underlying component and console-source logs before terminal formatting.
- Print the test-log archive path only once by retaining the final `LOG_ARCHIVE:` summary entry and removing the duplicate `Log archive:` success line.
- Added focused regressions covering both opt-in display flags, failure-only reveal behavior, terminal path relativization, and archive-path deduplication. Focused regressions are now 153 PASS.


## 0.4.21 — 2026-10-07

- Make translator INVALID/unknown-syntax rejection strict-only. Normal mode now stops an unrecognized validation path successfully without emitting INVALID or executing a guessed tmux command; `--strict` preserves the explicit INVALID diagnostic and exit status 64.
- Keep the invalid-syntax oracle/equivalence corpus active by adding `--strict` internally for invalid test cases while leaving the displayed Screen command unchanged.
- Align both pipe columns in the built patched tmux integration table by reserving widths for the longest labels, descriptions, and Screen invocations.
- Added regressions for permissive normal-mode validity handling, strict INVALID retention, hidden strict validation in the equivalence corpus, and built-integration column widths. Focused regressions are now 149 PASS.


## 0.4.20 — 2026-10-07

- Changed focused-regression console output to show failures only by default. `--show-regression-test-pass` restores individual `[PASS]` rows; the regression log continues to record every PASS/FAIL result regardless of console filtering.
- Made aggregate terminal formatting line-flushed so equivalence rows, summaries, and other component output are displayed as they arrive instead of being held by AWK pipeline buffering. The equivalence workers remain buffered/parallel internally, but ready mapping rows are emitted one line at a time.
- Made normal build progress incremental while preserving the existing compact layout: stage headers flush immediately, and width-aware `Compiling ...` lines are emitted as soon as each line fills rather than waiting for the entire compile stage. Configure summaries remain grouped at configure completion.
- Added focused regressions covering the opt-in PASS flag and incremental console/build formatter contracts. Focused regressions are now 145 PASS.

## 0.4.19 — 2026-10-07

- Fixed native-C normal-execution control flow for executable `APPROX` mappings. `screen_compat_approx_exec()` rewrites tmux argv in-process and returns, so callers must stop parsing immediately; 0.4.18 could otherwise fall through into a later fallback branch after installing the translated command. The reported `hardstatus off` case therefore emitted the intended APPROX mapping and then an erroneous UNSUPPORTED diagnostic/exit status.
- Audited every executable `APPROX` and helper-backed `EXTERNAL` call site in `screen-compat.c` and made each parser branch return immediately after argv installation (or naturally end the helper function). This preserves the selected tmux argv without allowing later mapping logic to run.
- Strengthened source regression coverage so executable native-C mapping helpers must be followed by parser termination, and strengthened the compiled hardlink APPROX integration check to reject any spurious UNSUPPORTED diagnostic. Focused regressions are now 142 PASS.

## 0.4.18 — 2026-10-06

- Fixed the native tmux module's printf-format annotation to use tmux's own `printflike(a, b)` macro and placement style. The 0.4.17 module used the nonexistent `__printflike`, which caused `screen-compat.c` to fail at its first annotated declaration under the real tmux 3.7c headers and produced a cascade of parser errors.
- Strengthened regression coverage to require `static void printflike(2, 3)` and reject any `__printflike` use in `screen-compat.c`. The validation harness now mirrors tmux's actual annotation macro instead of defining the incorrect spelling.
- Made the native-module layout regression tolerant of harmless legacy files left behind by overlaying a newer GitHub ZIP onto an older extracted tree. The active patch/builder paths are still required to use only the native `screen-compat.c` integration.
- Updated the README's one-command ZIP workflow to remove an existing `screen-to-tmux-translator-main` directory before extraction, preventing removed files from older releases from surviving a repeated download/build cycle.

## 0.4.17 — 2026-10-06

- Replaced the compiled tmux hardlink's embedded POSIX-shell payload and fork/pipe shell bridge with a self-contained native C translator in `tmux-integration/screen-compat.c`. Screen-style argv is now parsed and rewritten entirely in-process before tmux parses its own command line; the compiled path no longer invokes `/bin/sh` or shell helper utilities.
- Ported the complete tested compatibility policy to native C while preserving the canonical shell interfaces as an independent reference. Differential equivalence covers all 683 generated placement variants and requires the compiled C translator to match reference status, diagnostics, and dry-run argv.
- Kept the upstream-facing tmux patch minimal: `Makefile.am` compiles `screen-compat.c`, `tmux.h` declares `screen_compat_translate()`, and `tmux.c` calls it once before normal option parsing. The C module uses only headers already used by tmux and follows tmux declaration, indentation, naming, wrapping, and xmalloc conventions.
- Added regression coverage that rejects any return of the embedded-shell implementation (`screen_compat_shell_source`, `/bin/sh`/`_PATH_BSHELL`, fork/pipe/exec/wait bridge code) and restricts the module include set to existing tmux headers. Updated runtime documentation to distinguish POSIX-shell source interfaces from the shell-independent compiled hardlink.

## 0.4.16 — 2026-10-06

- Reworked `bin/screen-function-source-minified.oneliner.sh` so its first token is a literal `screen () { ... }` POSIX shell function containing the main Screen-to-tmux translation/parser body. Helper functions follow afterward on the same physical line, and `screen2tmux () { screen "$@"; }` is now the small compatibility entry point instead of the main implementation.
- Kept the one-liner free of eval-based reconstruction while preserving its one-physical-line paste-to-run form, direct-execution sourcing guidance, dry-run/strict behavior, and equivalence with the other packaged interfaces for the supported test matrix.
- Added regression coverage requiring the minified one-liner to begin with the `screen ()` definition and to keep the main parser body there rather than delegating `screen` immediately to `screen2tmux`.

## 0.4.15 — 2026-10-06

- Fixed the patched-tmux builder preflight after the 0.4.14 native-module refactor: the stale `TMUX_C_PATCH` reference is replaced with the defined `TMUX_PATCH` path, so `set -u` no longer aborts before checkout/build. The diagnostic now names the missing tmux integration patch rather than the retired tmux.c-only patch.
- Strengthened the native C module regression to require the real `TMUX_PATCH` preflight and to fail if `TMUX_C_PATCH` appears anywhere in `scripts/build-tmux-one.sh`, directly covering the release failure reported by an ordinary-user `sh run-tests.sh --build`.

## 0.4.14 — 2026-10-06

- Refactored the patched-tmux integration into a normal tmux-style C module, `screen-compat.c`, instead of directly including an extensionless implementation file from `tmux.c`. The zero-fuzz patch now makes small conventional edits to `Makefile.am`, `tmux.h`, and `tmux.c`: compile the module, declare `screen_compat_translate()`, and invoke it before tmux command-line parsing.
- Reworked the C bridge to follow tmux coding conventions: `screen_compat_*` names, tmux-style declaration/indentation, `err(3)`/`errx(3)` for the pre-parser fatal path, `sigaction(2)` for SIGPIPE handling, `_PATH_BSHELL` for the system shell, and `strtonum(3)` for bounded argv-count parsing. The canonical POSIX translator remains embedded as generated data, preserving translator behavior rather than maintaining a second independent C mapping implementation.
- Updated the source-footprint contract to exactly three modified upstream files plus one added `screen-compat.c`, and added regression/syntax coverage for the native module layout.

## 0.4.13 — 2026-10-06

- Rebuilt `bin/screen-function-source-minified.oneliner.sh` as a literal one-line POSIX shell program containing real function definitions instead of an `eval "$(printf ... )"` reconstruction wrapper. Its translator-extension argv filtering also uses direct POSIX positional-parameter rotation instead of `eval "set -- ..."`. The artifact now contains an actual `screen () { screen2tmux "$@"; }` definition and real helper/`screen2tmux` functions while remaining one physical line and paste-to-run.
- Kept the one-liner behavior equivalent to the canonical translator, including direct-execution sourcing guidance, `SCREEN2TMUX_NO_SCREEN_FUNCTION`, dry-run/strict semantics, and all translation classes.
- Added regression coverage requiring the minified one-liner to contain a literal POSIX `screen ()` function, contain no eval-based shell reconstruction path, and expose both callable `screen` and `screen2tmux` entry points after sourcing.

## 0.4.12 — 2026-10-06

- Changed the equivalence-interface banner to print each interface and its path on one line, with project-local paths rendered relative to the repository root (for example `screen-function-source.sh (reference) (bin/screen-function-source.sh)` and `tmux-3.7c screen hardlink (build/tmux-3.7c-patched/install/bin/screen)`). Detailed equivalence logs continue to retain the absolute paths used for execution.
- Fixed aggregate `run-tests.sh` terminal colorization so the complete right-hand mapping result after `->` is repainted with the semantic class color after the plain-text log has been written: exact green, approx yellow, unsupported/invalid red, moot cyan, and external magenta. This fixes the real runner path that 0.4.8's lower-level formatter regression did not exercise.
- Added a focused regression against the parent runner's actual terminal colorizer, covering all six result classes. Focused regressions are now 135 PASS.

## 0.4.11 — 2026-10-06

- Changed translator dry-run command rendering to omit unnecessary single quotes. Ordinary shell-safe argv words now print bare (for example `tmux attach-session`), while empty arguments, whitespace, shell metacharacters, `#`, and control bytes remain quoted/escaped so the displayed command stays copy-pasteable.
- Confirmed and regression-locked selectorless `screen -r` as an executable APPROX mapping: outside `--strict` it warns and runs `tmux attach-session`; under `--strict` it remains advisory.
- Updated the test-matrix parser and README dry-run example for the new shell-safe display format. Focused regressions are now 134 PASS.

## 0.4.10 — 2026-10-06

- Reordered the README for immediate use: directly after the one-line project description it now links `bin/screen-function-source-minified.oneliner.sh` and embeds that file's exact paste-to-run function declaration in a shell code block. The next section is the one-command GitHub ZIP download/build/test workflow.
- Changed bare `sh run-tests.sh --build`, `sh build_tmux_patched.sh`, and `sh build_tmux.sh` defaults from tmux 3.7d to the tmux 3.7c released baseline. Added `build_tmux_3.7c.sh` and `build_tmux_3.7c_patched.sh`; the existing 3.7d and `latest` front ends remain available.
- Pinned the default 3.7c request to `refs/tags/3.7c`, checked out detached, rather than following the mutable `release_3.7c` branch. Every build records the resolved commit in `BUILD-INFO`; `SCREEN2TMUX_TMUX_3_7C_PIN` or `TMUX_PIN_COMMIT` may provide an exact commit for content-addressed audits.
- Retained the supplied tmux 3.7d baseline's stronger archive-derived exact commit pin (`e9634d40749a5ae330aabf5aa46a81505b094a6b`) for historical reproducibility.
- Added/updated regression coverage for the 3.7c default, release-tag pin resolution, the new version-specific wrappers, and the unchanged 3.7d exact pin.

## 0.4.9 — 2026-10-06

- Fixed the build-dependency automatic-install regression so it supplies a fake `sudo` wrapper as well as a fake package manager. Running the test suite as an unprivileged user can no longer reach the real `sudo`, prompt for a password, or fail because the test runner lacks administrative rights.
- Improved missing-build-dependency diagnostics. The builder already names the missing commands/development libraries; it now also prints a copyable package-manager command that a user can give an administrator (`sudo apt-get update && sudo apt-get install ...` on Debian/Ubuntu, with equivalent `dnf`, `yum`, and `apk` forms). Homebrew guidance remains unprivileged.
- Clarified the interactive installer prompt so users are told in advance that automatic installation through a system package manager may invoke `sudo`.
- Added regressions requiring the administrator command to appear in both declined and automatic-install dependency paths.

## 0.4.8 — 2026-10-06

- Colorized the complete right-hand mapping result with the same semantic class color used by the case label. `UNSUPPORTED` results are red, `MOOT` results cyan, executable/advisory `APPROX` results yellow, `EXTERNAL` results magenta, `INVALID` results red, and exact tmux mappings green.
- Added concrete helper-backed `EXTERNAL` mappings for direct serial-device startup and Screen `//telnet`: tmux now launches `picocom` or `telnet` as the pane process when that helper is installed. Dry-run always shows the concrete tmux argv without requiring the helper.
- Preserved `EXTERNAL` classification for those mappings because tmux itself still provides only the PTY/session host; the external client implements the serial or Telnet protocol. Missing helpers return status 5 without invoking tmux.
- Extended `--strict` so executable `EXTERNAL` mappings also remain advisory and never invoke tmux. Runtime serial controls such as `break` and `flow` remain advisory `EXTERNAL` operations because no helper-independent tmux command safely reproduces their Screen endpoint semantics.
- Added regressions for helper-backed Telnet/serial execution, strict suppression of executable `EXTERNAL`, concrete external dry-run argv, IPv6 Telnet argument preservation, and class-matched mapping colors. Focused regressions are now 130 PASS.
- Extended the compiled patched-tmux integration suite with real helper-backed `EXTERNAL` execution and strict-EXTERNAL suppression checks; a built version now runs eight hardlink integration checks.

## 0.4.7 — 2026-10-06

- Added translator-owned `--strict`, accepted anywhere in the argument vector like `--dry-run`. `EXACT` mappings retain normal behavior; every `APPROX` mapping becomes advisory, returns status 3, and never invokes tmux. `--strict --dry-run` still prints the closest tmux argv for inspection without executing it.
- Added focused and compiled-hardlink regressions proving strict mode blocks executable approximations while preserving exact mappings.
- Made the default tmux 3.7d build reproducible by pinning it to `e9634d40749a5ae330aabf5aa46a81505b094a6b`, the commit recorded in the supplied `release_3.7d` GitHub ZIP, instead of following the moving `release_3.7d` branch. `latest` remains intentionally moving and explicit pin overrides remain available.
- Corrected tmux master source provenance to the supplied archive SHA-256 `e4deec4f6914e3f50047d5cf1d6f50a435f1da18635f925545301b46fb96a4d8` and GitHub ZIP commit comment `8f25579c5aef8d93924a20681f394e2a582fd3ad`; updated audited file hashes that changed with that snapshot.
- Documented the supplied 3.7d archive hash and key file hashes in `docs/SOURCE-BASIS.md`.
- Changed internal `.sh` child invocations to explicit `sh SCRIPT ...`, including build wrappers, aggregate test components, and standalone script equivalence calls. This avoids `Permission denied` failures when executable bits are lost in GitHub ZIP extraction. `sh run-tests.sh --build latest` remains the supported entry point.
- Documented the POSIX-shell runtime dependency, including the compiled `screen` hardlink's use of `/bin/sh` for translation.
- Repositioned the README around creating a Screen-compatible command-line identity for tmux and embedded the exact contents of `bin/screen-function-source-minified.oneliner.sh` as a paste-to-run function.

## 0.4.6 — 2026-10-05

- Changed `APPROX` from an always-advisory class into a warning-preserving execution policy. When an inexact Screen operation has a concrete useful one-command tmux substitute, the translator now prints the `APPROX` reason/suggestion and then executes that tmux command. Dry-run prints the warning followed by the translated command.
- `screen -r [session]` now demonstrates the intended behavior directly: it warns that Screen normally refuses an already-attached session while tmux supports multiple clients, then executes the closest `tmux attach-session` mapping.
- Enabled the same warning-then-execute behavior for other concrete approximations including session listing and named creation, named `-R/-RR` attach-or-create paths, attach preselection, `-U`, region split/focus/only, collapse, several query/inspection commands, namespaced copy-buffer operations, simple key bindings, hardstatus/caption operations, and layout inspection/selection.
- Promoted additional concrete approximations such as quiet `-ls` via `has-session`, Screen StartAt window creation via exact-index `new-window`, `number` via non-destructive `move-window`, `lockscreen`, logging on/off via `pipe-pane`, `unbindall`, `altscreen`, ACL add/delete via `server-access`, and `dinfo`. Their warnings explicitly call out failure modes or broader tmux scope before execution. Remaining advisory cases are those that still need an indeterminate direction/client, multiple coordinated commands, shell redirection, or unavailable Screen runtime state.
- Added an internal `approx-run` oracle expectation so executable approximations remain displayed as `approx` while tests require their successful translated-command status instead of the advisory exit status 3. The corpus now marks 80 base cases as executable approximations; the unified 5-interface matrix still covers all 683 dry-run placements per interface.
- Added a focused normal-execution regression proving `screen -r work` emits the approximation warning and then invokes `tmux attach-session -t work`.
- Extended built patched-tmux integration checks with a real executable-APPROX state change: the `screen` hardlink runs an approximate `hardstatus off` translation and the sibling tmux binary verifies the isolated session's `status` option became `off`.
- Updated help and documentation so exit status 3 means advisory/uncertain approximation; executable approximations return the underlying tmux status in normal mode.

## 0.4.5 — 2026-10-05

- Replaced the old `bin/screen.sh` wrapper with a genuinely self-contained executable that embeds the translator implementation and can run after being copied by itself with no sibling files.
- Added `bin/screen-function-source.oneliner.sh` and `bin/screen-function-source-minified.oneliner.sh`. Each is exactly one physical line, is sourced with the POSIX dot command, and defines the same callable `screen()` and `screen2tmux()` functions as its corresponding normal source file.
- Extended the source-file direct-execution guard to the two one-line filenames so `sh file` still explains that sourcing is required.
- Extended the unified equivalence matrix to both one-line interfaces. With no compiled tmux hardlink present, the packaged matrix now has five interfaces and performs 2732 non-reference comparisons across 683 placement variants with zero allowed divergences.
- Added regressions proving standalone isolation, one-line physical layout, sourceability, and direct-execution behavior. Focused regressions are now 113 PASS.
- Translation semantics are unchanged from 0.4.4.

## 0.4.4 — 2026-10-05

- Made normal configure output more coherent by normalizing and de-duplicating Autoconf probe names. Header usability/presence/final triples collapse to one header name, common `whether`/`working` boilerplate is removed, cached booleans are classified with yes/no, common tool labels are shortened, and internal `.screen2tmux-cc` paths are replaced with the actual compiler in displayed values.
- Collapsed successful compiler progress into one console-width-aware `Compiling ...` stream containing `file.c ... [OK]` entries, instead of printing one terminal row per source file. Raw compiler/build output remains unchanged in `build.log`.
- Added `build_tmux_patched.sh`, a generic patched-only companion to `build_tmux.sh`. It accepts the same version lists and verbosity options and defaults to patched tmux 3.7d.
- Changed `run-tests.sh --build` to compile patched variants only by default. Added `--compile-original` to explicitly request the previous original+patched pair for every requested version.
- Added focused regressions for the patched-only builder, `--compile-original` selection, normalized configure rendering, and grouped compile progress. Focused regressions are now 108 PASS. Translation semantics are unchanged from 0.4.3.

## 0.4.3 — 2026-10-05

- Reworked normal build configure output. Autoconf checks are grouped into width-aware `Configure yes`, `Configure no`, and comma-separated `Configure values` summaries; the leading `checking for ` text is removed. In color mode, successful names are green and failed names are red without coloring the whole line.
- Combined the aggregate Screen CLI/oracle validation and interface-equivalence matrix into one pass. The Screen 5.0.2 oracle and expected reference exit class are now checked inside the equivalence harness, so `run-tests.sh` prints each of the 228 Screen cases only once while still exercising all 683 first/middle/last placements per selected interface. The standalone `tests/test-screen-cli.sh` remains available for detailed per-invocation diagnostics.
- Equivalence interfaces are now printed one per line with their full paths. Removed the redundant `N-way` suffix from every case row.
- Tightened mapping columns and aligned every `->` marker so tmux commands start in the same column. Shortened the longest serial-device description from `direct serial tty device command treated as initial process argument` to `direct serial tty device`.
- Live tmux behavior checks now run once per discovered version against the patched tmux only. Pristine original builds remain build/reference baselines and are no longer rerun through the same behavior suite. If no patched build exists, the runner still falls back to a system tmux.
- Fixed original-build discovery display so the build directory is retained instead of appearing as an empty `()`.
- Added regressions for configure grouping/color scope, combined matrix execution, aligned arrows, full-path interface listing, patched-only behavior runs, and original build-registry field preservation. Focused regressions are now 106 PASS.
- Translation semantics are unchanged from 0.4.2.

## 0.4.2 — 2026-10-05

- Added `build_tmux.sh`, a generic POSIX front end that accepts one or more tmux versions/refs (comma- or space-separated), defaults to 3.7d, and builds both original and patched variants for every requested version. `latest` resolves upstream master/main; other values accept exact refs and the historical `release_VERSION` branch convention.
- Moved generated source trees under `src/tmux-*` and generated build/install trees under `build/tmux-*`. The four legacy one-variant build entry points remain available and use the new layout.
- Added `--verbosity quiet|normal|verbose` to the generic builder and `run-tests.sh`, with `normal` as the default. Normal build output replaces huge repeated compiler command lines with concise, selectively colorized stage output and `Compiling file.c ... [OK]` rows while retaining the detailed raw build transcript in each build directory.
- Added `run-tests.sh --build [VERSION ...]`. `--build` with no version builds 3.7d; comma- and space-separated lists are supported. The runner continues into testing after build failures so every successfully completed build can still be exercised.
- Generalized build discovery and interface equivalence. Every successful patched build under `build/` is automatically added as a compiled `screen` equivalence interface, rather than hardcoding only 3.7d/latest. Every successful original or patched tmux binary also receives the isolated live behavior suite.
- Added focused regressions for the generic builder default pair, comma-separated version lists, new `src/`/`build/` layout, concise normal build output, `run-tests --build`, dynamic build discovery, and default normal verbosity. Focused regressions are now 102 PASS.
- Translation semantics are unchanged from 0.4.1.

## 0.4.1 — 2026-10-05

- Reworked translation-oriented test rows to `result | description | screen command -> tmux command`, with both pipe columns aligned.
- Removed gratuitous per-argument single quotes from displayed commands. Arguments remain quoted only when shell protection is actually needed, such as spaces, `#` format strings, backslashes, or embedded quotes.
- Unified interface equivalence around `screen-function-source.sh` as the canonical reference. By default the matrix now includes the canonical sourced function, minified sourced function, standalone `screen.sh`, and each discovered patched tmux hardlink named `screen`.
- Every selected interface now runs the complete 683 first/middle/last placement matrix. A fully matching Screen case prints one PASS row regardless of interface count; failures print the case once and then only the interface/placement combinations that diverged.
- Added `run-tests.sh --equivalence NAME` / `--equivalence-only NAME`, repeatable for explicit interface subsets, plus `--list-equivalence-interfaces`. The default remains all available interfaces.
- `run-tests.sh` now names the active equivalence interfaces in the startup header and the equivalence section repeats the resolved list.
- Reduced duplicate compiled-build output: the central equivalence suite owns the full 683-variant compiled-hardlink comparisons; the built-tmux section now performs only hardlink identity, compiled dry-run smoke, and real-execution smoke checks.
- Added regressions for two-column alignment, description-before-command ordering, minimal command quoting, equivalence selection options, and aggregated divergence reporting. Focused regressions are now 97 PASS.
- Translation semantics are unchanged from 0.4.0.

## 0.4.0 — 2026-10-05

- Split the old two-build drivers into four independent build scripts: `build_tmux_3.7d.sh`, `build_tmux_3.7d_patched.sh`, `build_tmux_latest.sh`, and `build_tmux_latest_patched.sh`. Each script rebuilds only its own variant from scratch.
- Changed the default build layout to four preserved source trees plus four separate build/install trees: `source-tmux-3.7d`, `source-tmux-3.7d-patched`, `source-tmux-latest`, `source-tmux-latest-patched`, and matching `build-tmux-*` directories. Patched build installs still create `screen` as a hardlink to `tmux`.
- Latest original/patched builds synchronize to the same Git commit whenever the counterpart source tree already exists; `TMUX_LATEST_COMMIT` can pin the exact commit explicitly.
- Replaced the previous two-snapshot builder with `scripts/build-tmux-one.sh`, retaining dependency prompting/automatic installation, zero-fuzz patching, and the one-modified-file plus one-added-file source-footprint check.
- Translation-oriented test rows now show one aligned `screen -> tmux` mapping per Screen case. Successful first/middle/last dry-run placements are still all executed but only one canonical mapping is displayed. Non-exact classes explicitly show that no automatic tmux command is executed.
- Added `run-tests.sh --quiet` to hide only the mapping columns while keeping ordinary PASS/FAIL progress.
- Added `--truncate-lines N` (plus the requested typo-compatible `--trunkate-lines N` alias). Without an explicit width, `run-tests.sh` measures the terminal width once at startup and truncates only terminal display lines to that width. Full logs and the archived console transcript are written before truncation and remain complete.
- Updated patched-build discovery for the new `build-tmux-3.7d-patched` and `build-tmux-latest-patched` directories.
- Added focused regressions for four-script layout selection, aligned mapping columns, quiet mapping suppression, terminal-width/truncation support, and new build discovery. Focused regressions are now 92/92.
- Regenerated the minified translator and embedded tmux translator from the canonical 0.4.0 engine. Translation semantics are unchanged from 0.3.9.

## 0.3.9 — 2026-10-05

- Reduced successful test-console noise. The CLI/oracle suite still executes all 683 `--dry-run` placement variants (`first`, `middle`, and `last` where applicable), but when all placements for one Screen case pass it now prints a single `[PASS]` line for that case. If a placement fails, the failing placement is printed explicitly. Detailed per-placement records remain in the timestamped CLI log.
- Applied the same compact-success policy to the built patched-tmux hardlink suite: all 683 hardlink variants are still compared byte-for-byte, but successful placements collapse to one console PASS per Screen case; failing placements remain individually identified.
- Versioned the per-run log archive filename. `run-tests.sh` now writes `screen-to-tmux-translator-<VERSION>-test-logs-<YYYYMMDD-HHMMSS>.zip`, making archives self-identifying when copied away from the project directory.
- Fixed the live tmux `alternate-screen` behavior test for tmux 3.7d. `show-options -p -v` only reports a pane-local override, so an inheriting pane legitimately produced an empty value. The test now uses `show-options -p -A -v` to ask for the effective inherited value before comparing pane scope. The two supplied 0.3.8 runs otherwise passed; their sole failure was this test-harness assumption.
- Translator semantics are unchanged from 0.3.8.

## 0.3.8 — 2026-10-05

- Build dependency handling is now interactive by default. When required commands or libevent/ncurses development files are missing, `build_tmux_3.7d.sh` and `build_tmux_latest.sh` detect a supported package manager (`apt-get`, `dnf`, `yum`, `apk`, or Homebrew), display the package set, and ask whether to install it automatically. Yes installs and rechecks dependencies before continuing; no/default cancels without modifying the system.
- Added `SCREEN2TMUX_AUTO_INSTALL=ask|yes|no` for interactive/automated dependency policy and `SCREEN2TMUX_PACKAGE_MANAGER` as an explicit package-manager override. Root or `sudo` is used only for system package managers; Homebrew is never run through `sudo`.
- Added `SCREEN2TMUX_DEPENDENCY_CHECK_ONLY=1` as a test/diagnostic mode that exits after the dependency phase. Focused regressions verify both decline behavior and the automatic-install/recheck path using a fake `apt-get`, so the test suite never installs packages.
- `screen --help` is now a successful translator-owned compatibility help page. It follows the GNU Screen 5.0.x option surface, documents `--dry-run`/`--dryrun`, annotates options and common `-X`/`-Q` command families with translation classes, and explains tmux-underneath differences such as multi-client attach behavior, unique session names, pane-vs-region semantics, server-wide buffers/key tables, and the lack of stale per-session sockets.
- Help colorization is selective: headings and status tokens are colored, not entire rows. `SCREEN2TMUX_COLOR` and `NO_COLOR` use the same policy as diagnostics/tests.
- Changed the top-level `--help` test case from `UNSUPPORTED` to successful compatibility help while leaving native Screen version reporting (`-v`/`--version`) unsupported. Internal Screen `-X help` remains an approximation of Screen key-binding help and is unchanged.
- Regenerated the minified source and embedded tmux translator from the canonical 0.3.8 engine. The full 683 CLI/oracle matrix and 912 interface-equivalence comparisons remain clean; focused regressions are now 83/83.

## 0.3.7 — 2026-10-05

- Added `build_tmux_3.7d.sh`. It downloads the `release_3.7d` branch from the official tmux Git repository, verifies required build tools/libraries, snapshots one exact commit twice, builds an untouched original tree from scratch, then independently builds a Screen-compat patched tree from scratch.
- Added `build_tmux_latest.sh`, using the same process against the current `master` branch each time it is run. The exact Git commit is recorded in `build/<name>/BUILD-INFO`.
- Added `scripts/build-tmux-variant.sh` as the shared POSIX build implementation. It checks Autotools, compiler/make, yacc/bison, `pkg-config`, libevent 2.x, ncurses/terminfo, `patch`, and related utilities before downloading/building and prints distro-specific package hints on failure.
- Added `tmux-integration/screen-to-tmux-translator`, containing the full embedded compatibility layer, plus a minimal `tmux.c` patch. The build enforces the source-footprint contract before Autotools runs: exactly one existing upstream file (`tmux.c`) differs and exactly one new upstream file (`screen-to-tmux-translator`) is added.
- Patch application uses `patch --fuzz=0`. If current `master` no longer has the two known integration points, the latest-build script stops with a specific error rather than guessing where to inject compatibility code.
- Patched installs create `bin/screen` as a hardlink to the patched `bin/tmux`; original and patched `tmux -V` output must match before a build is accepted.
- Standard build locations are `build/tmux-3.7d/{original,patched}` and `build/tmux-latest/{original,patched}`. Each build records source URL, branch, commit, version, binary paths, and hardlink inode metadata.
- Added `tests/test-built-tmux-screen.sh`. When a completed patched build is discovered, it verifies hardlink identity, compares the actual hardlink named `screen` byte-for-byte and exit-status-for-exit-status against the canonical translator across all 683 dry-run placement variants, then performs an isolated real-execution smoke test.
- Extended `tests/interface-equivalence-worker.sh` with `standalone-full` mode so compiled/hardlinked Screen entry points can run the complete 683-placement corpus with bounded parallelism.
- `tests/test-tmux-behavior.sh` now accepts `TMUX_BIN=/path/to/tmux`, allowing the same isolated behavioral checks to run against each patched build instead of only a system tmux.
- `run-tests.sh` auto-detects completed 3.7d/latest builds, adds the full hardlink `screen` matrix, reruns live tmux behavior tests against each patched tmux, timestamps the extra logs, and includes every generated test log in the per-run ZIP.
- Verified the minimal tmux.c patch with zero fuzz against the supplied 3.7d tree and the available newer development tmux tree. The embedded translator source is byte-for-byte identical to `bin/screen-function-source.sh`; a strict C harness matched all 683 canonical dry-run outputs.
- Core translator semantics remain unchanged from 0.3.6.

## 0.3.6 — 2026-10-04

- Added `bin/screen-function-source-minified.sh`, a mechanically minified sourceable equivalent of `screen-function-source.sh`. Minification removes comments and blank lines only; executable/content lines are preserved.
- Extended the source-file direct-execution guard to both canonical and minified filenames; either must be loaded with the POSIX dot command to leave `screen()` in the current shell.
- Added `tests/test-interface-equivalence.sh` plus an internal worker. Canonical and minified source variants are compared byte-for-byte with identical exit statuses across all 683 dry-run placement variants.
- Added three-way parity checks for all 228 base Screen command cases across canonical source, minified source, and standalone `screen.sh`, plus a normal-execution comparison using an isolated stub `tmux`.
- Added bounded parallelism for standalone equivalence generation (`SCREEN2TMUX_EQUIV_JOBS`, default 8) so complete three-interface coverage does not excessively slow the suite.
- `run-tests.sh` now runs the interface-equivalence layer, timestamps its log, reports `LOG_EQUIVALENCE`, and includes that fifth log in the per-run ZIP archive.
- Added focused regressions for sourcing and direct-execution behavior of the minified source file, bringing the focused suite to 77 checks.
- Translation semantics are unchanged from 0.3.5.

## 0.3.5 — 2026-10-04

- Renamed the source-oriented translation engine from `bin/screen-to-tmux.sh` to `bin/screen-function-source.sh`. It remains the single implementation that defines `screen2tmux()` and, by default, the callable POSIX `screen()` shell function.
- Updated `bin/screen.sh`, the CLI/oracle harness, regression suite, documentation, and source comments to use the new canonical source filename.
- Added an explicit direct-execution guard: `sh bin/screen-function-source.sh` exits `2` with the portable instruction `. ./bin/screen-function-source.sh`, because a child POSIX shell cannot install a function into its parent.
- Added focused regressions proving that sourcing the file defines a working `screen()` function and that direct `sh` execution is rejected with the sourcing instruction, bringing the focused suite to 75 checks.
- Translation semantics are unchanged from 0.3.4.

## 0.3.4 — 2026-10-04

- Added `bin/screen.sh` as a standalone executable front-end that behaves like the `screen` command and delegates all translation semantics to the sourceable translation engine.
- Added `--dryrun` as an alias for `--dry-run`; either spelling may appear anywhere in the Screen argument vector and prints the translated tmux command instead of executing it.
- Kept one sourceable translation engine rather than duplicating its implementation in the command front-end.
- Added regressions proving `screen.sh --dryrun` prints the expected command and that `screen.sh` executes `tmux` by default when the translation is `EXACT`.
- Translation semantics are otherwise unchanged from 0.3.3.

## 0.3.3 — 2026-10-04

- Restored interactive ANSI colorization without coloring complete lines.
- `run-tests.sh` now colors only semantic terminal tokens after the plain stream has already been written to the timestamped console log. `[PASS]`/`[FAIL]`/`[SKIP]`, translation classes, selected diagnostic labels, section titles, and run-summary/status labels are colorized individually.
- CLI case rows now color the translation class itself (`exact`, `approx`, `unsupported`, `moot`, `external`, `invalid`) in addition to the result marker.
- Translator diagnostics selectively color only `APPROX`, `UNSUPPORTED`, `MOOT`, `EXTERNAL`, `WARNING`, `suggestion`, `note`, and the existing `invalid/unknown Screen syntax` phrase; reason/suggestion text and exact dry-run commands remain uncolored.
- Added `SCREEN2TMUX_COLOR=auto|always|never`. `auto` is the default; `NO_COLOR` remains a hard override, including over `always`.
- Test components run by the aggregate runner are forced to plain output before `tee`, so timestamped logs and their ZIP archive stay ANSI-free even while the terminal is colorized. Standalone test scripts honor the same color policy directly.
- Added three focused regressions for selective diagnostic color and `NO_COLOR` precedence, bringing the focused regression count to 71.
- Translation semantics are otherwise unchanged from 0.3.2.

## 0.3.2 — 2026-10-04

- Changed `run-tests.sh` to generate one shared run timestamp (`YYYYMMDD-HHMMSS`) and apply it to every log filename.
- Standalone test scripts also default to timestamped log filenames; when launched by `run-tests.sh` they receive the runner's shared timestamp/path.
- Added a timestamped console transcript generated by the runner itself rather than relying on an externally captured `test-run-console.log`.
- Added automatic end-of-run ZIP packaging containing exactly the four logs from that run: CLI/oracle, focused regressions, live tmux behavior, and console transcript.
- The log ZIP uses the same timestamp as the member logs: `logs/screen-to-tmux-translator-test-logs-YYYYMMDD-HHMMSS.zip`.
- The runner now executes all three test layers, records an overall PASS/FAIL status, then creates the log archive even if one test layer fails.
- Added `SCREEN2TMUX_RUN_TIMESTAMP` for deterministic/testable filenames and `SCREEN2TMUX_LOG_DIR` for an alternate output directory. Existing artifacts with the same forced timestamp are refused instead of overwritten.
- ZIP creation uses `zip` when available and falls back to Python 3's `zipfile`; if neither is present the runner reports a concrete packaging error.
- Runtime `logs/` artifacts are no longer part of the static `MANIFEST.sha256`, because every test run intentionally creates new timestamped files.
- Translator semantics are unchanged from 0.3.1.

## 0.3.1 — 2026-10-04

- Adopted an explicit no-emulation policy for Screen-only behavior: when tmux does not implement the same feature, the translator reports `UNSUPPORTED`/`APPROX` rather than constructing a compatibility subsystem.
- Added `WARNING: uncertain translation of argument ...` diagnostics (exit 3, non-executing) for Screen session/window selectors that contain tmux-significant target syntax and cannot be safely reinterpreted.
- Reclassified `-U` as `APPROX`. GNU Screen `-U` both declares a UTF-8 display and sets the default encoding for new windows; tmux `-u` does not implement Screen's per-window encoding policy.
- Reclassified the attach-time semantics of `-A` as `APPROX`; tmux has no equivalent to Screen's explicit adapt-all-window-sizes behavior. Non-attach paths leave `-A` inert, matching Screen's source path.
- Reclassified Screen version/help requests (`-v`, `--version`, `--help`, internal `version`) as `UNSUPPORTED` compatibility translations instead of returning tmux's unrelated help/version output.
- Reclassified attached nested `-m` inside tmux as `APPROX` and preserved tmux's nesting safeguard instead of automatically unsetting `$TMUX`.
- Corrected internal `screen N`/`N:title`: Screen uses `N` as a `StartAt` lower bound and searches for the first free window number at or above it. The previous exact `tmux new-window -t :N` mapping was state-dependent and is now an uncertainty warning/`APPROX`.
- Added deterministic tmux format escaping for literal Screen names/titles in source-confirmed format-expanded arguments: `#` becomes `##` for `new-session -s/-n`, `new-window -n`, `rename-session`, and `rename-window`.
- Changed `-Q echo` to `tmux display-message -pl` for literal output and rejected Screen `echo -p` format strings rather than interpreting them as tmux formats.
- Expanded focused regressions from 50 to 68 checks, including format-injection/literal-name cases, uncertain selectors, `-U`, `-A`, version/help, nested `-m`, and `echo -p`.
- 0.3.1 packaged results: 683/683 translator permutations PASS, 228/228 syntax-oracle cases PASS, 68/68 focused regressions PASS; live tmux behavior checks are present but skipped in this build environment because no tmux executable is installed.

## 0.3.0 — 2026-10-04

- Reclassified the entire `-R/-RR` create-or-attach family as `APPROX`. GNU Screen filters candidate sockets by attached/detached state and `-RR` has distinct multiple-match selection behavior; tmux `new-session -A` does not preserve those rules.
- Reclassified `-ls/-list` as `APPROX` because Screen's socket-oriented output and attached/detached/dead-state reporting are not output-compatible with `tmux list-sessions`.
- Implemented explicit `-q` tracking and reclassified `-q -ls/-list` as `APPROX`; Screen suppresses output and returns special socket-count-derived exit statuses that tmux does not reproduce.
- Reclassified `number N` as state-sensitive `APPROX`. Screen swaps window numbers when the target slot is occupied; the translator now recommends `tmux swap-window` for an occupied slot and `move-window` only for an empty slot.
- Reclassified `collapse` as `APPROX` because Screen always renumbers from zero while tmux `move-window -r` starts at `base-index`.
- Reclassified internal `detach` and `pow_detach` as client-scoped approximations rather than session-wide automatic detaches.
- Reclassified `altscreen on/off` as `APPROX` because Screen's `use_altscreen` is backend-wide while tmux's `alternate-screen` option is window/pane scoped.
- Reclassified `readbuf`, `writebuf`, and `register` as `APPROX` due to Screen-backend/user versus tmux-server buffer scope. Suggestions now use explicit namespaced buffer names.
- Corrected `paste` with no register argument to `UNSUPPORTED`; GNU Screen opens an interactive register-selection prompt rather than immediately pasting a default buffer.
- Added a conservative named-session creation policy. `-S NAME` creation is `APPROX` by default because Screen permits multiple `PID.NAME` sockets sharing a label whereas tmux names are unique. `SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=1` opts into direct tmux named-session creation.
- Fixed malformed `list-windows`/`collapse` suggestion construction that could duplicate a session name in diagnostic text.
- Expanded focused semantic regressions from 33 to 50 tests.
- Added optional isolated live-tmux behavioral tests for duplicate session names, occupied window indices, `base-index`, server-wide buffers, and pane-scoped `alternate-screen`.
- Packaged static results: 683/683 translator permutations PASS, 228/228 syntax-oracle cases PASS, 50/50 focused regressions PASS. Live tmux behavior checks are skipped when no tmux executable is installed.

## 0.2.1 — 2026-10-04

- Fixed nested-multiplexer behavior: ordinary `screen [program ...]` now maps to `tmux new-window [program ...]` when `$TMUX` is set, no `-S` is supplied, and Screen `-m` was not requested. This mirrors Screen's `$STY`/`SendCreateMsg` behavior.
- Preserved Screen's `-m` and `-S` escape hatches inside tmux: either one continues to create a new tmux session rather than a window in the current session.
- Reclassified plain named `screen -r session` (including `-p ... -r`) as `APPROX`: Screen resume semantics normally require a detached session, whereas tmux `attach-session` normally permits an additional client.
- Corrected `removebuf`: Screen deletes its exchange file (`BufferFile`) and does not clear the in-memory copy buffer, so the incorrect `tmux delete-buffer` mapping was removed.
- Corrected `screen -Q number` to use a tmux format matching Screen's `N (title)` result shape: `#{window_index} (#{window_name})`.
- Scoped the `displays` substitute to the selected tmux session (`list-clients -t SESSION`) and downgraded it to `APPROX` because output formats differ.
- Downgraded `bind` and `unbindall` to `APPROX`: Screen bindings belong to one Screen backend/session while tmux key tables are server-wide.
- Downgraded `redisplay`, `suspend`, `dinfo`, and related display/client operations where a Screen session selector does not uniquely identify a tmux client.
- Downgraded `-Q windows`, `-Q info`, `-Q lastmsg`, `-X windows`, `-X help`, `-X info`, and `-X lastmsg` where tmux offers a useful query but not Screen-compatible output.
- Downgraded explicit-file `hardcopy` translations to `APPROX`; `capture-pane` is a useful substitute but not guaranteed byte-for-byte equivalent in whitespace/history/rendering details.
- Made serial/Telnet suggestions context-aware: when invoked inside tmux without `-S`/`-m`, the suggested external application is opened with `tmux new-window` rather than a new tmux session.
- Expanded focused regression coverage from 15 to 33 tests.
- Packaged results: 683/683 translator permutations PASS, 228/228 syntax-oracle cases PASS, 33/33 focused regressions PASS.

## 0.2.0 — 2026-10-04

- Added translation classes: `EXACT`, `UNSUPPORTED`, `APPROX`, `MOOT`, `EXTERNAL`, and `INVALID` with distinct exit codes.
- Fixed `screen -d -m <program>` parsing so the program is not mistaken for a session selector.
- Fixed `screen -m`: it maps to an attached `tmux new-session`, not `new-session -d`.
- Prevented Screen configuration files from being passed directly to `tmux -f`.
- Prevented Screen `source` files from being passed directly to `tmux source-file`.
- Stopped silently dropping `-L` and `-Logfile`; logging differences became explicit approximations/unsupported cases.
- Preserved `-p <window>` in the closest named `-r` attach substitute using tmux's `session:window` target syntax.
- Downgraded Screen region operations (`split`, `focus`, `only`, `resize`) from exact mappings to explicit approximations.
- Corrected suggested tmux focus targets to forms such as `session:.{right-of}`.
- Removed the incorrect fixed-direction `resize +N -> resize-pane -D N` translation.
- Downgraded Screen saved layout operations to approximations/unsupported because tmux pane layouts are a different abstraction.
- Downgraded Screen ACL add/delete mappings to approximations because tmux `server-access` has server-wide scope.
- Reclassified direct serial/Telnet substitutes as `EXTERNAL` and stopped executing them automatically.
- Added single-line control-byte escaping in dry-run command rendering.
- Added exact argv/output hex logging so carriage returns and other control bytes cannot corrupt the test transcript.
- Added a separate GNU Screen 5.0.2 syntax oracle based on `comm.c` metadata and an independent top-level parser.
- Added a generated `screen-5.0.2-command-manifest.tsv` containing all 189 current internal commands and query capability metadata.
- Added focused regression tests for the semantic false positives observed in 0.1.0.
- Packaged results: 683/683 translator permutations PASS, 228/228 syntax-oracle cases PASS, 15/15 focused regressions PASS.

## 0.1.0 — 2026-10-01

- Initial versioned project packaging.
- Added POSIX-shell `screen2tmux()` translator.
- Added optional drop-in `screen()` shell function.
- Added `--dry-run` recognition at any argument position.
- Added initial translation exit classes (`0`, `2`, `64`).
- Added explicit explanations and alternatives for Screen-only semantics.
- Added mappings for common session, window, input, split, query, copy-buffer, logging, monitoring, configuration, terminal, and client-control commands.
- Added external-tool substitutions for Screen direct serial and built-in Telnet forms.
- Added source-derived command-line case manifest.
- Added colorized POSIX-shell test harness.
- Added three-position dry-run permutation testing.
- Added full input/output result logging.
