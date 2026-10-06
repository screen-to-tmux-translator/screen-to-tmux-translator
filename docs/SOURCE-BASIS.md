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
```

`docs/screen-5.0.2-command-manifest.tsv` was generated from the 189-entry `comm.c` command table. It records each command's flag/arity expression and whether it has `CAN_QUERY`.

## tmux

The supplied tmux source identifies itself in `configure.ac` as the development version `next-3.9`.

```text
tmux source archive: tmux-master.zip
SHA-256: df78c6897052eaf158945ce98007a4ce5fa68790b7c43fa3b2ce8fe6a66da1e6

cmd-attach-session.c SHA-256:
40c4868f3a643d9e19105bda8d30a08e718072cfa7bbe92a7eb7add7ccf6aae2
```

The 0.2.0 attach preselection fix specifically relies on current tmux behavior in `cmd-attach-session.c`: if the `-t` value contains `:` or `.`, tmux resolves it as a pane target and then makes the corresponding window/pane current before attaching. This permits `screen -p 2 -r work` to map to `tmux attach-session -t work:2` without a separate selection command.

## Caveat

The source hashes identify the snapshots audited for this release. A future Screen or tmux release may add, remove, or alter syntax or semantics; rerun and update the source-derived manifests before treating this translator as authoritative for a different version.
