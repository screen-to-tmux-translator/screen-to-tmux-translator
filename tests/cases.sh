# Source-derived Screen CLI cases for screen-to-tmux-translator 0.1.0.
# This file is sourced by test-screen-cli.sh, which defines case_.
# Syntax: case_ ID EXPECTED "description" [screen arguments...]
# EXPECTED: mapped | unsupported | invalid

# Common everyday usage
case_ C001 mapped      "start a new session"
case_ C002 mapped      "start named session" -S work
case_ C003 mapped      "start session running bash" bash
case_ C004 mapped      "start named session running bash" -S work bash
case_ C005 mapped      "start session running vim" vim
case_ C006 mapped      "start session running vim file" vim file.txt
case_ C007 mapped      "start named editor session" -S editor vim file.txt
case_ C008 mapped      "clustered detached named session" -dmS work
case_ C009 mapped      "clustered detached named session with command" -dmS work bash
case_ C010 mapped      "clustered detached build session" -dmS build make
case_ C011 mapped      "list sessions short" -ls
case_ C012 mapped      "list sessions long" -list
case_ C013 mapped      "list matching sessions" -ls work
case_ C014 mapped      "attach to an available session" -r
case_ C015 mapped      "attach named session" -r work
case_ C016 mapped      "multi-display attach named session" -x work
case_ C017 mapped      "detach named session" -d work
case_ C018 mapped      "power detach named session" -D work
case_ C019 mapped      "detach elsewhere and attach" -d -r work
case_ C020 mapped      "power detach elsewhere and attach" -D -r work
case_ C021 mapped      "create-or-attach named session" -R work
case_ C022 mapped      "aggressive create-or-attach named session" -RR work
case_ C023 mapped      "detach and create-or-attach" -d -R work
case_ C024 mapped      "power-detach and create-or-attach" -D -R work
case_ C025 mapped      "detach and RR" -d -RR work
case_ C026 mapped      "power-detach and RR" -D -RR work
case_ C027 unsupported "wipe stale sessions" -wipe
case_ C028 unsupported "wipe matching stale sessions" -wipe work

# Option clustering / ordering permutations explicitly supported by Screen parser
case_ P001 mapped      "expanded detached named session" -d -m -S work
case_ P002 mapped      "expanded detached named command" -d -m -S work bash
case_ P003 mapped      "session option before detached flags" -S work -d -m
case_ P004 mapped      "cluster dR attach-create" -dR work
case_ P005 mapped      "cluster dRR attach-create" -dRR work
case_ P006 mapped      "cluster DR attach-create" -DR work
case_ P007 mapped      "cluster DRR attach-create" -DRR work
case_ P008 mapped      "attached preselect syntax" -p 2 -r work
case_ P009 mapped      "attached preselect compact syntax" -p2 -r work
case_ P010 mapped      "compact alternate rc syntax" -c/tmp/screenrc
case_ P011 unsupported "compact escape syntax" '-e^Bb'
case_ P012 unsupported "flow enabled form" -f
case_ P013 unsupported "flow off form" -fn
case_ P014 unsupported "flow auto form" -fa
case_ P015 unsupported "login mode off" -ln
case_ P016 mapped      "quiet session list" -q -ls

# Detached/background forms
case_ D001 mapped      "expanded detached session" -d -m
case_ D002 mapped      "expanded detached bash" -d -m bash
case_ D003 mapped      "expanded detached shell command" -d -m sh -c 'sleep 60'
case_ D004 mapped      "expanded detached named" -d -m -S work
case_ D005 mapped      "expanded detached named bash" -d -m -S work bash
case_ D006 mapped      "expanded detached build" -d -m -S build make
case_ D007 unsupported "Screen D-m process semantics" -D -m -S work
case_ D008 unsupported "Screen D-m command semantics" -D -m -S work bash

# Window creation through -X
case_ W001 mapped      "create shell window" -S work -X screen
case_ W002 mapped      "create bash window" -S work -X screen bash
case_ W003 mapped      "create top window" -S work -X screen top
case_ W004 mapped      "create vim window" -S work -X screen vim file.txt
case_ W005 mapped      "create titled editor window" -S work -X screen -t editor vim
case_ W006 unsupported "create window with per-window history size" -S work -X screen -h 10000 bash
case_ W007 mapped      "create window at index five" -S work -X screen 5
case_ W008 mapped      "create indexed named window" -S work -X screen 5:editor vim

# Window selection/renaming/order
case_ W101 mapped      "select window zero" -S work -p 0 -X select
case_ W102 mapped      "select window two" -S work -p 2 -X select
case_ W103 mapped      "select named window" -S work -p editor -X select
case_ W104 mapped      "rename window" -S work -p 2 -X title editor
case_ W105 mapped      "renumber window" -S work -p 2 -X number 5
case_ W106 mapped      "kill window" -S work -p 2 -X kill
case_ W107 mapped      "next window" -S work -X next
case_ W108 mapped      "previous window" -S work -X prev
case_ W109 mapped      "other/last window" -S work -X other
case_ W110 mapped      "collapse window numbers" -S work -X collapse
case_ W111 unsupported "alphabetically sort and renumber windows" -S work -X sort

# Sending input
case_ I001 mapped      "stuff literal hello" -S work -p 0 -X stuff hello
case_ I002 mapped      "stuff literal backslash-n text" -S work -p 0 -X stuff 'hello\n'
case_ I003 mapped      "stuff carriage-return byte" -S work -p 0 -X stuff "hello$(printf '\r')"
case_ I004 mapped      "stuff q into named window" -S work -p editor -X stuff q
case_ I005 mapped      "send XON" -S work -p 1 -X xon
case_ I006 mapped      "send XOFF" -S work -p 1 -X xoff

# Splits/regions
case_ R001 mapped      "split top-bottom" -S work -X split
case_ R002 mapped      "split left-right" -S work -X split -v
case_ R003 mapped      "focus implicit next" -S work -X focus
case_ R004 mapped      "focus next" -S work -X focus next
case_ R005 mapped      "focus previous" -S work -X focus prev
case_ R006 mapped      "focus up" -S work -X focus up
case_ R007 mapped      "focus down" -S work -X focus down
case_ R008 mapped      "focus left" -S work -X focus left
case_ R009 mapped      "focus right" -S work -X focus right
case_ R010 mapped      "only current region" -S work -X only
case_ R011 unsupported "remove Screen region without killing window" -S work -X remove
case_ R012 unsupported "fit layer to Screen region" -S work -X fit
case_ R013 mapped      "resize region plus five" -S work -X resize +5
case_ R014 mapped      "redisplay" -S work -X redisplay

# Client/session control
case_ S001 mapped      "detach via X" -S work -X detach
case_ S002 mapped      "power detach via X" -S work -X pow_detach
case_ S003 mapped      "suspend frontend" -S work -X suspend
case_ S004 mapped      "quit named Screen session" -S work -X quit
case_ S005 mapped      "lock Screen session" -S work -X lockscreen
case_ S006 mapped      "rename session" -S work -X sessionname development

# Queries
case_ Q001 mapped      "query windows" -S work -Q windows
case_ Q002 mapped      "query info" -S work -Q info
case_ Q003 mapped      "query last message" -S work -Q lastmsg
case_ Q004 mapped      "query window number" -S work -Q number
case_ Q005 mapped      "query window title" -S work -Q title
case_ Q006 mapped      "query echo" -S work -Q echo hello
case_ Q007 mapped      "query-select window two" -S work -Q select 2

# Copy buffer/scrollback
case_ B001 unsupported "hardcopy default filename" -S work -p 0 -X hardcopy
case_ B002 mapped      "hardcopy explicit file" -S work -p 0 -X hardcopy /tmp/window.txt
case_ B003 mapped      "hardcopy history explicit file" -S work -p 0 -X hardcopy -h /tmp/all.txt
case_ B004 unsupported "change existing window scrollback" -S work -p 0 -X scrollback 10000
case_ B005 mapped      "read copy buffer" -S work -X readbuf /tmp/text
case_ B006 mapped      "write copy buffer" -S work -X writebuf /tmp/text
case_ B007 mapped      "remove copy buffer" -S work -X removebuf
case_ B008 mapped      "register text" -S work -X register a hello
case_ B009 mapped      "paste buffer" -S work -p 0 -X paste
case_ B010 mapped      "enter copy mode" -S work -p 0 -X copy

# Logging
case_ L001 mapped      "new session with initial logging" -L
case_ L002 mapped      "named session with initial logging" -L -S work
case_ L003 mapped      "explicit logfile without enabling logging" -Logfile /tmp/screen.log
case_ L004 mapped      "logging with explicit logfile" -L -Logfile /tmp/screen.log
case_ L005 mapped      "turn pane logging on" -S work -p 0 -X log on
case_ L006 mapped      "turn pane logging off" -S work -p 0 -X log off
case_ L007 unsupported "set Screen logfile format" -S work -X logfile /tmp/screen-%n.log
case_ L008 unsupported "set Screen logfile flush interval" -S work -X logfile flush 5
case_ L009 unsupported "enable Screen log timestamp insertion" -S work -X logtstamp on

# Monitoring and alerts
case_ M001 mapped      "monitor activity on" -S work -p 0 -X monitor on
case_ M002 mapped      "monitor activity off" -S work -p 0 -X monitor off
case_ M003 mapped      "silence monitor thirty seconds" -S work -p 0 -X silence 30
case_ M004 mapped      "silence monitor off" -S work -p 0 -X silence off
case_ M005 mapped      "visual bell on" -S work -X vbell on
case_ M006 mapped      "visual bell off" -S work -X vbell off

# Configuration/environment
case_ E001 mapped      "alternate screenrc" -c /tmp/screenrc.test
case_ E002 mapped      "source additional configuration" -S work -X source /tmp/screen-extra
case_ E003 mapped      "set environment" -S work -X setenv FOO bar
case_ E004 mapped      "unset environment" -S work -X unsetenv FOO
case_ E005 unsupported "change Screen backend default cwd" -S work -X chdir /tmp

# Prefix/key configuration
case_ K001 unsupported "startup Screen escape pair" -e '^Bb'
case_ K002 unsupported "runtime Screen escape pair" -S work -X escape '^Bb'
case_ K003 mapped      "bind c to create window" -S work -X bind c screen
case_ K004 mapped      "bind k to kill window" -S work -X bind k kill
case_ K005 mapped      "unbind all" -S work -X unbindall

# Terminal/encoding
case_ T001 unsupported "set Screen virtual TERM at startup" -T screen-256color
case_ T002 mapped      "force UTF-8 client output" -U
case_ T003 mapped      "enable truecolor" -S work -X truecolor on
case_ T004 mapped      "enable alternate screen" -S work -X altscreen on
case_ T005 mapped      "disable alternate screen" -S work -X altscreen off
case_ T006 mapped      "reset terminal state" -S work -X reset
case_ T007 unsupported "set UTF-8 Screen encoding" -S work -X encoding UTF-8
case_ T008 unsupported "set Shift-JIS Screen encoding" -S work -X encoding SJIS
case_ T009 unsupported "set ISO-2022 charset" -S work -X charset 'B%G'

# Status/caption
case_ H001 mapped      "hardstatus on" -S work -X hardstatus on
case_ H002 mapped      "hardstatus off" -S work -X hardstatus off
case_ H003 mapped      "hardstatus bottom" -S work -X hardstatus alwayslastline
case_ H004 mapped      "hardstatus top" -S work -X hardstatus alwaysfirstline
case_ H005 mapped      "caption always" -S work -X caption always
case_ H006 unsupported "caption splitonly" -S work -X caption splitonly
case_ H007 mapped      "redisplay from status section" -S work -X redisplay

# Security/multiuser
case_ A001 unsupported "enable Screen multiuser mode" -S work -X multiuser on
case_ A002 unsupported "disable Screen multiuser mode" -S work -X multiuser off
case_ A003 mapped      "add ACL user" -S work -X acladd alice
case_ A004 mapped      "delete ACL user" -S work -X acldel alice
case_ A005 unsupported "change per-window ACL" -S work -X aclchg alice -w '#'
case_ A006 unsupported "Screen writelock" -S work -X writelock on
case_ A007 unsupported "Screen authentication" -S work -X auth on
case_ A008 unsupported "startup Screen authentication" -P -S work

# Serial/direct-device/Telnet/ZMODEM special forms
case_ X001 mapped      "direct serial tty device command treated as initial process argument" /dev/ttyS0
case_ X002 mapped      "direct serial tty with baud operand" /dev/ttyS0 9600
case_ X003 mapped      "direct USB serial tty with baud operand" /dev/ttyUSB0 115200
case_ X004 unsupported "native serial break" -S work -X break
case_ X005 unsupported "timed native serial break" -S work -X break 500
case_ X006 unsupported "Screen flow on" -S work -X flow on
case_ X007 unsupported "Screen flow off" -S work -X flow off
case_ X008 unsupported "Screen flow auto" -S work -X flow auto
case_ X009 mapped      "built-in telnet special command represented as argv" //telnet example.com
case_ X010 mapped      "built-in telnet with port represented as argv" //telnet example.com 23
case_ X011 mapped      "IPv4 telnet selection" -4 //telnet example.com
case_ X012 mapped      "IPv6 telnet selection" -6 //telnet example.com
case_ X013 unsupported "ZMODEM auto" -S work -X zmodem auto
case_ X014 unsupported "ZMODEM catch" -S work -X zmodem catch
case_ X015 unsupported "ZMODEM pass" -S work -X zmodem pass
case_ X016 unsupported "ZMODEM off" -S work -X zmodem off

# Top-level options and utility forms
case_ O001 unsupported "force all termcap capabilities" -a
case_ O002 mapped      "adapt windows to display" -A
case_ O003 mapped      "alternate rc file" -c /tmp/my-screenrc
case_ O004 unsupported "Screen escape pair" -e '^Bb'
case_ O005 unsupported "flow on" -f
case_ O006 unsupported "flow off" -fn
case_ O007 unsupported "flow auto" -fa
case_ O008 unsupported "initial scrollback size" -h 10000
case_ O009 unsupported "interrupt output sooner" -i
case_ O010 unsupported "utmp login mode on" -l
case_ O011 unsupported "utmp login mode off" -ln
case_ O012 mapped      "startup logging" -L
case_ O013 mapped      "set logfile path without logging" -Logfile /tmp/screen.log
case_ O014 mapped      "force new Screen session semantics" -m
case_ O015 unsupported "optimized VT output mode" -O
case_ O016 mapped      "preselect then attach" -p 2 -r work
case_ O017 unsupported "Screen authentication flag" -P
case_ O018 mapped      "quiet list" -q -ls
case_ O019 unsupported "default shell override" -s /bin/bash
case_ O020 mapped      "session name" -S work
case_ O021 mapped      "initial window title" -t editor vim
case_ O022 unsupported "virtual terminal type" -T screen-256color
case_ O023 mapped      "UTF-8 mode" -U
case_ O024 mapped      "version short" -v
case_ O025 mapped      "version long" --version
case_ O026 mapped      "help" --help

# Native command-mode informational mappings
case_ N001 mapped      "list attached displays" -S work -X displays
case_ N002 mapped      "display info" -S work -X dinfo
case_ N003 mapped      "list windows internal command" -S work -X windows
case_ N004 mapped      "help/list keys" -S work -X help
case_ N005 mapped      "info internal command" -S work -X info
case_ N006 mapped      "lastmsg internal command" -S work -X lastmsg
case_ N007 mapped      "version internal command" -S work -X version
case_ N008 unsupported "license internal command" -S work -X license
case_ N009 mapped      "layout next" -S work -X layout next
case_ N010 mapped      "layout previous" -S work -X layout prev
case_ N011 mapped      "layout show" -S work -X layout show
case_ N012 mapped      "layout select" -S work -X layout select tiled
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
