# Source basis

This release was built against the source archives supplied during the project work.

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

## Caveat

The source hashes identify the snapshots audited for this release. A future Screen or tmux release may add, remove, or alter syntax or semantics; rerun and update the source-derived manifests before treating this translator as authoritative for a different version.

For 0.3.0, `cmd-move-window.c` and `session.c` confirm that `move-window -r` calls `session_renumber_windows()`, which starts at the session's `base-index`. `options-table.c` declares `alternate-screen` with window/pane scope. These source facts underpin the new `APPROX` classifications.
