# Changelog

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
