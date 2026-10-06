# Source-derived Screen CLI cases for screen-to-tmux-translator 0.4.10.
# This file is sourced by test-screen-cli.sh, which defines case_.
# Syntax: case_ ID EXPECTED "description" [screen arguments...]
# EXPECTED: exact | approx-run | approx | moot | external | unsupported | invalid

# Common everyday usage
case_ C001 exact       "start a new session"
case_ C002 approx-run       "start named session" -S work
case_ C003 exact       "start session running bash" bash
case_ C004 approx-run       "start named session running bash" -S work bash
case_ C005 exact       "start session running vim" vim
case_ C006 exact       "start session running vim file" vim file.txt
case_ C007 approx-run       "start named editor session" -S editor vim file.txt
case_ C008 approx-run       "clustered detached named session" -dmS work
case_ C009 approx-run       "clustered detached named session with command" -dmS work bash
case_ C010 approx-run       "clustered detached build session" -dmS build make
case_ C011 approx-run       "list sessions short" -ls
case_ C012 approx-run       "list sessions long" -list
case_ C013 approx-run       "list matching sessions" -ls work
case_ C014 approx-run      "attach to an available session" -r
case_ C015 approx-run      "attach named session" -r work
case_ C016 exact       "multi-display attach named session" -x work
case_ C017 exact       "detach named session" -d work
case_ C018 exact       "power detach named session" -D work
case_ C019 exact       "detach elsewhere and attach" -d -r work
case_ C020 exact       "power detach elsewhere and attach" -D -r work
case_ C021 approx-run       "create-or-attach named session" -R work
case_ C022 approx-run       "aggressive create-or-attach named session" -RR work
case_ C023 approx-run       "detach and create-or-attach" -d -R work
case_ C024 approx-run       "power-detach and create-or-attach" -D -R work
case_ C025 approx-run       "detach and RR" -d -RR work
case_ C026 approx-run       "power-detach and RR" -D -RR work
case_ C027 moot        "wipe stale sessions" -wipe
case_ C028 moot        "wipe matching stale sessions" -wipe work

# Option clustering / ordering permutations explicitly supported by Screen parser
case_ P001 approx-run       "expanded detached named session" -d -m -S work
case_ P002 approx-run       "expanded detached named command" -d -m -S work bash
case_ P003 approx-run       "session option before detached flags" -S work -d -m
case_ P004 approx-run       "cluster dR attach-create" -dR work
case_ P005 approx-run       "cluster dRR attach-create" -dRR work
case_ P006 approx-run       "cluster DR attach-create" -DR work
case_ P007 approx-run       "cluster DRR attach-create" -DRR work
case_ P008 approx-run      "attached preselect syntax" -p 2 -r work
case_ P009 approx-run      "attached preselect compact syntax" -p2 -r work
case_ P010 unsupported "compact alternate rc syntax" -c/tmp/screenrc
case_ P011 unsupported "compact escape syntax" '-e^Bb'
case_ P012 unsupported "flow enabled form" -f
case_ P013 unsupported "flow off form" -fn
case_ P014 unsupported "flow auto form" -fa
case_ P015 unsupported "login mode off" -ln
case_ P016 approx-run       "quiet session list" -q -ls

# Detached/background forms
case_ D001 exact       "expanded detached session" -d -m
case_ D002 exact       "expanded detached bash" -d -m bash
case_ D003 exact       "expanded detached shell command" -d -m sh -c 'sleep 60'
case_ D004 approx-run       "expanded detached named" -d -m -S work
case_ D005 approx-run       "expanded detached named bash" -d -m -S work bash
case_ D006 approx-run       "expanded detached build" -d -m -S build make
case_ D007 unsupported "Screen D-m process semantics" -D -m -S work
case_ D008 unsupported "Screen D-m command semantics" -D -m -S work bash

# Window creation through -X
case_ W001 exact       "create shell window" -S work -X screen
case_ W002 exact       "create bash window" -S work -X screen bash
case_ W003 exact       "create top window" -S work -X screen top
case_ W004 exact       "create vim window" -S work -X screen vim file.txt
case_ W005 exact       "create titled editor window" -S work -X screen -t editor vim
case_ W006 unsupported "create window with per-window history size" -S work -X screen -h 10000 bash
case_ W007 approx-run      "create window at index five" -S work -X screen 5
case_ W008 approx-run      "create indexed named window" -S work -X screen 5:editor vim

# Window selection/renaming/order
case_ W101 exact       "select window zero" -S work -p 0 -X select
case_ W102 exact       "select window two" -S work -p 2 -X select
case_ W103 exact       "select named window" -S work -p editor -X select
case_ W104 exact       "rename window" -S work -p 2 -X title editor
case_ W105 approx-run       "renumber window" -S work -p 2 -X number 5
case_ W106 exact       "kill window" -S work -p 2 -X kill
case_ W107 exact       "next window" -S work -X next
case_ W108 exact       "previous window" -S work -X prev
case_ W109 exact       "other/last window" -S work -X other
case_ W110 approx-run       "collapse window numbers" -S work -X collapse
case_ W111 unsupported "alphabetically sort and renumber windows" -S work -X sort

# Sending input
case_ I001 exact       "stuff literal hello" -S work -p 0 -X stuff hello
case_ I002 exact       "stuff literal backslash-n text" -S work -p 0 -X stuff 'hello\n'
case_ I003 exact       "stuff carriage-return byte" -S work -p 0 -X stuff "hello$(printf '\r')"
case_ I004 exact       "stuff q into named window" -S work -p editor -X stuff q
case_ I005 exact       "send XON" -S work -p 1 -X xon
case_ I006 exact       "send XOFF" -S work -p 1 -X xoff

# Splits/regions
case_ R001 approx-run      "split top-bottom" -S work -X split
case_ R002 approx-run      "split left-right" -S work -X split -v
case_ R003 approx-run      "focus implicit next" -S work -X focus
case_ R004 approx-run      "focus next" -S work -X focus next
case_ R005 approx-run      "focus previous" -S work -X focus prev
case_ R006 approx-run      "focus up" -S work -X focus up
case_ R007 approx-run      "focus down" -S work -X focus down
case_ R008 approx-run      "focus left" -S work -X focus left
case_ R009 approx-run      "focus right" -S work -X focus right
case_ R010 approx-run      "only current region" -S work -X only
case_ R011 unsupported "remove Screen region without killing window" -S work -X remove
case_ R012 unsupported "fit layer to Screen region" -S work -X fit
case_ R013 approx      "resize region plus five" -S work -X resize +5
case_ R014 approx      "redisplay" -S work -X redisplay

# Client/session control
case_ S001 approx       "detach via X" -S work -X detach
case_ S002 approx       "power detach via X" -S work -X pow_detach
case_ S003 approx      "suspend frontend" -S work -X suspend
case_ S004 exact       "quit named Screen session" -S work -X quit
case_ S005 approx-run      "lock Screen session" -S work -X lockscreen
case_ S006 exact       "rename session" -S work -X sessionname development

# Queries
case_ Q001 approx-run      "query windows" -S work -Q windows
case_ Q002 approx-run      "query info" -S work -Q info
case_ Q003 approx-run      "query last message" -S work -Q lastmsg
case_ Q004 exact       "query window number" -S work -Q number
case_ Q005 exact       "query window title" -S work -Q title
case_ Q006 exact       "query echo" -S work -Q echo hello
case_ Q007 exact       "query-select window two" -S work -Q select 2

# Copy buffer/scrollback
case_ B001 unsupported "hardcopy default filename" -S work -p 0 -X hardcopy
case_ B002 approx      "hardcopy explicit file" -S work -p 0 -X hardcopy /tmp/window.txt
case_ B003 approx      "hardcopy history explicit file" -S work -p 0 -X hardcopy -h /tmp/all.txt
case_ B004 unsupported "change existing window scrollback" -S work -p 0 -X scrollback 10000
case_ B005 approx-run       "read copy buffer" -S work -X readbuf /tmp/text
case_ B006 approx-run       "write copy buffer" -S work -X writebuf /tmp/text
case_ B007 unsupported "remove Screen exchange file" -S work -X removebuf
case_ B008 approx-run       "register text" -S work -X register a hello
case_ B009 unsupported       "paste buffer" -S work -p 0 -X paste
case_ B010 exact       "enter copy mode" -S work -p 0 -X copy

# Logging
case_ L001 approx      "new session with initial logging" -L
case_ L002 approx      "named session with initial logging" -L -S work
case_ L003 unsupported "explicit logfile without enabling logging" -Logfile /tmp/screen.log
case_ L004 approx      "logging with explicit logfile" -L -Logfile /tmp/screen.log
case_ L005 approx-run      "turn pane logging on" -S work -p 0 -X log on
case_ L006 approx-run      "turn pane logging off" -S work -p 0 -X log off
case_ L007 unsupported "set Screen logfile format" -S work -X logfile /tmp/screen-%n.log
case_ L008 unsupported "set Screen logfile flush interval" -S work -X logfile flush 5
case_ L009 unsupported "enable Screen log timestamp insertion" -S work -X logtstamp on

# Monitoring and alerts
case_ M001 exact       "monitor activity on" -S work -p 0 -X monitor on
case_ M002 exact       "monitor activity off" -S work -p 0 -X monitor off
case_ M003 exact       "silence monitor thirty seconds" -S work -p 0 -X silence 30
case_ M004 exact       "silence monitor off" -S work -p 0 -X silence off
case_ M005 exact       "visual bell on" -S work -X vbell on
case_ M006 exact       "visual bell off" -S work -X vbell off

# Configuration/environment
case_ E001 unsupported "alternate screenrc" -c /tmp/screenrc.test
case_ E002 unsupported "source additional configuration" -S work -X source /tmp/screen-extra
case_ E003 exact       "set environment" -S work -X setenv FOO bar
case_ E004 exact       "unset environment" -S work -X unsetenv FOO
case_ E005 unsupported "change Screen backend default cwd" -S work -X chdir /tmp

# Prefix/key configuration
case_ K001 unsupported "startup Screen escape pair" -e '^Bb'
case_ K002 unsupported "runtime Screen escape pair" -S work -X escape '^Bb'
case_ K003 approx-run      "bind c to create window" -S work -X bind c screen
case_ K004 approx-run      "bind k to kill window" -S work -X bind k kill
case_ K005 approx-run      "unbind all" -S work -X unbindall

# Terminal/encoding
case_ T001 unsupported "set Screen virtual TERM at startup" -T screen-256color
case_ T002 approx-run      "force UTF-8 client output" -U
case_ T003 approx      "enable truecolor" -S work -X truecolor on
case_ T004 approx-run       "enable alternate screen" -S work -X altscreen on
case_ T005 approx-run       "disable alternate screen" -S work -X altscreen off
case_ T006 exact       "reset terminal state" -S work -X reset
case_ T007 unsupported "set UTF-8 Screen encoding" -S work -X encoding UTF-8
case_ T008 unsupported "set Shift-JIS Screen encoding" -S work -X encoding SJIS
case_ T009 unsupported "set ISO-2022 charset" -S work -X charset 'B%G'

# Status/caption
case_ H001 approx-run      "hardstatus on" -S work -X hardstatus on
case_ H002 approx-run      "hardstatus off" -S work -X hardstatus off
case_ H003 approx-run      "hardstatus bottom" -S work -X hardstatus alwayslastline
case_ H004 approx-run      "hardstatus top" -S work -X hardstatus alwaysfirstline
case_ H005 approx-run      "caption always" -S work -X caption always
case_ H006 unsupported "caption splitonly" -S work -X caption splitonly
case_ H007 approx      "redisplay from status section" -S work -X redisplay

# Security/multiuser
case_ A001 unsupported "enable Screen multiuser mode" -S work -X multiuser on
case_ A002 unsupported "disable Screen multiuser mode" -S work -X multiuser off
case_ A003 approx-run      "add ACL user" -S work -X acladd alice
case_ A004 approx-run      "delete ACL user" -S work -X acldel alice
case_ A005 unsupported "change per-window ACL" -S work -X aclchg alice -w '#'
case_ A006 unsupported "Screen writelock" -S work -X writelock on
case_ A007 unsupported "Screen authentication" -S work -X auth on
case_ A008 unsupported "startup Screen authentication" -P -S work

# Serial/direct-device/Telnet/ZMODEM special forms
case_ X001 external-run "direct serial tty device" /dev/ttyS0
case_ X002 external-run "direct serial tty with baud operand" /dev/ttyS0 9600
case_ X003 external-run "direct USB serial tty with baud operand" /dev/ttyUSB0 115200
case_ X004 external    "native serial break" -S work -X break
case_ X005 external    "timed native serial break" -S work -X break 500
case_ X006 external    "Screen flow on" -S work -X flow on
case_ X007 external    "Screen flow off" -S work -X flow off
case_ X008 external    "Screen flow auto" -S work -X flow auto
case_ X009 external-run "built-in telnet special command represented as argv" //telnet example.com
case_ X010 external-run "built-in telnet with port represented as argv" //telnet example.com 23
case_ X011 external-run "IPv4 telnet selection" -4 //telnet example.com
case_ X012 external-run "IPv6 telnet selection" -6 //telnet example.com
case_ X013 unsupported "ZMODEM auto" -S work -X zmodem auto
case_ X014 unsupported "ZMODEM catch" -S work -X zmodem catch
case_ X015 unsupported "ZMODEM pass" -S work -X zmodem pass
case_ X016 unsupported "ZMODEM off" -S work -X zmodem off

# Top-level options and utility forms
case_ O001 unsupported "force all termcap capabilities" -a
case_ O002 exact       "adapt windows to display" -A
case_ O003 unsupported "alternate rc file" -c /tmp/my-screenrc
case_ O004 unsupported "Screen escape pair" -e '^Bb'
case_ O005 unsupported "flow on" -f
case_ O006 unsupported "flow off" -fn
case_ O007 unsupported "flow auto" -fa
case_ O008 unsupported "initial scrollback size" -h 10000
case_ O009 unsupported "interrupt output sooner" -i
case_ O010 unsupported "utmp login mode on" -l
case_ O011 unsupported "utmp login mode off" -ln
case_ O012 approx      "startup logging" -L
case_ O013 unsupported "set logfile path without logging" -Logfile /tmp/screen.log
case_ O014 exact       "force new Screen session semantics" -m
case_ O015 unsupported "optimized VT output mode" -O
case_ O016 approx-run      "preselect then attach" -p 2 -r work
case_ O017 unsupported "Screen authentication flag" -P
case_ O018 approx-run       "quiet list" -q -ls
case_ O019 unsupported "default shell override" -s /bin/bash
case_ O020 approx-run       "session name" -S work
case_ O021 exact       "initial window title" -t editor vim
case_ O022 unsupported "virtual terminal type" -T screen-256color
case_ O023 approx-run      "UTF-8 mode" -U
case_ O024 unsupported "version short" -v
case_ O025 unsupported "version long" --version
case_ O026 exact       "translator compatibility help" --help

# Native command-mode informational mappings
case_ N001 approx-run      "list attached displays" -S work -X displays
case_ N002 approx-run      "display info" -S work -X dinfo
case_ N003 approx-run      "list windows internal command" -S work -X windows
case_ N004 approx-run      "help/list keys" -S work -X help
case_ N005 approx-run      "info internal command" -S work -X info
case_ N006 approx-run      "lastmsg internal command" -S work -X lastmsg
case_ N007 unsupported "version internal command" -S work -X version
case_ N008 unsupported "license internal command" -S work -X license
case_ N009 approx-run      "layout next" -S work -X layout next
case_ N010 approx-run      "layout previous" -S work -X layout prev
case_ N011 approx-run      "layout show" -S work -X layout show
case_ N012 approx-run      "layout select" -S work -X layout select tiled
case_ N013 unsupported "layout save" -S work -X layout save worklayout

# Negative controls: expected invalid translator/Screen syntax patterns.
case_ Z001 invalid     "unknown top-level option" -Z
case_ Z002 invalid     "missing -S argument" -S
case_ Z003 invalid     "missing -p argument" -p
case_ Z004 invalid     "missing -c argument" -c
case_ Z005 invalid     "missing -T argument" -T
case_ Z006 invalid     "missing -X command" -S work -X
case_ Z007 invalid     "missing -Q command" -S work -Q
case_ Z008 invalid     "unknown internal command" -S work -X definitely-not-a-screen-command
case_ Z009 invalid     "unknown query command" -S work -Q definitely-not-a-screen-command
case_ Z010 invalid     "invalid focus direction" -S work -X focus diagonal
