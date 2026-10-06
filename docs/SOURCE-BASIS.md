# Source basis

**0.4.1 note:** translation semantics and upstream source assumptions are unchanged from 0.4.0; this release changes test presentation and interface-equivalence orchestration only.

This release was built against the source archives supplied during the project work. At 0.4.0 packaging time, GNU's public distribution index lists Screen 5.0.1 as the latest official release. This project also has a supplied Screen 5.0.2 source snapshot (the version already used for the translator's source audit), and the runtime compatibility help derives its option surface from that 5.0.2 `screen.c` usage table. Because that snapshot is newer than the latest official tarball, the help deliberately labels itself GNU Screen 5.0.x-style compatibility help rather than claiming to be native Screen help or a native Screen version.

## GNU Screen

```text
GNU Screen archive: screen-5.0.2.tar.gz
SHA-256: ca9a2c7e240919bc7ac12124593ae4529bb4eb5f7349d8857829b7e3f0b3b332

comm.c SHA-256:
1814cf1fd8bc4f18a58c62036e7de325b7ad7554da633305455866e1882d5620

screen.c SHA-256:
36598a0c3381b7fa1dc7f6b439f24ed690d8ca74463086d25ef027c7dd8e6989

process.c SHA-256:
8ad5c4fc976a1420ede9ad28daf479fd69ef7ed975696a177e613aa90a65a2e3

fileio.c SHA-256:
5af1aebd7fe2b58aa6521e8b8d70d28ff7fae1fd262927428856c493cdf5f25a

window.c SHA-256:
3515c4bb1cc7440e4b6bfe0069718eaa9b38f818acd6ac45c4748a867492cf30

socket.c SHA-256:
440a5388549abbfc58138aeeed66bc2d9f0a970fefa9d654dd1e4d8d2f763553
```

`docs/screen-5.0.2-command-manifest.tsv` was generated from the 189-entry `comm.c` command table. It records each command's flag/arity expression and whether it has `CAN_QUERY`.

The top-level compatibility help option list is cross-checked against `screen.c:exit_with_usage()` from the supplied 5.0.2 snapshot. That usage table includes `-P` authentication as well as the standard `-4/-6`, `-A`, logging, attach/resume, UTF-8, wipe, and command-execution options. Translator-specific status annotations are added by this project and are not copied native Screen output.

The nested-invocation behavior follows `screen.c`: when there is no `SocketMatch` (`-S` selector), `-m` is not set, and `$STY` is present, Screen sends `SendCreateMsg` to the existing Screen backend instead of starting another Screen session. The compatibility wrapper mirrors that rule using `$TMUX` and `tmux new-window`.

The `removebuf` correction follows `process.c:DoCommandRemovebuf()` -> `fileio.c:KillBuffers()`, which unlinks Screen's `BufferFile`. It does not clear the in-memory copy buffer.

`screen -Q number` is based on `DoCommandNumber()`, which returns `%d (%s)` in query mode. `DoCommandNumber()` calls `SwapWindows()`: `window.c:SwapWindows()` exchanges numbers when the destination already exists, which is why `tmux move-window` alone is not exact. `CollapseWindowlist()` always assigns `0,1,2,...`.

`socket.c:FindSocket()` filters Screen sockets by mode (`0600` detached, `0700` attached). Ordinary `-R` therefore considers a different candidate set from tmux `new-session -A`, and `-RR` changes Screen's multiple-match behavior. `screen.c` also shows `-q -ls` returning socket-count-derived statuses rather than ordinary list output.

`process.c:DoCommandAltscreen()` changes the single global `use_altscreen` flag. Screen copy buffers/registers are held in Screen backend/user structures, not in a cross-session server namespace.

## tmux

The supplied tmux source identifies itself in `configure.ac` as the development version `next-3.9`.

```text
tmux source archive: tmux-master.zip
SHA-256: df78c6897052eaf158945ce98007a4ce5fa68790b7c43fa3b2ce8fe6a66da1e6

cmd-attach-session.c SHA-256:
40c4868f3a643d9e19105bda8d30a08e718072cfa7bbe92a7eb7add7ccf6aae2

cmd-list-clients.c SHA-256:
cecd7547017c11420e540e9102b1556ebecd6c63ec1d279a3d741814f25d7fd9

cmd-list-keys.c SHA-256:
d96fb4acdd936609b07895011235c307eaba8c96d642289fa25f5a912ff5c738

cmd-refresh-client.c SHA-256:
983a57e0382c3f97c450b73aee94734a2ffbe86f796f27abd81d96edc0d78d34

cmd-detach-client.c SHA-256:
112872b2ade3821982d96b560257cae4fd973c088a450ea8d2a25e7c87a405be

cmd-move-window.c SHA-256:
b7e2adf85639ff2c74f8d387552aadd013e36c815aa3d2bb0855bbae0e80f7dd

session.c SHA-256:
3eaabb33457777239d24557a02606d58376bd6e1a45e07aca9c3a48bc21245b3

options-table.c SHA-256:
0cdb22361799e36e90e451f1b3c8ad57d31dd0ab18fd878559aa3f8f5bd62c90
```

`cmd-list-clients.c` confirms that `list-clients -t session` scopes results to clients attached to the selected session. tmux key bindings, by contrast, live in server key tables, so a Screen-session-local `bind` cannot safely be executed as an unconditional `tmux bind-key` without broadening scope.

`refresh-client` and `suspend-client` are target-client commands. A Screen session selector (`-S`) does not uniquely identify a tmux client when multiple clients are attached, so these translations are classified as `APPROX` instead of being executed automatically.

For plain Screen `-r`, tmux's `attach-session` is only an approximation: Screen resume semantics distinguish detached from already attached sessions, while tmux normally permits multiple clients. The wrapper preserves a Screen `-p` window in the suggested tmux `session:window` target, but no longer labels the overall `-r` behavior exact.

## 0.3.1 source checks

GNU Screen 5.0.2 `doc/screen.1` documents `-U` as both a terminal UTF-8 declaration and a default-new-window encoding change. `screen.c` implements that by setting `nwin_options.encoding = UTF8`. The same manual documents `-A` as adapting all windows to the current terminal; `attacher.c` passes `adaptflag` to the backend and `display.c:InitTerm()` changes resize behavior accordingly. These are not modeled as `tmux -u` or a hidden tmux resize sequence.

`process.c:DoCommandEcho()` shows that ordinary `echo` is literal while `echo -p` expands Screen's `%` status format. This is why literal `-Q echo` uses tmux `display-message -pl`, but Screen `echo -p` is not translated.

`process.c:DoScreen()` stores a numeric `screen N` operand in `NewWindow.StartAt`. `window.c:MakeWindow()` then increments from `StartAt` until it finds a free window number. Therefore `screen 5` is not equivalent to tmux `new-window -t :5` when slot 5 is occupied. The translator reports the state dependency instead of implementing a slot-search wrapper.

The audited tmux development source format-expands session/window names in `cmd-new-session.c` (`-s`, `-n`), `cmd-new-window.c` (`-n`), `cmd-rename-session.c`, and `cmd-rename-window.c`. `regress/format-strings.sh` verifies `##` expands to a literal `#`. 0.3.1 therefore escapes literal Screen `#` only in these source-confirmed format-expanded name positions. `cmd-display-message.c` confirms `-l` bypasses format expansion.

`cmd-new-session.c` also contains tmux's attached nested-session safeguard (`sessions should be nested with care, unset $TMUX to force`). The translator does not unset `$TMUX` on the user's behalf.

`socket.c:FindSocket()` also explains the conservative selector warnings. Screen may strip a leading numeric `PID.` component when matching a nonnumeric selector, treats the `tty` prefix as optional, and gives leading-numeric selectors a second match path after the socket PID. Those rules are not tmux target-syntax rules, so selectors whose meaning can depend on them are reported as uncertain instead of being rewritten.

Additional audited hashes:

```text
GNU Screen doc/screen.1 SHA-256:
ba2fde926826b979f6320df57f54b291e98435ab2bdd6e07ad1951e1e4f78fda

GNU Screen display.c SHA-256:
3b34badccc7028fd45d69477b84928c4bb4773d5eb5e095fb323b625d542c5b8

tmux cmd-new-session.c SHA-256:
efc19dd76439019b028ba124eaef393516f3e17579b7cab978254bdcea6d45ee

tmux cmd-new-window.c SHA-256:
4cd3235f2fac8834c632bc987d1fe71ada11d304a0145a2b5890a4b4d2c8d771

tmux cmd-rename-session.c SHA-256:
c02a18cb346a7704e323567002f19e4401ddbb50ae7825196096d328d3a6772d

tmux cmd-rename-window.c SHA-256:
165a8d71e719a4fd1cee2a21b52417a39c81e31284e301232fed66ad291d2839

tmux cmd-display-message.c SHA-256:
e528b10d8d128f265eb1fcb4f8fd6a362ce96adb3969b8216f244196e8676766

tmux cmd-find.c SHA-256:
decb4d8aeecea0d86ace095be76a40449013fba579706b35580acefa275fcef6

tmux regress/format-strings.sh SHA-256:
f808fad0506fb6ca16193118891590a6eb8c854a4ffbbedf9313de21cf025bd5
```

## Caveat

The source hashes identify the snapshots audited for this release. A future Screen or tmux release may add, remove, or alter syntax or semantics; rerun and update the source-derived manifests before treating this translator as authoritative for a different version.

For 0.3.0, `cmd-move-window.c` and `session.c` confirm that `move-window -r` calls `session_renumber_windows()`, which starts at the session's `base-index`. `options-table.c` declares `alternate-screen` with window/pane scope. These source facts underpin the new `APPROX` classifications.

## Embedded tmux build integration (0.4.0)

The compatibility integration keeps the upstream source footprint intentionally small. The packaged build workflow copies `tmux-integration/screen-to-tmux-translator` into the selected tmux source tree and applies `tmux-integration/tmux.c-screen-compat.patch` with zero fuzz. The patch changes only `tmux.c`: it includes the translator file and calls `screen_to_tmux_translate(&argc, &argv)` at the beginning of `main()`.

The same minimal tmux.c patch was checked locally against the supplied `release_3.7d` source tree and the available newer development tmux source snapshot. For `build_tmux_latest.sh`, the source is downloaded from the official `master` branch when the script runs and the exact commit is recorded. If those known integration anchors stop matching, the script fails explicitly rather than inferring a new location.

`tmux-integration/screen-to-tmux-translator` embeds the canonical POSIX translator source. For this package, the embedded shell payload is regenerated directly from `bin/screen-function-source.sh`. The canonical/minified/standalone interfaces remain byte-identical across the existing equivalence corpus, and the help path is part of that corpus. The embedded help identifies itself as compatibility help rather than native GNU Screen output.


### 0.4.0 build layout

The build integration is now exercised through four independent drivers. Original and patched 3.7d/latest trees are downloaded into separate `source-tmux-*` directories and built into separate `build-tmux-*` directories. Patched builds continue to modify only upstream `tmux.c` and add `screen-to-tmux-translator`; original trees remain unpatched. Current-master original/patched scripts synchronize to the same commit when the counterpart source tree is present.
