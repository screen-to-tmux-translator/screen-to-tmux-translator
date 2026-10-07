/*
 * GNU Screen command-line compatibility for tmux.
 *
 * This file intentionally contains the complete compatibility parser.  It
 * runs before tmux parses its own command line and rewrites Screen-style argv
 * into the corresponding tmux argv when a safe mapping exists.
 */

#include <sys/types.h>

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "tmux.h"

#define SCREEN_COMPAT_VERSION "0.4.17"

struct screen_compat_cmd {
	char	**argv;
	int	  argc;
	int	  size;
};

struct screen_compat {
	int	 dry_run;
	int	 strict;
	int	 strict_blocked;
	int	 Aflag;
	int	 quiet;
	int	 Uflag;
	int	 list;
	int	 wipe;
	int	 detach;
	int	 mflag;
	int	 attach;
	int	 attach_strength;
	int	 xflag;
	int	 log;
	int	 af;
	char	 mode;

	const char	*session;
	const char	*window;
	const char	*screenrc;
	const char	*logfile;
	const char	*title;
	const char	*shell;
	const char	*hist;
	const char	*term;
	const char	*escape;
	char		*unsupported_opt;

	int	 argc;
	char	**argv;
	int	 pos;

	int	 original_argc;
	char	**original_argv;
};

static int	 screen_compat_is_screen(const char *);
static int	 screen_compat_color_enabled(void);
static const char	*screen_compat_class_color(const char *);
static void	 screen_compat_color(FILE *, const char *, const char *);
static void	 screen_compat_report(const char *, const char *, const char *);
static __dead void	 screen_compat_invalid(const char *);
static __dead void	 screen_compat_unsupported(const char *, const char *);
static __dead void	 screen_compat_approx(const char *, const char *);
static __dead void	 screen_compat_moot(const char *, const char *);
static __dead void	 screen_compat_external(const char *, const char *);
static __dead void	 screen_compat_uncertain(const char *, const char *,
	    const char *);
static void	 screen_compat_note(const char *);
static void	 screen_compat_strict_refusal(const char *);
static void	 screen_compat_help(void);
static int	 screen_compat_selector_risky(const char *);
static int	 screen_compat_session_selector_risky(const char *);
static void	 screen_compat_guard_targets(struct screen_compat *);
static char	*screen_compat_target(struct screen_compat *);
static char	*screen_compat_format_literal(const char *);
static char	*screen_compat_join(int, char **);
static char	*screen_compat_quote(const char *);
static int	 screen_compat_program_exists(const char *);

static void	 screen_compat_cmd_init(struct screen_compat_cmd *);
static void	 screen_compat_cmd_add(struct screen_compat_cmd *, const char *);
static void	 screen_compat_cmd_addf(struct screen_compat_cmd *, const char *,
	    ...)
	    __printflike(2, 3);
static void	 screen_compat_cmd_add_argv(struct screen_compat_cmd *, int,
	    char **);
static void	 screen_compat_cmd_prepend_u(struct screen_compat *,
	    struct screen_compat_cmd *);
static void	 screen_compat_print_arg(const char *);
static void	 screen_compat_print_cmd(struct screen_compat_cmd *);
static void	 screen_compat_install_cmd(struct screen_compat *,
	    struct screen_compat_cmd *);
static void	 screen_compat_finish(struct screen_compat *,
	    struct screen_compat_cmd *);
static void	 screen_compat_finish_u(struct screen_compat *,
	    struct screen_compat_cmd *);
static void	 screen_compat_approx_notice(struct screen_compat *,
	    const char *, const char *);
static void	 screen_compat_approx_exec(struct screen_compat *, const char *,
	    const char *, struct screen_compat_cmd *);
static void	 screen_compat_external_exec(struct screen_compat *, const char *,
	    const char *, const char *, struct screen_compat_cmd *);
static void	 screen_compat_external_launch(struct screen_compat *, const char *,
	    const char *, const char *, int, char **);
static int	 screen_compat_known_internal(const char *);
static void	 screen_compat_query(struct screen_compat *, int, char **);
static void	 screen_compat_xcommand(struct screen_compat *, int, char **);
static void	 screen_compat_parse(struct screen_compat *);

static int
screen_compat_is_screen(const char *arg0)
{
	const char	*name;

	if (arg0 == NULL)
		return (0);
	name = strrchr(arg0, '/');
	if (name == NULL)
		name = arg0;
	else
		name++;
	if (*name == '-')
		name++;
	return (strcmp(name, "screen") == 0);
}

static int
screen_compat_color_enabled(void)
{
	const char	*value;

	value = getenv("NO_COLOR");
	if (value != NULL && *value != '\0')
		return (0);
	value = getenv("SCREEN2TMUX_COLOR");
	if (value != NULL) {
		if (strcmp(value, "always") == 0)
			return (1);
		if (strcmp(value, "never") == 0)
			return (0);
		if (*value != '\0' && strcmp(value, "auto") != 0)
			return (0);
	}
	value = getenv("TERM");
	return (isatty(STDERR_FILENO) &&
	    (value == NULL || strcmp(value, "dumb") != 0));
}

static const char *
screen_compat_class_color(const char *class)
{
	if (strcmp(class, "EXACT") == 0)
		return ("\033[32m");
	if (strcmp(class, "APPROX") == 0)
		return ("\033[33m");
	if (strcmp(class, "UNSUPPORTED") == 0 ||
	    strcmp(class, "INVALID") == 0)
		return ("\033[31m");
	if (strcmp(class, "MOOT") == 0)
		return ("\033[36m");
	if (strcmp(class, "EXTERNAL") == 0)
		return ("\033[35m");
	return ("\033[36m");
}

static void
screen_compat_color(FILE *f, const char *color, const char *text)
{
	if (screen_compat_color_enabled())
		fprintf(f, "%s%s\033[0m", color, text);
	else
		fputs(text, f);
}

static void
screen_compat_report(const char *class, const char *reason,
    const char *suggestion)
{
	fputs("screen2tmux: ", stderr);
	screen_compat_color(stderr, screen_compat_class_color(class), class);
	fprintf(stderr, ": %s\n", reason);
	if (suggestion != NULL && *suggestion != '\0') {
		fputs("screen2tmux: ", stderr);
		screen_compat_color(stderr, "\033[36m", "suggestion");
		fprintf(stderr, ": %s\n", suggestion);
	}
}

static __dead void
screen_compat_invalid(const char *text)
{
	fputs("screen2tmux: ", stderr);
	screen_compat_color(stderr, "\033[31m", "invalid/unknown Screen syntax");
	fprintf(stderr, ": %s\n", text);
	exit(64);
}

static __dead void
screen_compat_unsupported(const char *reason, const char *suggestion)
{
	screen_compat_report("UNSUPPORTED", reason, suggestion);
	exit(2);
}

static __dead void
screen_compat_approx(const char *reason, const char *suggestion)
{
	screen_compat_report("APPROX", reason, suggestion);
	exit(3);
}

static __dead void
screen_compat_moot(const char *reason, const char *suggestion)
{
	screen_compat_report("MOOT", reason, suggestion);
	exit(4);
}

static __dead void
screen_compat_external(const char *reason, const char *suggestion)
{
	screen_compat_report("EXTERNAL", reason, suggestion);
	exit(5);
}

static __dead void
screen_compat_uncertain(const char *argument, const char *reason,
    const char *suggestion)
{
	fputs("screen2tmux: ", stderr);
	screen_compat_color(stderr, "\033[33m", "WARNING");
	fprintf(stderr, ": uncertain translation of argument %s: %s\n",
	    argument, reason);
	if (suggestion != NULL && *suggestion != '\0') {
		fputs("screen2tmux: ", stderr);
		screen_compat_color(stderr, "\033[36m", "suggestion");
		fprintf(stderr, ": %s\n", suggestion);
	}
	exit(3);
}

static void
screen_compat_note(const char *text)
{
	fputs("screen2tmux: ", stderr);
	screen_compat_color(stderr, "\033[36m", "note");
	fprintf(stderr, ": %s\n", text);
}

static void
screen_compat_strict_refusal(const char *class)
{
	fputs("screen2tmux: ", stderr);
	screen_compat_color(stderr, "\033[33m", "STRICT");
	fprintf(stderr,
	    ": --strict keeps %s mappings advisory; tmux was not executed.\n",

	    class);
}

static const char screen_compat_help_text[] =
	"screen-to-tmux compatibility help (translator 0.4.17)\n"
	"GNU Screen 5.0.x-style command-line syntax translated to tmux when a safe "
	"mapping exists.\n"
	"This is compatibility help, not byte-for-byte native GNU Screen help.\n"
	"\n"
	"Usage\n"
	"  screen [options] [command [args]]\n"
	"  screen -r [session]\n"
	"  screen -S session -X command [args]\n"
	"  screen -S session -Q command [args]\n"
	"  screen [--dry-run|--dryrun] [--strict] ...\n"
	"\n"
	"Translation classes\n"
	"  EXACT                    [EXACT] Safe mapping; executes tmux "
	"automatically (or prints it in dry-run mode).\n"
	"  APPROX                   [APPROX] Semantics differ; concrete "
	"one-command substitutes execute after a warning, otherwise translation "
	"stays advisory.\n"
	"  UNSUPPORTED              [UNSUPPORTED] Valid Screen behavior has no "
	"safe tmux equivalent; no emulation is invented.\n"
	"  MOOT                     [MOOT] Screen-only maintenance/architecture is "
	"unnecessary under tmux.\n"
	"  EXTERNAL                 [EXTERNAL] Closest substitute needs another "
	"program; concrete helper-backed mappings run when that helper is "
	"installed (unless --strict).\n"
	"  VARIES                   [VARIES] Depends on subcommand, selector, "
	"runtime state, or invocation context.\n"
	"\n"
	"Top-level Screen options\n"
	"  -4 / -6                  [VARIES] Only meaningful for Screen built-in "
	"network forms; external-client substitution may be required.\n"
	"  -a                       [UNSUPPORTED] Screen termcap capability "
	"forcing has no matching tmux CLI operation.\n"
	"  -A                       [VARIES] Inert for a fresh tmux session; "
	"Screen attach-time resize semantics are different.\n"
	"  -c file                  [UNSUPPORTED] screenrc syntax is not tmux.conf "
	"syntax; the same file is never passed to tmux -f.\n"
	"  -d [session]             [EXACT] Detach the selected session clients "
	"for supported unambiguous targets.\n"
	"  -D [session]             [EXACT] Power-detach style top-level operation "
	"for supported unambiguous targets.\n"
	"  -dmS name                [APPROX] Detached named tmux session is close, "
	"but tmux names are unique while Screen labels need not be.\n"
	"  -e xy                    [UNSUPPORTED] Screen command-character pair is "
	"not silently rewritten into tmux prefix configuration.\n"
	"  -f / -fn / -fa           [UNSUPPORTED] Screen flow-control policy has "
	"no direct tmux equivalent.\n"
	"  -h lines                 [UNSUPPORTED] Screen per-invocation initial "
	"history semantics do not map safely to tmux history-limit.\n"
	"  -i                       [UNSUPPORTED] Screen XON/XOFF interrupt policy "
	"has no tmux equivalent.\n"
	"  -l / -ln                 [UNSUPPORTED] Screen utmp login accounting is "
	"not a tmux pane feature.\n"
	"  -ls / -list [match]      [APPROX] tmux list-sessions is useful, but "
	"output/state/exit-code semantics differ.\n"
	"  -L                       [APPROX] tmux pipe-pane can log panes, but "
	"Screen startup/future-window logging policy differs.\n"
	"  -Logfile file            [VARIES] Unsupported alone; with -L, pipe-pane "
	"is only an approximation.\n"
	"  -m                       [VARIES] Forces a new session; inside tmux, "
	"the tmux nesting safeguard can make this non-equivalent.\n"
	"  -O                       [UNSUPPORTED] Legacy Screen VT-output mode is "
	"not mapped to tmux terminal-features automatically.\n"
	"  -p window                [VARIES] Safe simple selectors are preserved; "
	"ambiguous/tmux-significant selectors produce a warning.\n"
	"  -P                       [UNSUPPORTED] Screen-managed authentication "
	"differs from tmux socket/server-access security.\n"
	"  -q                       [VARIES] Quiet behavior is command-specific; "
	"Screen quiet-list exit codes are not tmux-compatible.\n"
	"  -Q command               [VARIES] Queries are translated per command; "
	"some output is exact and some only approximate.\n"
	"  -r [session]             [APPROX] Screen requires a detached session; "
	"tmux normally permits another client.\n"
	"  -R / -RR [session]       [APPROX] Screen attach-or-create "
	"matching/state rules differ from tmux new-session -A.\n"
	"  -s shell                 [UNSUPPORTED] Screen default-shell override is "
	"not applied as a tmux-global side effect.\n"
	"  -S sockname              [APPROX] Screen allows duplicate PID.label "
	"sockets; tmux session names are unique.\n"
	"  -t title                 [EXACT] Initial window title is preserved; "
	"tmux format metacharacters are escaped literally.\n"
	"  -T term                  [UNSUPPORTED] Screen virtual TERM selection is "
	"not silently converted into tmux terminal configuration.\n"
	"  -U                       [APPROX] Screen changes client/output and "
	"new-window encoding semantics; tmux -u is not equivalent.\n"
	"  -v / --version           [UNSUPPORTED] A tmux-backed binary cannot "
	"truthfully report itself as native GNU Screen.\n"
	"  -wipe [match]            [MOOT] tmux does not leave one stale "
	"filesystem socket per session.\n"
	"  -x [session]             [EXACT] tmux natively supports multiple "
	"clients; safe unambiguous targets attach directly.\n"
	"  -X command [args]        [VARIES] Screen commands are translated "
	"individually; see common command groups below.\n"
	"\n"
	"Translator extensions\n"
	"  --dry-run / --dryrun     [EXTENSION] Print the translated tmux argv or "
	"diagnostic instead of executing it.\n"
	"  --strict                 [EXTENSION] Never execute APPROX or EXTERNAL "
	"mappings; APPROX returns 3 and EXTERNAL returns 5.\n"
	"  --help                   [EXTENSION] Show this compatibility-aware help "
	"page.\n"
	"\n"
	"Common -X / -Q command coverage\n"
	"  stuff/select/title/kill  [EXACT] Direct pane/window operations for safe "
	"targets; literal data is protected from tmux format expansion.\n"
	"  next/prev/other/quit     [EXACT] Straightforward tmux window/session "
	"operations for supported targets.\n"
	"  setenv/unsetenv          [EXACT] Mapped to tmux environment operations "
	"in the selected session context.\n"
	"  monitor/silence/vbell    [EXACT] Mapped to the corresponding tmux "
	"window/session monitoring options.\n"
	"  copy/xon/xoff/reset      [EXACT] Mapped to tmux copy/input/reset "
	"operations where source semantics align.\n"
	"  split/focus/resize       [APPROX] Screen display regions and tmux panes "
	"are different object models.\n"
	"  hardcopy FILE / log      [APPROX] capture-pane/pipe-pane are useful "
	"substitutes but output/log policy differs.\n"
	"  truecolor/altscreen      [APPROX] tmux has related "
	"capabilities/options, but scope and terminal model differ.\n"
	"  layout/displays/info     [APPROX] Useful tmux inspection/layout "
	"commands exist; Screen object/output formats differ.\n"
	"  bind/unbindall/ACL       [APPROX] tmux key tables and server access "
	"have broader server-wide scope.\n"
	"  source/chdir/auth        [UNSUPPORTED] No unsafe "
	"config-language/backend/security emulation is attempted.\n"
	"  multiuser/writelock      [UNSUPPORTED] Screen per-session/per-window "
	"security model is not recreated on top of tmux.\n"
	"  encoding/charset         [UNSUPPORTED] Screen character-set machinery "
	"is not reprogrammed in the translator.\n"
	"  paste/removebuf          [UNSUPPORTED] Screen register/exchange-file "
	"semantics differ from tmux server-wide buffers.\n"
	"  /dev/tty*, //telnet      [EXTERNAL] Concrete mappings launch "
	"picocom/telnet inside tmux when installed; tmux itself is not a "
	"serial/telnet engine.\n"
	"\n"
	"Important tmux-underneath differences\n"
	"  * tmux multi-client attachment is native and often simpler, but that "
	"makes Screen -r semantics only approximate.\n"
	"  * tmux uses unique session names; Screen socket labels can repeat "
	"because the PID is part of the socket name.\n"
	"  * tmux panes are PTYs; Screen display regions can show layers/windows "
	"without creating another PTY.\n"
	"  * tmux paste buffers and key tables are server-wide, so the translator "
	"refuses to pretend they are Screen-session-local.\n"
	"  * tmux has one server socket rather than one staleable socket per "
	"session, so Screen -wipe is unnecessary.\n"
	"  * When an argument can be interpreted differently by Screen and tmux, "
	"translation stops with a specific WARNING.\n"
	"\n"
	"Environment controls\n"
	"  SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=1  allow direct -S NAME "
	"creation when your deployment guarantees uniqueness.\n"
	"  SCREEN2TMUX_COLOR=auto|always|never          control selective "
	"diagnostic/help color.\n"
	"  NO_COLOR=1                                  disable ANSI color "
	"unconditionally.\n"
	"\n"
	"Exit status\n"
	"  0 exact/help success or successful executable APPROX/EXTERNAL mapping; "
	"2 unsupported; 3 advisory approximate/uncertain; 4 moot; 5 "
	"advisory/missing-helper external; 64 invalid syntax.\n"
	"  Executed mappings return the underlying tmux command status in normal "
	"mode; --strict never executes APPROX or EXTERNAL.\n"
	;

static void
screen_compat_help(void)
{
	fputs(screen_compat_help_text, stdout);
}

static int
screen_compat_selector_risky(const char *value)
{
	const unsigned char	*p;

	if (value == NULL || *value == '\0')
		return (1);
	for (p = (const unsigned char *)value; *p != '\0'; p++) {
		if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') ||
		    (*p >= '0' && *p <= '9') || *p == '_' || *p == '-')
			continue;
		return (1);
	}
	return (0);
}

static int
screen_compat_session_selector_risky(const char *value)
{
	if (screen_compat_selector_risky(value))
		return (1);
	if (*value >= '0' && *value <= '9')
		return (1);
	if (strncmp(value, "tty", 3) == 0)
		return (1);
	return (0);
}

static void
screen_compat_guard_targets(struct screen_compat *sc)
{
	char	*argument;

	if (sc->session != NULL && *sc->session != '\0' &&
	    screen_compat_session_selector_risky(sc->session)) {
		xasprintf(&argument, "Screen session selector '%s'", sc->session);
		screen_compat_uncertain(argument,
		    "Screen socket matching may interpret leading digits as a PID, may "
		    "strip PID prefixes, treats a tty prefix specially, and otherwise "
		    "uses Screen-specific prefix rules; tmux target syntax has different "
		    "ID, separator, and pattern rules.",

		    "Choose the intended tmux session explicitly and rewrite the target; "
		    "this translator will not guess how that Screen selector should be "
		    "interpreted.");
	}
	if (sc->window != NULL && *sc->window != '\0' &&
	    screen_compat_selector_risky(sc->window)) {
		xasprintf(&argument, "Screen window selector '%s'", sc->window);
		screen_compat_uncertain(argument,
		    "tmux window/pane targets have a different selector grammar from "
		    "Screen window names and numbers.",

		    "Choose the intended tmux window explicitly and rewrite the target; "
		    "this translator will not guess how that Screen selector should be "
		    "interpreted.");
	}
}

static char *
screen_compat_target(struct screen_compat *sc)
{
	char	*target;

	if (sc->session != NULL && *sc->session != '\0' &&
	    sc->window != NULL && *sc->window != '\0') {
		xasprintf(&target, "%s:%s", sc->session, sc->window);
		return (target);
	}
	if (sc->session != NULL && *sc->session != '\0')
		return (xstrdup(sc->session));
	if (sc->window != NULL && *sc->window != '\0') {
		xasprintf(&target, ":%s", sc->window);
		return (target);
	}
	return (NULL);
}

static char *
screen_compat_format_literal(const char *value)
{
	const char	*p;
	char		*out, *q;
	size_t		 hashes = 0, len;

	for (p = value; *p != '\0'; p++) {
		if (*p == '#')
			hashes++;
	}
	len = strlen(value);
	out = xcalloc(len + hashes + 1, 1);
	q = out;
	for (p = value; *p != '\0'; p++) {
		if (*p == '#')
			*q++ = '#';
		*q++ = *p;
	}
	*q = '\0';
	return (out);
}

static char *
screen_compat_join(int argc, char **argv)
{
	char	*out, *p;
	size_t	 len = 1;
	int	 i;

	for (i = 0; i < argc; i++)
		len += strlen(argv[i]) + (i != 0);
	out = xcalloc(len, 1);
	p = out;
	for (i = 0; i < argc; i++) {
		if (i != 0)
			*p++ = ' ';
		memcpy(p, argv[i], strlen(argv[i]));
		p += strlen(argv[i]);
	}
	*p = '\0';
	return (out);
}

static char *
screen_compat_quote(const char *value)
{
	const char	*p;
	char		*out, *q;
	size_t		 quotes = 0, len;

	for (p = value; *p != '\0'; p++) {
		if (*p == '\'')
			quotes++;
	}
	len = strlen(value);
	out = xcalloc(len + quotes * 3 + 3, 1);
	q = out;
	*q++ = '\'';
	for (p = value; *p != '\0'; p++) {
		if (*p == '\'') {
			*q++ = '\'';
			*q++ = '\\';
			*q++ = '\'';
			*q++ = '\'';
		} else
			*q++ = *p;
	}
	*q++ = '\'';
	*q = '\0';
	return (out);
}

static int
screen_compat_program_exists(const char *program)
{
	const char	*path, *start, *end;
	char		*name;

	if (strchr(program, '/') != NULL)
		return (access(program, X_OK) == 0);
	path = getenv("PATH");
	if (path == NULL)
		path = "/bin:/usr/bin";
	start = path;
	for (;;) {
		end = strchr(start, ':');
		if (end == NULL)
			xasprintf(&name, "%s/%s", *start == '\0' ? "." : start,
			    program);
		else if (end == start)
			xasprintf(&name, "./%s", program);
		else {
			char *dir = xcalloc((size_t)(end - start) + 1, 1);
			memcpy(dir, start, (size_t)(end - start));
			xasprintf(&name, "%s/%s", dir, program);
			free(dir);
		}
		if (access(name, X_OK) == 0) {
			free(name);
			return (1);
		}
		free(name);
		if (end == NULL)
			break;
		start = end + 1;
	}
	return (0);
}

static void
screen_compat_cmd_init(struct screen_compat_cmd *cmd)
{
	memset(cmd, 0, sizeof *cmd);
}

static void
screen_compat_cmd_add(struct screen_compat_cmd *cmd, const char *value)
{
	if (cmd->argc + 1 >= cmd->size) {
		cmd->size = cmd->size == 0 ? 8 : cmd->size * 2;
		cmd->argv = xreallocarray(cmd->argv, cmd->size,
		    sizeof *cmd->argv);
	}
	cmd->argv[cmd->argc++] = xstrdup(value);
	cmd->argv[cmd->argc] = NULL;
}

static void
screen_compat_cmd_addf(struct screen_compat_cmd *cmd, const char *fmt, ...)
{
	va_list	 ap;
	char	*value;

	va_start(ap, fmt);
	xvasprintf(&value, fmt, ap);
	va_end(ap);
	screen_compat_cmd_add(cmd, value);
	free(value);
}

static void
screen_compat_cmd_add_argv(struct screen_compat_cmd *cmd, int argc, char **argv)
{
	int	 i;

	for (i = 0; i < argc; i++)
		screen_compat_cmd_add(cmd, argv[i]);
}

static void
screen_compat_cmd_prepend_u(struct screen_compat *sc,
    struct screen_compat_cmd *cmd)
{
	char	**argv;
	int	 i;

	if (!sc->Uflag)
		return;
	argv = xcalloc(cmd->size == 0 ? cmd->argc + 3 : cmd->size + 1,
	    sizeof *argv);
	argv[0] = xstrdup("-u");
	for (i = 0; i < cmd->argc; i++)
		argv[i + 1] = cmd->argv[i];
	free(cmd->argv);
	cmd->argv = argv;
	cmd->argc++;
	cmd->size = cmd->argc + 1;
}

static int
screen_compat_safe_arg(const char *value)
{
	const unsigned char	*p;

	if (*value == '\0')
		return (0);
	for (p = (const unsigned char *)value; *p != '\0'; p++) {
		if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') ||
		    (*p >= '0' && *p <= '9') || strchr("_@%+=:,./-", *p) != NULL)
			continue;
		return (0);
	}
	return (1);
}

static void
screen_compat_print_arg(const char *value)
{
	const unsigned char	*p;

	if (screen_compat_safe_arg(value)) {
		fputs(value, stdout);
		return;
	}
	if (*value == '\0') {
		fputs("''", stdout);
		return;
	}
	putchar('\'');
	for (p = (const unsigned char *)value; *p != '\0'; p++) {
		switch (*p) {
		case '\'':
			fputs("'\\''", stdout);
			break;
		case '\r':
			fputs("\\r", stdout);
			break;
		case '\n':
			fputs("\\n", stdout);
			break;
		case '\t':
			fputs("\\t", stdout);
			break;
		default:
			if (*p >= 32 && *p <= 126)
				putchar(*p);
			else
				printf("\\x%02x", *p);
			break;
		}
	}
	putchar('\'');
}

static void
screen_compat_print_cmd(struct screen_compat_cmd *cmd)
{
	int	 i;

	fputs("tmux", stdout);
	for (i = 0; i < cmd->argc; i++) {
		putchar(' ');
		screen_compat_print_arg(cmd->argv[i]);
	}
	putchar('\n');
}

static void
screen_compat_install_cmd(struct screen_compat *sc,
    struct screen_compat_cmd *cmd)
{
	char	**argv;
	int	 i;

	argv = xcalloc((size_t)cmd->argc + 2, sizeof *argv);
	argv[0] = sc->original_argv[0];
	for (i = 0; i < cmd->argc; i++)
		argv[i + 1] = cmd->argv[i];
	argv[cmd->argc + 1] = NULL;
	free(cmd->argv);
	sc->original_argc = cmd->argc + 1;
	sc->original_argv = argv;
}

static void
screen_compat_finish(struct screen_compat *sc, struct screen_compat_cmd *cmd)
{
	if (sc->strict_blocked) {
		if (sc->dry_run)
			screen_compat_print_cmd(cmd);
		exit(3);
	}
	if (sc->dry_run) {
		screen_compat_print_cmd(cmd);
		exit(0);
	}
	screen_compat_install_cmd(sc, cmd);
}

static void
screen_compat_finish_u(struct screen_compat *sc, struct screen_compat_cmd *cmd)
{
	screen_compat_cmd_prepend_u(sc, cmd);
	screen_compat_finish(sc, cmd);
}

static void
screen_compat_approx_notice(struct screen_compat *sc, const char *reason,
    const char *suggestion)
{
	screen_compat_report("APPROX", reason, suggestion);
	if (sc->strict) {
		sc->strict_blocked = 1;
		screen_compat_strict_refusal("APPROX");
	}
}

static void
screen_compat_approx_exec(struct screen_compat *sc, const char *reason,
    const char *suggestion, struct screen_compat_cmd *cmd)
{
	screen_compat_report("APPROX", reason, suggestion);
	if (sc->strict) {
		screen_compat_strict_refusal("APPROX");
		if (sc->dry_run)
			screen_compat_print_cmd(cmd);
		exit(3);
	}
	screen_compat_finish(sc, cmd);
}

static void
screen_compat_external_exec(struct screen_compat *sc, const char *helper,
    const char *reason, const char *suggestion, struct screen_compat_cmd *cmd)
{
	char	*note;

	screen_compat_report("EXTERNAL", reason, suggestion);
	if (sc->strict) {
		screen_compat_strict_refusal("EXTERNAL");
		if (sc->dry_run)
			screen_compat_print_cmd(cmd);
		exit(5);
	}
	if (sc->dry_run) {
		screen_compat_print_cmd(cmd);
		exit(0);
	}
	if (!screen_compat_program_exists(helper)) {
		xasprintf(&note,
		    "external helper '%s' is not installed; tmux was not executed.",
		    helper);
		screen_compat_note(note);
		exit(5);
	}
	screen_compat_install_cmd(sc, cmd);
}

static void
screen_compat_external_launch(struct screen_compat *sc, const char *helper,
    const char *reason, const char *suggestion, int argc, char **argv)
{
	struct screen_compat_cmd	 cmd;
	char			*session = NULL, *title = NULL;
	const char		*tmux;
	int			 detached;

	screen_compat_cmd_init(&cmd);
	tmux = getenv("TMUX");
	if (tmux != NULL && *tmux != '\0' && !sc->mflag &&
	    (sc->session == NULL || *sc->session == '\0')) {
		screen_compat_cmd_add(&cmd, "new-window");
		if (sc->title != NULL && *sc->title != '\0') {
			title = screen_compat_format_literal(sc->title);
			screen_compat_cmd_add(&cmd, "-n");
			screen_compat_cmd_add(&cmd, title);
		}
		screen_compat_cmd_add_argv(&cmd, argc, argv);
		screen_compat_cmd_prepend_u(sc, &cmd);
		screen_compat_external_exec(sc, helper, reason, suggestion, &cmd);
		return;
	}

	if (sc->session != NULL && *sc->session != '\0')
		session = screen_compat_format_literal(sc->session);
	if (sc->title != NULL && *sc->title != '\0')
		title = screen_compat_format_literal(sc->title);
	detached = sc->detach == 1 && sc->mflag;

	screen_compat_cmd_add(&cmd, "new-session");
	if (detached)
		screen_compat_cmd_add(&cmd, "-d");
	if (session != NULL) {
		screen_compat_cmd_add(&cmd, "-s");
		screen_compat_cmd_add(&cmd, session);
	}
	if (title != NULL) {
		screen_compat_cmd_add(&cmd, "-n");
		screen_compat_cmd_add(&cmd, title);
	}
	screen_compat_cmd_add_argv(&cmd, argc, argv);
	screen_compat_cmd_prepend_u(sc, &cmd);
	screen_compat_external_exec(sc, helper, reason, suggestion, &cmd);
}

static const char *screen_compat_internal_commands[] = {
	"acladd", "aclchg", "acldel", "aclgrp", "aclumask", "activity",
	"addacl", "allpartial", "altscreen", "at", "auth", "autodetach",
	"autonuke", "backtick", "bce", "bell", "bell_msg", "bind",
	"bindkey", "blanker", "blankerprg", "break", "breaktype",
	"bufferfile", "bumpleft", "bumpright", "c1", "caption", "chacl",
	"charset", "chdir", "cjkwidth", "clear", "collapse", "colon",
	"command", "compacthist", "console", "copy", "crlf", "defautonuke",
	"defbce", "defbreaktype", "defc1", "defcharset", "defdynamictitle",
	"defencoding", "defescape", "defflow", "defgr", "defhstatus",
	"defkanji", "deflog", "deflogin", "defmode", "defmonitor",
	"defmousetrack", "defnonblock", "defobuflimit", "defscrollback",
	"defshell", "defsilence", "defslowpaste", "defutf8", "defwrap",
	"defwritelock", "detach", "digraph", "dinfo", "displays",
	"dumptermcap", "dynamictitle", "echo", "encoding", "escape", "eval",
	"exec", "fit", "flow", "focus", "focusminsize", "gr", "group",
	"hardcopy", "hardcopy_append", "hardcopydir", "hardstatus", "height",
	"help", "history", "hstatus", "idle", "ignorecase", "info", "kanji",
	"kill", "lastmsg", "layout", "license", "lockscreen", "log",
	"logfile", "login", "logtstamp", "mapdefault", "mapnotnext",
	"maptimeout", "markkeys", "meta", "monitor", "mousetrack",
	"msgminwait", "msgwait", "multiinput", "multiuser", "next",
	"nonblock", "number", "obuflimit", "only", "other", "parent",
	"partial", "paste", "pastefont", "pow_break", "pow_detach",
	"pow_detach_msg", "prev", "printcmd", "process", "quit", "readbuf",
	"readreg", "redisplay", "register", "remove", "removebuf", "rendition",
	"reset", "resize", "screen", "scrollback", "select", "sessionname",
	"setenv", "setsid", "shell", "shelltitle", "silence", "silencewait",
	"sleep", "slowpaste", "sorendition", "sort", "source", "split",
	"startup_message", "status", "stuff", "su", "suspend", "term",
	"termcap", "termcapinfo", "terminfo", "title", "truecolor", "umask",
	"unbindall", "unsetenv", "utf8", "vbell", "vbell_msg", "vbellwait",
	"verbose", "version", "wall", "width", "windowlist", "windows", "wrap",
	"writebuf", "writelock", "xoff", "xon", "zmodem", "zombie",
	"zombie_timeout", NULL
};

static int
screen_compat_known_internal(const char *name)
{
	const char	**p;

	for (p = screen_compat_internal_commands; *p != NULL; p++) {
		if (strcmp(*p, name) == 0)
			return (1);
	}
	return (0);
}

static void
screen_compat_query(struct screen_compat *sc, int argc, char **argv)
{
	struct screen_compat_cmd	 cmd;
	char			*target, *text;
	const char		*name;

	if (argc == 0)
		screen_compat_invalid("-Q requires a query command");
	name = argv[0];
	argc--;
	argv++;
	screen_compat_guard_targets(sc);
	target = screen_compat_target(sc);
	screen_compat_cmd_init(&cmd);

	if (strcmp(name, "windows") == 0) {
		screen_compat_cmd_add(&cmd, "list-windows");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
			xasprintf(&text,
			    "Executing closest substitute; use -F to build output compatible "
			    "with the consumer if exact formatting matters: tmux list-windows -t "
			    "%s",
			    sc->session);
		} else
			text = xstrdup(
			    "Executing closest substitute; use -F to build output compatible "
			    "with the consumer if exact formatting matters: tmux list-windows");
		screen_compat_approx_exec(sc,
		    "Screen -Q windows has Screen-specific window-list formatting and "
		    "markers; tmux list-windows reports a different format.",

		    text, &cmd);
	}
	if (strcmp(name, "number") == 0) {
		screen_compat_cmd_add(&cmd, "display-message");
		screen_compat_cmd_add(&cmd, "-p");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_cmd_add(&cmd, "#{window_index} (#{window_name})");
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "title") == 0) {
		screen_compat_cmd_add(&cmd, "display-message");
		screen_compat_cmd_add(&cmd, "-p");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_cmd_add(&cmd, "#W");
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "info") == 0) {
		screen_compat_cmd_add(&cmd, "display-message");
		screen_compat_cmd_add(&cmd, "-p");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_cmd_add(&cmd,
		    "#{session_name}:#{window_index}.#{pane_index} "
		    "#{pane_width}x#{pane_height} #{pane_current_command}");
		screen_compat_approx_exec(sc,
		    "Screen -Q info emits Screen's own fixed status summary; tmux has no "
		    "byte-compatible equivalent.",

		    "Executing a useful tmux status summary with explicit format fields.",
		    &cmd);
	}
	if (strcmp(name, "lastmsg") == 0) {
		screen_compat_cmd_add(&cmd, "show-messages");
		screen_compat_approx_exec(sc,
		    "Screen -Q lastmsg returns Screen's single most recent message; tmux "
		    "show-messages returns a message history with different formatting "
		    "and scope.",

		    "Executing tmux show-messages; scripts that need exactly one "
		    "Screen-style message must select the desired entry explicitly.",
		    &cmd);
	}
	if (strcmp(name, "echo") == 0) {
		if (argc == 0)
			screen_compat_invalid("echo requires a string");
		if (argc == 1 || (argc == 2 && strcmp(argv[0], "-n") == 0)) {
			screen_compat_cmd_add(&cmd, "display-message");
			screen_compat_cmd_add(&cmd, "-pl");
			screen_compat_cmd_add(&cmd, argc == 1 ? argv[0] : argv[1]);
			screen_compat_finish(sc, &cmd);
			return;
		}
		if (argc == 2 && strcmp(argv[0], "-p") == 0)
			screen_compat_unsupported(
			    "Screen echo -p expands Screen's own % status-format language; tmux "
			    "formats use a different #{} language.",

			    "Translate the Screen format deliberately instead of passing it to "
			    "tmux display-message.");
		text = screen_compat_join(argc, argv);
		{
			char *argument;
			xasprintf(&argument, "echo arguments '%s'", text);
			screen_compat_uncertain(argument,
			    "Screen accepts a narrow one/two-argument form and extra argument "
			    "interpretation is not safely representable as a tmux "
			    "display-message invocation.",

			    "Use Screen's documented 'echo [-n] [-p] string' form and translate "
			    "the intended formatting explicitly.");
		}
	}
	if (strcmp(name, "select") == 0) {
		if (argc > 0) {
			screen_compat_cmd_add(&cmd, "select-window");
			screen_compat_cmd_add(&cmd, "-t");
			if (sc->session != NULL && *sc->session != '\0')
				screen_compat_cmd_addf(&cmd, "%s:%s", sc->session, argv[0]);
			else
				screen_compat_cmd_addf(&cmd, ":%s", argv[0]);
		} else {
			screen_compat_cmd_add(&cmd, "display-message");
			screen_compat_cmd_add(&cmd, "-p");
			if (target != NULL) {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, target);
			}
			screen_compat_cmd_add(&cmd, "#I #W");
		}
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (screen_compat_known_internal(name)) {
		xasprintf(&text,
		    "Screen command '%s' is recognized, but Screen only permits a subset "
		    "of commands to return useful -Q results.",
		    name);
		screen_compat_unsupported(text,
		    "Use tmux list-*, show-*, or display-message -p with format variables.");
	}
	xasprintf(&text, "unknown -Q command '%s'", name);
	screen_compat_invalid(text);
}

static void
screen_compat_xcommand(struct screen_compat *sc, int argc, char **argv)
{
	struct screen_compat_cmd	 cmd;
	char			*target, *text, *text2, *joined, *quoted;
	char			*name_tmux, *nw_target;
	const char		*name, *value, *nw_name = NULL, *nw_index = NULL;
	const char		*nw_hist = NULL, *sel, *state;
	int			 i;

	if (argc == 0)
		screen_compat_invalid("-X requires a Screen command");
	name = argv[0];
	argc--;
	argv++;
	screen_compat_guard_targets(sc);
	target = screen_compat_target(sc);
	screen_compat_cmd_init(&cmd);

	if (strcmp(name, "screen") == 0) {
		i = 0;
		while (i < argc) {
			if (strcmp(argv[i], "-t") == 0) {
				if (++i >= argc)
					screen_compat_invalid("screen -t requires a title");
				nw_name = argv[i++];
				continue;
			}
			if (strcmp(argv[i], "-h") == 0) {
				if (++i >= argc)
					screen_compat_invalid("screen -h requires a history size");
				nw_hist = argv[i++];
				continue;
			}
			if (strcmp(argv[i], "--") == 0) {
				i++;
				break;
			}
			if (argv[i][0] == '-') {
				xasprintf(&text,
				    "internal Screen 'screen' option '%s' has no safe generic tmux "
				    "translation in this release.",
				    argv[i]);
				screen_compat_unsupported(text,
				    "Create the window with tmux new-window and configure the "
				    "corresponding tmux option explicitly.");
			}
			if (argv[i][0] >= '0' && argv[i][0] <= '9') {
				char *colon = strchr(argv[i], ':');
				if (colon != NULL) {
					char *index = xcalloc((size_t)(colon - argv[i]) + 1, 1);
					memcpy(index, argv[i], (size_t)(colon - argv[i]));
					nw_index = index;
					nw_name = colon + 1;
					i++;
					break;
				}
				nw_index = argv[i++];
				break;
			}
			break;
		}
		if (nw_hist != NULL && *nw_hist != '\0') {
			xasprintf(&text,
			    "Screen can choose scrollback size while creating this window; tmux "
			    "history-limit is an option whose creation-time semantics are "
			    "server/session scoped.");
			xasprintf(&text2,
			    "Set 'history-limit %s' in tmux.conf before creating panes, then use "
			    "tmux new-window.",
			    nw_hist);
			screen_compat_unsupported(text, text2);
		}
		if (nw_index != NULL && *nw_index != '\0') {
			xasprintf(&text,
			    "Screen treats window number '%s' as StartAt and chooses the first "
			    "free number at or above it; tmux -t :N addresses exact index N and "
			    "fails if that index is occupied.",
			    nw_index);
			xasprintf(&text2,
			    "Executing the closest exact-index tmux new-window mapping. If index "
			    "%s is occupied, tmux may fail where Screen would search upward.",
			    nw_index);
			screen_compat_approx_notice(sc, text, text2);
		}
		if (sc->session != NULL && *sc->session != '\0' &&
		    nw_index != NULL && *nw_index != '\0')
			xasprintf(&nw_target, "%s:%s", sc->session, nw_index);
		else if (sc->session != NULL && *sc->session != '\0')
			nw_target = xstrdup(sc->session);
		else if (nw_index != NULL && *nw_index != '\0')
			xasprintf(&nw_target, ":%s", nw_index);
		else
			nw_target = NULL;
		name_tmux = nw_name == NULL || *nw_name == '\0' ? NULL :
		    screen_compat_format_literal(nw_name);
		screen_compat_cmd_add(&cmd, "new-window");
		if (nw_target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, nw_target);
		}
		if (name_tmux != NULL) {
			screen_compat_cmd_add(&cmd, "-n");
			screen_compat_cmd_add(&cmd, name_tmux);
		}
		screen_compat_cmd_add_argv(&cmd, argc - i, argv + i);
		screen_compat_finish(sc, &cmd);
		return;
	}

	if (strcmp(name, "select") == 0) {
		sel = argc > 0 ? argv[0] : sc->window;
		if (sel == NULL || *sel == '\0')
			screen_compat_invalid(
			    "select requires a target window in noninteractive translation");
		screen_compat_cmd_add(&cmd, "select-window");
		screen_compat_cmd_add(&cmd, "-t");
		if (sc->session != NULL && *sc->session != '\0')
			screen_compat_cmd_addf(&cmd, "%s:%s", sc->session, sel);
		else
			screen_compat_cmd_addf(&cmd, ":%s", sel);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "title") == 0) {
		if (argc == 0)
			screen_compat_invalid("title requires a title in shell translation");
		name_tmux = screen_compat_format_literal(argv[0]);
		screen_compat_cmd_add(&cmd, "rename-window");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_cmd_add(&cmd, name_tmux);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "number") == 0) {
		if (argc == 0) {
			screen_compat_cmd_add(&cmd, "display-message");
			screen_compat_cmd_add(&cmd, "-p");
			if (target != NULL) {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, target);
			}
			screen_compat_cmd_add(&cmd, "#I");
			screen_compat_finish(sc, &cmd);
			return;
		}
		if (target == NULL)
			screen_compat_unsupported(
			    "renumbering requires a determinate Screen window target.",
			    "Use screen -S session -p window -X number N and inspect the "
			    "destination before choosing a tmux operation.");
		if (sc->session != NULL && *sc->session != '\0')
			xasprintf(&text, "%s:%s", sc->session, argv[0]);
		else
			xasprintf(&text, ":%s", argv[0]);
		screen_compat_cmd_add(&cmd, "move-window");
		screen_compat_cmd_add(&cmd, "-s");
		screen_compat_cmd_add(&cmd, target);
		screen_compat_cmd_add(&cmd, "-t");
		screen_compat_cmd_add(&cmd, text);
		xasprintf(&text2,
		    "Executing the non-destructive closest substitute: tmux move-window "
		    "-s %s -t %s. If the destination is occupied, tmux will fail instead "
		    "of replacing it; use swap-window explicitly when Screen's "
		    "occupied-slot behavior is required.",
		    target, text);
		screen_compat_approx_exec(sc,
		    "Screen number swaps window numbers when the destination is occupied, "
		    "whereas tmux move-window fails when the destination is occupied.",

		    text2, &cmd);
	}
	if (strcmp(name, "kill") == 0) {
		screen_compat_cmd_add(&cmd, "kill-window");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "next") == 0 || strcmp(name, "prev") == 0 ||
	    strcmp(name, "other") == 0) {
		screen_compat_cmd_add(&cmd,
		    strcmp(name, "next") == 0 ? "next-window" :
		    strcmp(name, "prev") == 0 ? "previous-window" : "last-window");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
		}
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "collapse") == 0) {
		screen_compat_cmd_add(&cmd, "move-window");
		screen_compat_cmd_add(&cmd, "-r");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
			xasprintf(&text,
			    "Executing tmux move-window -r -t %s; the result is "
			    "Screen-compatible only when tmux base-index is 0.",
			    sc->session);
		} else
			text = xstrdup(
			    "Executing tmux move-window -r; the result is Screen-compatible only "
			    "when tmux base-index is 0.");
		screen_compat_approx_exec(sc,
		    "Screen collapse always renumbers windows consecutively from 0; tmux "
		    "move-window -r starts from the session's base-index option.",

		    text, &cmd);
	}
	if (strcmp(name, "sort") == 0)
		screen_compat_unsupported(
		    "Screen mutates window numbers by sorting actual windows "
		    "alphabetically; tmux can sort list/chooser views but has no direct "
		    "mutating sort command.",

		    "Script list-windows plus move-window if persistent alphabetical "
		    "indices are required.");
	if (strcmp(name, "stuff") == 0) {
		if (argc == 0)
			screen_compat_invalid("stuff requires text");
		joined = screen_compat_join(argc, argv);
		screen_compat_cmd_add(&cmd, "send-keys");
		screen_compat_cmd_add(&cmd, "-l");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_cmd_add(&cmd, joined);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "xon") == 0 || strcmp(name, "xoff") == 0) {
		screen_compat_cmd_add(&cmd, "send-keys");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_cmd_add(&cmd, strcmp(name, "xon") == 0 ? "C-q" : "C-s");
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "split") == 0) {
		int horizontal = argc > 0 && strcmp(argv[0], "-v") == 0;
		screen_compat_cmd_add(&cmd, "split-window");
		screen_compat_cmd_add(&cmd, horizontal ? "-h" : "-v");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		if (horizontal) {
			if (target != NULL)
				xasprintf(&text,
				    "Executing the closest visual substitute: tmux split-window -h -t "
				    "%s.",
				    target);
			else
				text = xstrdup(
				    "Executing the closest visual substitute: tmux split-window -h.");
			screen_compat_approx_exec(sc,
			    "Screen split -v creates another display region without creating a "
			    "new PTY; tmux split-window -h creates a new pane/PTY.",
			    text, &cmd);
		} else {
			if (target != NULL)
				xasprintf(&text,
				    "Executing the closest visual substitute: tmux split-window -v -t "
				    "%s.",
				    target);
			else
				text = xstrdup(
				    "Executing the closest visual substitute: tmux split-window -v.");
			screen_compat_approx_exec(sc,
			    "Screen split creates another display region without creating a new "
			    "PTY; tmux split-window -v creates a new pane/PTY.",
			    text, &cmd);
		}
	}
	if (strcmp(name, "focus") == 0) {
		const char *direction = argc > 0 ? argv[0] : "next";
		const char *suffix;
		if (*direction == '\0' || strcmp(direction, "next") == 0)
			suffix = ".+";
		else if (strcmp(direction, "prev") == 0)
			suffix = ".-";
		else if (strcmp(direction, "up") == 0)
			suffix = ".{up-of}";
		else if (strcmp(direction, "down") == 0)
			suffix = ".{down-of}";
		else if (strcmp(direction, "left") == 0)
			suffix = ".{left-of}";
		else if (strcmp(direction, "right") == 0)
			suffix = ".{right-of}";
		else if (strcmp(direction, "top") == 0)
			suffix = ".{top}";
		else if (strcmp(direction, "bottom") == 0)
			suffix = ".{bottom}";
		else {
			xasprintf(&text, "unknown focus direction '%s'", direction);
			screen_compat_invalid(text);
		}
		if (sc->session != NULL && *sc->session != '\0')
			xasprintf(&text, "%s:%s", sc->session, suffix);
		else
			text = xstrdup(suffix);
		screen_compat_cmd_add(&cmd, "select-pane");
		screen_compat_cmd_add(&cmd, "-t");
		screen_compat_cmd_add(&cmd, text);
		xasprintf(&text2,
		    "Executing the closest substitute: tmux select-pane -t %s",
		    text);
		screen_compat_approx_exec(sc,
		    "Screen focus moves among display regions; tmux select-pane moves "
		    "among PTY panes, so the object model is different.",
		    text2, &cmd);
	}
	if (strcmp(name, "only") == 0) {
		screen_compat_cmd_add(&cmd, "resize-pane");
		screen_compat_cmd_add(&cmd, "-Z");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
			xasprintf(&text,
			    "Executing the closest non-destructive substitute: tmux resize-pane "
			    "-Z -t %s.",
			    target);
		} else
			text = xstrdup(
			    "Executing the closest non-destructive substitute: tmux resize-pane "
			    "-Z.");
		screen_compat_approx_exec(sc,
		    "Screen 'only' removes the other display regions while preserving "
		    "their windows; tmux zoom merely hides other panes temporarily.",

		    text, &cmd);
	}
	if (strcmp(name, "remove") == 0)
		screen_compat_unsupported(
		    "Screen removes a display region without killing its window; tmux has "
		    "no separate region object because a pane is both the PTY and the "
		    "layout object.",

		    "Use resize-pane -Z to zoom, or break-pane before kill-pane if you "
		    "need to preserve the process.");
	if (strcmp(name, "fit") == 0)
		screen_compat_unsupported(
		    "Screen fits a window layer to a display region; tmux automatically "
		    "sizes pane PTYs to their layout cells.",

		    "Usually no command is needed; use resize-pane/resize-window if "
		    "explicit geometry is required.");
	if (strcmp(name, "resize") == 0) {
		if (argc == 0)
			screen_compat_unsupported(
			    "Interactive Screen resize without an amount has no safe "
			    "noninteractive one-command mapping.",

			    "Use tmux resize-pane -L/-R/-U/-D N or resize-pane -x/-y.");
		xasprintf(&text,
		    "Choose the appropriate tmux resize-pane direction explicitly for the "
		    "pane layout; requested Screen amount was '%s'.",
		    argv[0]);
		screen_compat_approx(
		    "Screen resize changes a display-region boundary according to "
		    "Screen's region orientation; mapping '+/-' to a fixed tmux direction "
		    "would be wrong.",

		    text);
	}
	if (strcmp(name, "redisplay") == 0)
		screen_compat_approx(
		    "Screen redisplay acts on a particular attached Display; a Screen "
		    "session selector does not identify one unique tmux client when "
		    "several clients are attached.",

		    "From the intended tmux client use: tmux refresh-client. Otherwise "
		    "choose a concrete client from 'tmux list-clients -t SESSION' and use "
		    "refresh-client -t CLIENT.");
	if (strcmp(name, "detach") == 0)
		screen_compat_approx(
		    "Screen's internal detach command requires one concrete Display and "
		    "detaches that Display only; tmux detach-client -s SESSION would "
		    "detach every client attached to the session.",

		    "From the intended tmux client use: tmux detach-client. Otherwise "
		    "identify one client with tmux list-clients -t SESSION and use tmux "
		    "detach-client -t CLIENT.");
	if (strcmp(name, "pow_detach") == 0)
		screen_compat_approx(
		    "Screen's internal pow_detach acts on one concrete Display and also "
		    "signals that attacher's parent; a session-wide tmux detach would "
		    "broaden the operation.",

		    "From the intended client use tmux detach-client -P, or select one "
		    "concrete client and use tmux detach-client -P -t CLIENT.");
	if (strcmp(name, "suspend") == 0)
		screen_compat_approx(
		    "Screen suspend operates on the invoking/selected Display; an "
		    "external Screen session selector does not uniquely identify a tmux "
		    "client.",

		    "From the intended tmux client use: tmux suspend-client. Otherwise "
		    "choose a concrete target-client explicitly.");
	if (strcmp(name, "quit") == 0) {
		if (sc->session == NULL || *sc->session == '\0')
			screen_compat_unsupported(
			    "Screen 'quit' kills its one Screen session, while tmux may hold "
			    "many sessions in one server.",

			    "Specify screen -S name -X quit so it can map to tmux kill-session "
			    "-t name; use tmux kill-server only if you truly want every tmux "
			    "session.");
		screen_compat_cmd_add(&cmd, "kill-session");
		screen_compat_cmd_add(&cmd, "-t");
		screen_compat_cmd_add(&cmd, sc->session);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "lockscreen") == 0) {
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "lock-session");
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
			xasprintf(&text,
			    "Executing the closest selectable substitute with that broader "
			    "scope: tmux lock-session -t %s.",
			    sc->session);
			screen_compat_approx_exec(sc,
			    "Screen lockscreen locks one Screen display; tmux lock-session locks "
			    "every client attached to the selected tmux session.",
			    text, &cmd);
		} else {
			screen_compat_cmd_add(&cmd, "lock-client");
			screen_compat_approx_exec(sc,
			    "Screen lockscreen locks the current Screen display; tmux "
			    "lock-client locks the current tmux client.",

			    "Executing the closest current-client substitute: tmux lock-client.",
			    &cmd);
		}
	}
	if (strcmp(name, "sessionname") == 0) {
		if (argc == 0)
			screen_compat_invalid(
			    "sessionname requires a new name in shell translation");
		name_tmux = screen_compat_format_literal(argv[0]);
		screen_compat_cmd_add(&cmd, "rename-session");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
		}
		screen_compat_cmd_add(&cmd, name_tmux);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "hardcopy") == 0) {
		int history = 0;
		const char *file = NULL;
		if (argc > 0 && strcmp(argv[0], "-h") == 0) {
			history = 1;
			argc--;
			argv++;
		}
		if (argc > 0)
			file = argv[0];
		if (target != NULL) {
			quoted = screen_compat_quote(target);
			xasprintf(&text, history ?
			    "tmux capture-pane -p -S - -t %s" :
			    "tmux capture-pane -p -t %s", quoted);
		} else
			text = xstrdup(history ? "tmux capture-pane -p -S -" :
			    "tmux capture-pane -p");
		if (file != NULL && *file != '\0') {
			quoted = screen_compat_quote(file);
			xasprintf(&text2, "Closest substitute: %s > %s.", text, quoted);
			screen_compat_approx(
			    "Screen hardcopy and tmux capture-pane are close but not "
			    "byte-for-byte equivalent in whitespace/history/rendering details, "
			    "so automatic execution could change saved output.",
			    text2);
		}
		screen_compat_unsupported(
		    "Screen hardcopy without a filename writes to Screen's hardcopy "
		    "naming convention; tmux capture-pane normally writes to stdout.",

		    "Use an explicit file with tmux capture-pane -p > file after "
		    "reviewing the formatting differences.");
	}
	if (strcmp(name, "scrollback") == 0) {
		if (argc == 0)
			screen_compat_invalid("scrollback requires a line count");
		screen_compat_unsupported(
		    "Changing Screen scrollback on an existing window does not map "
		    "exactly to tmux history-limit for an already-created pane.",

		    "Set tmux history-limit before pane creation (usually in tmux.conf).");
	}
	if (strcmp(name, "readbuf") == 0 || strcmp(name, "writebuf") == 0) {
		if (argc == 0)
			screen_compat_invalid(strcmp(name, "readbuf") == 0 ?
			    "readbuf requires a filename for noninteractive translation" :
			    "writebuf requires a filename for noninteractive translation");
		xasprintf(&text, "screen2tmux:%s:copy",
		    sc->session != NULL && *sc->session != '\0' ? sc->session : "default");
		screen_compat_cmd_add(&cmd, strcmp(name, "readbuf") == 0 ?
		    "load-buffer" : "save-buffer");
		screen_compat_cmd_add(&cmd, "-b");
		screen_compat_cmd_add(&cmd, text);
		screen_compat_cmd_add(&cmd, argv[0]);
		if (strcmp(name, "readbuf") == 0) {
			xasprintf(&text2,
			    "Executing with a session-namespaced tmux buffer: tmux load-buffer "
			    "-b %s '%s'.",
			    text, argv[0]);
			screen_compat_approx_exec(sc,
			    "Screen readbuf loads the current Screen user's copy buffer inside "
			    "one Screen backend; tmux paste buffers are shared by the entire "
			    "tmux server.",
			    text2, &cmd);
		} else {
			xasprintf(&text2,
			    "Executing with the same session-namespaced compatibility buffer: "
			    "tmux save-buffer -b %s '%s'.",
			    text, argv[0]);
			screen_compat_approx_exec(sc,
			    "Screen writebuf writes the current Screen user's copy buffer; tmux "
			    "paste buffers are server-wide and shared by the entire tmux server.",
			    text2, &cmd);
		}
	}
	if (strcmp(name, "removebuf") == 0)
		screen_compat_unsupported(
		    "Screen removebuf deletes Screen's exchange file (BufferFile); it "
		    "does not delete the in-memory copy buffer, so tmux delete-buffer "
		    "would perform a different operation.",

		    "If you intended to remove Screen's exchange file, remove that file "
		    "explicitly. If you intended to clear a tmux paste buffer, use tmux "
		    "delete-buffer deliberately.");
	if (strcmp(name, "register") == 0) {
		if (argc < 2)
			screen_compat_invalid("register requires a register name and string");
		xasprintf(&text, "screen2tmux:%s:reg:%s",
		    sc->session != NULL && *sc->session != '\0' ? sc->session : "default",
		    argv[0]);
		joined = screen_compat_join(argc - 1, argv + 1);
		screen_compat_cmd_add(&cmd, "set-buffer");
		screen_compat_cmd_add(&cmd, "-b");
		screen_compat_cmd_add(&cmd, text);
		screen_compat_cmd_add(&cmd, joined);
		xasprintf(&text2,
		    "Executing with a session-namespaced tmux buffer: tmux set-buffer -b "
		    "%s TEXT.",
		    text);
		screen_compat_approx_exec(sc,
		    "Screen named registers belong to the Screen backend, while tmux "
		    "named paste buffers are server-wide and can collide with unrelated "
		    "sessions.",
		    text2, &cmd);
	}
	if (strcmp(name, "paste") == 0) {
		if (argc == 0)
			screen_compat_unsupported(
			    "Screen paste with no register argument enters Screen's interactive "
			    "register prompt; tmux paste-buffer immediately pastes a server-wide "
			    "buffer, so the previous mapping was not equivalent.",

			    "Specify the intended Screen register and translate it to a "
			    "session-namespaced tmux buffer, or enter tmux "
			    "copy-mode/paste-buffer explicitly.");
		screen_compat_approx(
		    "Screen paste can concatenate Screen registers/copy buffers with "
		    "Screen-specific encoding semantics; tmux paste-buffer uses "
		    "server-wide named buffers and a different model.",

		    "Translate the requested registers into session-namespaced tmux "
		    "buffers and paste the intended buffer explicitly.");
	}
	if (strcmp(name, "copy") == 0) {
		screen_compat_cmd_add(&cmd, "copy-mode");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "log") == 0) {
		value = argc > 0 ? argv[0] : "";
		if (strcmp(value, "on") == 0) {
			screen_compat_cmd_add(&cmd, "pipe-pane");
			screen_compat_cmd_add(&cmd, "-o");
			if (target != NULL) {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, target);
			}
			screen_compat_cmd_add(&cmd, "cat >>screenlog.#{window_index}");
			if (target != NULL)
				xasprintf(&text,
				    "Executing the closest default-policy substitute: tmux pipe-pane -o "
				    "-t %s 'cat >>screenlog.#{window_index}'. If the Screen session "
				    "used a custom logfile pattern, choose that destination explicitly.",
				    target);
			else
				text = xstrdup(
				    "Executing the closest default-policy substitute: tmux pipe-pane -o "
				    "'cat >>screenlog.#{window_index}'. If the Screen session used a "
				    "custom logfile pattern, choose that destination explicitly.");
			screen_compat_approx_exec(sc,
			    "Screen 'log on' uses Screen's configured logfile policy; tmux "
			    "pipe-pane is a general pane-output pipe and cannot recover a Screen "
			    "logfile pattern configured in an earlier Screen process.",
			    text, &cmd);
		}
		if (strcmp(value, "off") == 0) {
			screen_compat_cmd_add(&cmd, "pipe-pane");
			if (target != NULL) {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, target);
				xasprintf(&text,
				    "Executing tmux pipe-pane -t %s. This may also close a non-logging "
				    "pipe installed by other tmux configuration.",
				    target);
			} else
				text = xstrdup(
				    "Executing tmux pipe-pane. This may also close a non-logging pipe "
				    "installed by other tmux configuration.");
			screen_compat_approx_exec(sc,
			    target != NULL ?
			    "Screen 'log off' disables Screen's logger; tmux pipe-pane without a "
			    "command closes whatever output pipe the pane currently has." :
			    "Screen 'log off' disables Screen's logger; tmux pipe-pane without a "
			    "command closes whatever output pipe the current pane has.",

			    text, &cmd);
		}
		screen_compat_invalid("log expects on or off in shell translation");
	}
	if (strcmp(name, "logfile") == 0)
		screen_compat_unsupported(
		    "Screen has a built-in logfile naming/flush subsystem; tmux logging "
		    "is implemented with pipe-pane to an external process.",

		    "Use tmux pipe-pane -o 'cat >>file'; put tmux format variables such "
		    "as #{session_name}, #{window_index}, and #{pane_index} in the shell "
		    "command.");
	if (strcmp(name, "logtstamp") == 0)
		screen_compat_unsupported(
		    "Screen can insert inactivity timestamps into its built-in logs; tmux "
		    "has no equivalent logging filter.",

		    "Pipe the pane through an external timestamping program using tmux "
		    "pipe-pane.");
	if (strcmp(name, "monitor") == 0) {
		state = argc > 0 ? argv[0] : "on";
		if (strcmp(state, "on") != 0 && strcmp(state, "off") != 0)
			screen_compat_invalid("monitor expects on/off");
		screen_compat_cmd_add(&cmd, "set-option");
		screen_compat_cmd_add(&cmd, target != NULL ? "-wt" : "-w");
		if (target != NULL)
			screen_compat_cmd_add(&cmd, target);
		screen_compat_cmd_add(&cmd, "monitor-activity");
		screen_compat_cmd_add(&cmd, state);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "silence") == 0) {
		value = argc > 0 ? argv[0] : "on";
		if (strcmp(value, "off") == 0)
			value = "0";
		else if (strcmp(value, "on") == 0)
			value = "30";
		for (i = 0; value[i] != '\0'; i++) {
			if (value[i] < '0' || value[i] > '9')
				screen_compat_invalid("silence expects on/off/seconds");
		}
		screen_compat_cmd_add(&cmd, "set-option");
		screen_compat_cmd_add(&cmd, target != NULL ? "-wt" : "-w");
		if (target != NULL)
			screen_compat_cmd_add(&cmd, target);
		screen_compat_cmd_add(&cmd, "monitor-silence");
		screen_compat_cmd_add(&cmd, value);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "vbell") == 0) {
		if (argc == 0 || (strcmp(argv[0], "on") != 0 &&
		    strcmp(argv[0], "off") != 0))
			screen_compat_invalid("vbell expects on/off");
		screen_compat_cmd_add(&cmd, "set-option");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
		} else
			screen_compat_cmd_add(&cmd, "-g");
		screen_compat_cmd_add(&cmd, "visual-bell");
		screen_compat_cmd_add(&cmd, argv[0]);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "source") == 0) {
		if (argc == 0)
			screen_compat_invalid("source requires a filename");
		screen_compat_unsupported(
		    "Screen 'source' reads Screen command syntax, which tmux source-file "
		    "cannot parse.",

		    "Translate the screenrc fragment to tmux.conf syntax first, then use "
		    "tmux source-file on the translated file.");
	}
	if (strcmp(name, "setenv") == 0) {
		if (argc < 2)
			screen_compat_invalid(
			    "setenv requires NAME VALUE in noninteractive translation");
		joined = screen_compat_join(argc - 1, argv + 1);
		screen_compat_cmd_add(&cmd, "set-environment");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
		}
		screen_compat_cmd_add(&cmd, argv[0]);
		screen_compat_cmd_add(&cmd, joined);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "unsetenv") == 0) {
		if (argc == 0)
			screen_compat_invalid("unsetenv requires NAME");
		screen_compat_cmd_add(&cmd, "set-environment");
		screen_compat_cmd_add(&cmd, "-u");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
		}
		screen_compat_cmd_add(&cmd, argv[0]);
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "chdir") == 0)
		screen_compat_unsupported(
		    "Screen changes a backend-wide default directory for future windows; "
		    "tmux normally chooses a directory at "
		    "new-session/new-window/split-window time.",

		    "Use tmux new-window -c DIR or split-window -c DIR.");
	if (strcmp(name, "escape") == 0)
		screen_compat_unsupported(
		    "Screen 'escape' encodes both command and literal-prefix characters "
		    "as a two-character pair; tmux exposes prefix and prefix2 as "
		    "independent key options.",

		    "Use tmux set-option prefix KEY and, if desired, set-option prefix2 "
		    "KEY.");
	if (strcmp(name, "bind") == 0) {
		if (argc < 2)
			screen_compat_invalid("bind requires key and command");
		if (strcmp(argv[1], "screen") == 0 || strcmp(argv[1], "kill") == 0) {
			screen_compat_cmd_add(&cmd, "bind-key");
			screen_compat_cmd_add(&cmd, argv[0]);
			screen_compat_cmd_add(&cmd, strcmp(argv[1], "screen") == 0 ?
			    "new-window" : "kill-window");
			xasprintf(&text,
			    "Executing the closest substitute with that broader scope: tmux "
			    "bind-key %s %s.",

			    argv[0], strcmp(argv[1], "screen") == 0 ? "new-window" : "kill-window");
			screen_compat_approx_exec(sc,
			    "Screen key bindings belong to one Screen backend/session; tmux key "
			    "tables are server-wide, so bind-key can affect unrelated tmux "
			    "sessions.",

			    text, &cmd);
		}
		xasprintf(&text,
		    "Screen bind command '%s' is valid but command-name/argument "
		    "translation is not automatically safe.",
		    argv[1]);
		screen_compat_unsupported(text,
		    "Bind the corresponding tmux command explicitly with tmux bind-key "
		    "after reviewing server-wide scope.");
	}
	if (strcmp(name, "unbindall") == 0) {
		screen_compat_cmd_add(&cmd, "unbind-key");
		screen_compat_cmd_add(&cmd, "-a");
		screen_compat_approx_exec(sc,
		    "Screen unbindall affects only the current Screen backend/session, "
		    "while tmux unbind-key -a removes bindings from the server-wide key "
		    "table.",

		    "Executing tmux unbind-key -a with that broader scope.", &cmd);
	}
	if (strcmp(name, "truecolor") == 0) {
		if (argc == 0)
			screen_compat_invalid("truecolor expects on/off");
		if (strcmp(argv[0], "on") == 0)
			screen_compat_approx(
			    "Screen truecolor toggles Screen's handling, while tmux "
			    "terminal-features is server/terminal-capability configuration.",

			    "If detection is wrong, use tmux set-option -as terminal-features "
			    "',TERM:RGB' for the actual terminal type rather than '*'.");
		if (strcmp(argv[0], "off") == 0)
			screen_compat_unsupported(
			    "Removing RGB from tmux terminal feature detection globally is not a "
			    "safe equivalent of Screen truecolor off.",

			    "Override terminal-features/terminal-overrides for the specific "
			    "client terminal if required.");
		screen_compat_invalid("truecolor expects on/off");
	}
	if (strcmp(name, "altscreen") == 0) {
		if (argc == 0 || (strcmp(argv[0], "on") != 0 && strcmp(argv[0], "off") != 0))
			screen_compat_invalid("altscreen expects on/off");
		screen_compat_cmd_add(&cmd, "set-option");
		screen_compat_cmd_add(&cmd, "-w");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
			xasprintf(&text,
			    "Executing the closest selected-window substitute: tmux set-option "
			    "-w -t %s alternate-screen %s.",
			    target, argv[0]);
		} else
			xasprintf(&text,
			    "Executing the closest current-window substitute: tmux set-option -w "
			    "alternate-screen %s.",
			    argv[0]);
		screen_compat_cmd_add(&cmd, "alternate-screen");
		screen_compat_cmd_add(&cmd, argv[0]);
		screen_compat_approx_exec(sc,
		    target != NULL ?
		    "Screen altscreen changes one backend-wide use_altscreen switch; tmux "
		    "alternate-screen is a window option, so this affects only the "
		    "selected/current tmux window rather than all Screen windows." :
		    "Screen altscreen changes one backend-wide use_altscreen switch; tmux "
		    "alternate-screen is a window option, so this affects only the "
		    "current tmux window rather than all Screen windows.",

		    text, &cmd);
	}
	if (strcmp(name, "reset") == 0) {
		screen_compat_cmd_add(&cmd, "send-keys");
		screen_compat_cmd_add(&cmd, "-R");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_finish(sc, &cmd);
		return;
	}
	if (strcmp(name, "encoding") == 0 || strcmp(name, "kanji") == 0 ||
	    strcmp(name, "charset") == 0 || strcmp(name, "gr") == 0 ||
	    strcmp(name, "c1") == 0) {
		quoted = screen_compat_quote(name);
		xasprintf(&text,
		    "Screen provides legacy encoding/ISO-2022 translation ('%s'); tmux "
		    "intentionally uses a modern UTF-8-oriented terminal model.",
		    quoted);
		screen_compat_unsupported(text,
		    "Use UTF-8 applications, or an external transcoder such as luit/iconv "
		    "when legacy encodings are unavoidable.");
	}
	if (strcmp(name, "hardstatus") == 0) {
		value = argc > 0 ? argv[0] : "";
		if (strcmp(value, "on") == 0 || strcmp(value, "off") == 0) {
			screen_compat_cmd_add(&cmd, "set-option");
			if (sc->session != NULL && *sc->session != '\0') {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, sc->session);
				xasprintf(&text,
				    "Executing the closest substitute: tmux set-option -t %s status %s.",
				    sc->session, value);
			} else
				xasprintf(&text,
				    "Executing the closest substitute: tmux set-option status %s.",
				    value);
			screen_compat_cmd_add(&cmd, "status");
			screen_compat_cmd_add(&cmd, value);
			screen_compat_approx_exec(sc,
			    "Screen hardstatus and tmux status lines overlap in purpose but are "
			    "not the same terminal facility.",
			    text, &cmd);
		}
		if (strcmp(value, "alwayslastline") == 0 ||
		    strcmp(value, "lastline") == 0 ||
		    strcmp(value, "alwaysfirstline") == 0 ||
		    strcmp(value, "firstline") == 0) {
			const char *position = (strstr(value, "first") != NULL) ? "top" : "bottom";
			screen_compat_cmd_add(&cmd, "set-option");
			if (sc->session != NULL && *sc->session != '\0') {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, sc->session);
				xasprintf(&text,
				    "Executing the closest substitute: tmux set-option -t %s "
				    "status-position %s.",
				    sc->session, position);
			} else
				xasprintf(&text,
				    "Executing the closest substitute: tmux set-option status-position "
				    "%s.",
				    position);
			screen_compat_cmd_add(&cmd, "status-position");
			screen_compat_cmd_add(&cmd, position);
			screen_compat_approx_exec(sc,
			    "Screen hardstatus placement maps only approximately to tmux's "
			    "status line.",
			    text, &cmd);
		}
		screen_compat_unsupported(
		    "Screen hardstatus has physical-hardstatus and formatting modes that "
		    "do not map one-to-one.",

		    "Use tmux status, status-position, status-left, status-right and "
		    "status-format options.");
	}
	if (strcmp(name, "caption") == 0) {
		value = argc > 0 ? argv[0] : "";
		if (strcmp(value, "always") == 0) {
			screen_compat_cmd_add(&cmd, "set-option");
			screen_compat_cmd_add(&cmd, "-w");
			if (target != NULL) {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, target);
				xasprintf(&text,
				    "Executing the closest substitute for the selected tmux window: "
				    "tmux set-option -w -t %s pane-border-status bottom.",
				    target);
			} else if (sc->session != NULL && *sc->session != '\0') {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, sc->session);
				xasprintf(&text,
				    "Executing the closest substitute for the session's current window: "
				    "tmux set-option -w -t %s pane-border-status bottom.",
				    sc->session);
			} else
				text = xstrdup(
				    "Executing the closest substitute for the current window: tmux "
				    "set-option -w pane-border-status bottom.");
			screen_compat_cmd_add(&cmd, "pane-border-status");
			screen_compat_cmd_add(&cmd, "bottom");
			screen_compat_approx_exec(sc,
			    "Screen captions label display regions; tmux pane-border-status "
			    "labels pane borders. They are visually similar but attach to "
			    "different objects.",
			    text, &cmd);
		}
		if (strcmp(value, "splitonly") == 0)
			screen_compat_unsupported(
			    "Screen can enable captions only when a display has multiple "
			    "regions; tmux has no identical split-only pane-border-status mode.",

			    "Use pane-border-status plus a format condition, or a hook/script, "
			    "if conditional display is important.");
		screen_compat_unsupported(
		    "Screen caption syntax does not map one-to-one to tmux pane-border "
		    "formatting.",

		    "Use pane-border-status and pane-border-format.");
	}
	if (strcmp(name, "multiuser") == 0)
		screen_compat_unsupported(
		    "Screen toggles an internal multiuser mode; tmux cross-user access is "
		    "controlled by its server socket plus server-access.",

		    "Grant/revoke a specific OS user with tmux server-access and ensure "
		    "socket filesystem permissions allow connection.");
	if (strcmp(name, "acladd") == 0 || strcmp(name, "addacl") == 0) {
		if (argc < 1) {
			xasprintf(&text, "%s requires a user", name);
			screen_compat_invalid(text);
		}
		screen_compat_cmd_add(&cmd, "server-access");
		screen_compat_cmd_add(&cmd, "-a");
		screen_compat_cmd_add(&cmd, argv[0]);
		xasprintf(&text,
		    "Executing the closest substitute with that broader scope: tmux "
		    "server-access -a %s.",
		    argv[0]);
		screen_compat_approx_exec(sc,
		    "Screen ACL access is scoped to one Screen session and can be refined "
		    "per command/window; tmux server-access grants access at the entire "
		    "tmux server level.",
		    text, &cmd);
	}
	if (strcmp(name, "acldel") == 0) {
		if (argc < 1)
			screen_compat_invalid("acldel requires a user");
		screen_compat_cmd_add(&cmd, "server-access");
		screen_compat_cmd_add(&cmd, "-d");
		screen_compat_cmd_add(&cmd, argv[0]);
		xasprintf(&text,
		    "Executing the closest substitute with that broader scope: tmux "
		    "server-access -d %s.",
		    argv[0]);
		screen_compat_approx_exec(sc,
		    "Screen acldel removes a user from one Screen session; tmux "
		    "server-access revokes access to the entire tmux server.",
		    text, &cmd);
	}
	if (strcmp(name, "aclchg") == 0 || strcmp(name, "chacl") == 0 ||
	    strcmp(name, "aclgrp") == 0 || strcmp(name, "aclumask") == 0 ||
	    strcmp(name, "umask") == 0 || strcmp(name, "writelock") == 0 ||
	    strcmp(name, "auth") == 0 || strcmp(name, "su") == 0) {
		xasprintf(&text,
		    "Screen's ACL/authentication operation '%s' has finer or different "
		    "semantics than tmux server-access/read-only clients.",
		    name);
		screen_compat_unsupported(text,
		    "Use tmux server-access, Unix socket permissions, and read-only "
		    "clients where appropriate; there is no exact per-command/per-window "
		    "Screen ACL equivalent.");
	}
	if (strcmp(name, "break") == 0 || strcmp(name, "breaktype") == 0 ||
	    strcmp(name, "pow_break") == 0 || strcmp(name, "flow") == 0 ||
	    strcmp(name, "console") == 0) {
		xasprintf(&text,
		    "Screen includes direct serial/device functionality for '%s'; tmux "
		    "panes always contain PTYs and tmux has no built-in serial-device "
		    "control layer.",
		    name);
		screen_compat_external(text,
		    "Run picocom, cu, minicom, tio, or another serial application inside "
		    "a tmux pane and use that program's serial controls.");
	}
	if (strcmp(name, "zmodem") == 0)
		screen_compat_unsupported(
		    "Screen has built-in ZMODEM interception/pass-through policy; tmux "
		    "does not.",

		    "Run rz/sz or terminal/file-transfer tooling externally and leave "
		    "tmux as the PTY multiplexer.");
	if (strcmp(name, "displays") == 0) {
		if (sc->session == NULL || *sc->session == '\0')
			screen_compat_approx(
			    "Screen displays lists Displays attached to its one Screen backend; "
			    "a tmux server may contain clients for many sessions.",

			    "Choose a tmux session explicitly, then use tmux list-clients -t "
			    "SESSION.");
		screen_compat_cmd_add(&cmd, "list-clients");
		screen_compat_cmd_add(&cmd, "-t");
		screen_compat_cmd_add(&cmd, sc->session);
		xasprintf(&text,
		    "Executing the closest substitute: tmux list-clients -t %s",
		    sc->session);
		screen_compat_approx_exec(sc,
		    "Screen displays lists Displays attached to one Screen session; tmux "
		    "list-clients can be scoped to that session but uses different output "
		    "fields and formatting.",
		    text, &cmd);
	}
	if (strcmp(name, "dinfo") == 0) {
		screen_compat_cmd_add(&cmd, "list-clients");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
		}
		screen_compat_cmd_add(&cmd, "-F");
		screen_compat_cmd_add(&cmd,
		    "#{client_name} #{client_tty} #{client_width}x#{client_height} "
		    "#{client_termname}");
		if (sc->session != NULL && *sc->session != '\0')
			xasprintf(&text,
			    "Executing a useful client summary for every client on the selected "
			    "session: tmux list-clients -t %s -F '#{client_name} #{client_tty} "
			    "#{client_width}x#{client_height} #{client_termname}'.",
			    sc->session);
		else
			text = xstrdup(
			    "Executing a useful tmux client summary: tmux list-clients -F "
			    "'#{client_name} #{client_tty} #{client_width}x#{client_height} "
			    "#{client_termname}'.");
		screen_compat_approx_exec(sc,
		    sc->session != NULL && *sc->session != '\0' ?
		    "Screen dinfo reports one particular Screen Display; a tmux session "
		    "may have multiple clients with different terminal/display state." :
		    "Screen dinfo reports one particular Screen Display; tmux may have "
		    "multiple clients with different terminal/display state.",

		    text, &cmd);
	}
	if (strcmp(name, "windows") == 0) {
		screen_compat_cmd_add(&cmd, "list-windows");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, sc->session);
			xasprintf(&text,
			    "Executing the closest substitute: tmux list-windows -t %s.",
			    sc->session);
		} else
			text = xstrdup("Executing the closest substitute: tmux list-windows.");
		screen_compat_approx_exec(sc,
		    "Screen windows uses Screen-specific formatting/flags; tmux "
		    "list-windows is functionally similar but not output-compatible.",
		    text, &cmd);
	}
	if (strcmp(name, "help") == 0) {
		screen_compat_cmd_add(&cmd, "list-keys");
		screen_compat_approx_exec(sc,
		    "Screen help renders Screen's current command-class bindings; tmux "
		    "list-keys renders tmux's server-wide key tables with different "
		    "command names and formatting.",

		    "Executing the closest substitute: tmux list-keys.", &cmd);
	}
	if (strcmp(name, "info") == 0) {
		screen_compat_cmd_add(&cmd, "display-message");
		screen_compat_cmd_add(&cmd, "-p");
		if (target != NULL) {
			screen_compat_cmd_add(&cmd, "-t");
			screen_compat_cmd_add(&cmd, target);
		}
		screen_compat_cmd_add(&cmd,
		    "#{session_name}:#{window_index}.#{pane_index} "
		    "#{pane_width}x#{pane_height} #{pane_current_command}");
		screen_compat_approx_exec(sc,
		    "Screen info emits a Screen-specific window/display status summary; "
		    "tmux has no byte-compatible equivalent.",

		    "Executing a useful tmux status summary with explicit format "
		    "variables.",
		    &cmd);
	}
	if (strcmp(name, "lastmsg") == 0) {
		screen_compat_cmd_add(&cmd, "show-messages");
		screen_compat_approx_exec(sc,
		    "Screen lastmsg reports one Screen message; tmux show-messages "
		    "reports a differently formatted message history.",

		    "Executing tmux show-messages; select the desired entry explicitly if "
		    "exact single-message behavior matters.",
		    &cmd);
	}
	if (strcmp(name, "version") == 0)
		screen_compat_unsupported(
		    "Screen's internal version command reports Screen's version/status "
		    "text; tmux -V reports tmux and is not an equivalent command result.",

		    "Use the native Screen command when Screen version output is "
		    "required, or tmux -V explicitly for tmux's version.");
	if (strcmp(name, "license") == 0)
		screen_compat_unsupported(
		    "Screen has an interactive license command; tmux does not expose its "
		    "license text as a runtime command.",

		    "Read tmux's COPYING file from the source/package.");
	if (strcmp(name, "layout") == 0) {
		value = argc > 0 ? argv[0] : "";
		if (strcmp(value, "next") == 0 || strcmp(value, "prev") == 0) {
			screen_compat_cmd_add(&cmd,
			    strcmp(value, "next") == 0 ? "next-layout" : "previous-layout");
			screen_compat_approx_exec(sc,
			    strcmp(value, "next") == 0 ?
			    "Screen 'layout next' switches among saved display-region layouts; "
			    "tmux next-layout cycles pane-layout algorithms/history, not Screen "
			    "layout objects." :
			    "Screen 'layout prev' switches among saved display-region layouts; "
			    "tmux previous-layout operates on pane layouts.",

			    strcmp(value, "next") == 0 ?
			    "Executing the closest visual substitute: tmux next-layout." :
			    "Executing the closest visual substitute: tmux previous-layout.", &cmd);
		}
		if (strcmp(value, "show") == 0) {
			screen_compat_cmd_add(&cmd, "display-message");
			screen_compat_cmd_add(&cmd, "-p");
			if (target != NULL) {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, target);
				xasprintf(&text,
				    "Executing the closest inspection command: tmux display-message -p "
				    "-t %s '#{window_layout}'.",
				    target);
			} else
				text = xstrdup(
				    "Executing the closest inspection command: tmux display-message -p "
				    "'#{window_layout}'.");
			screen_compat_cmd_add(&cmd, "#{window_layout}");
			screen_compat_approx_exec(sc,
			    "Screen 'layout show' reports the selected saved Screen layout; tmux "
			    "exposes current pane geometry as an encoded layout string.",
			    text, &cmd);
		}
		if (strcmp(value, "select") == 0) {
			if (argc < 2)
				screen_compat_invalid("layout select requires a layout");
			screen_compat_cmd_add(&cmd, "select-layout");
			if (target != NULL) {
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, target);
				xasprintf(&text,
				    "Executing tmux select-layout -t %s '%s'; this works only when the "
				    "Screen layout argument is meaningful to tmux.",
				    target, argv[1]);
			} else
				xasprintf(&text,
				    "Executing tmux select-layout '%s'; this works only when the Screen "
				    "layout argument is meaningful to tmux.",
				    argv[1]);
			screen_compat_cmd_add(&cmd, argv[1]);
			screen_compat_approx_exec(sc,
			    "Screen selects a saved named/numbered display layout; tmux "
			    "select-layout selects a pane layout name or encoded geometry.",
			    text, &cmd);
		}
		screen_compat_unsupported(
		    "Screen has persistent named/numbered layout objects; tmux has "
		    "current/encoded pane layouts but not the same saved-layout "
		    "collection.",

		    "Use #{window_layout} to capture an encoded tmux layout and "
		    "select-layout to restore it, or store names in user options/scripts.");
	}

	if (screen_compat_known_internal(name)) {
		xasprintf(&text,
		    "Screen command '%s' is valid/recognized but has no safe automatic "
		    "mapping implemented in screen-to-tmux-translator %s.",

		    name, SCREEN_COMPAT_VERSION);
		screen_compat_unsupported(text,
		    "Use 'tmux list-commands' and the project cross-reference to select "
		    "the closest tmux operation.");
	}
	xasprintf(&text, "unknown Screen command '%s'", name);
	screen_compat_invalid(text);
}

static void
screen_compat_parse(struct screen_compat *sc)
{
	struct screen_compat_cmd	 cmd;
	char			*text, *text2, *session_tmux;
	char			*title_tmux, *filter, *helper_argv[5];
	const char		*arg, *opt, *rest, *tmux, *unique;
	const char		*host, *port, *dev, *baud;
	int			 i, remaining, new_detached;

	while (sc->pos < sc->argc) {
		arg = sc->argv[sc->pos];
		if (strcmp(arg, "--") == 0) {
			sc->pos++;
			break;
		}
		if (strcmp(arg, "--help") == 0) {
			screen_compat_help();
			exit(0);
		}
		if (strcmp(arg, "--version") == 0)
			screen_compat_unsupported(
			    "Screen --version reports the GNU Screen version; tmux -V reports a "
			    "different program and cannot preserve that result.",

			    "Run the native Screen binary for Screen's version, or tmux -V "
			    "explicitly for tmux's version.");
		if (strcmp(arg, "-list") == 0 || strcmp(arg, "-ls") == 0 ||
		    strcmp(arg, "-wipe") == 0) {
			sc->list = 1;
			if (strcmp(arg, "-wipe") == 0)
				sc->wipe = 1;
			sc->pos++;
			if (sc->pos < sc->argc && sc->argv[sc->pos][0] != '-')
				sc->session = sc->argv[sc->pos++];
			continue;
		}
		if (strcmp(arg, "-Logfile") == 0) {
			sc->pos++;
			if (sc->pos >= sc->argc)
				screen_compat_invalid("-Logfile requires a filename");
			sc->logfile = sc->argv[sc->pos++];
			continue;
		}
		if (arg[0] == '-' && arg[1] != '\0') {
			opt = arg + 1;
			sc->pos++;
			while (*opt != '\0') {
				rest = opt + 1;
				switch (*opt) {
				case '4':
				case '6':
					sc->af = *opt - '0';
					opt = rest;
					break;
				case 'a':
					free(sc->unsupported_opt);
					sc->unsupported_opt = xstrdup(
					    "Screen -a capability-forcing has no exact tmux CLI equivalent");
					opt = rest;
					break;
				case 'A':
					sc->Aflag = 1;
					opt = rest;
					break;
				case 'p':
					if (*rest != '\0') {
						sc->window = rest;
						opt = rest + strlen(rest);
					} else {
						if (sc->pos >= sc->argc)
							screen_compat_invalid("-p requires a window");
						sc->window = sc->argv[sc->pos++];
						opt = rest;
					}
					break;
				case 'P':
					free(sc->unsupported_opt);
					sc->unsupported_opt = xstrdup(
					    "Screen -P enables Screen-managed authentication; tmux uses Unix "
					    "socket permissions/server-access");
					opt = rest;
					break;
				case 'c':
					if (*rest != '\0') {
						sc->screenrc = rest;
						opt = rest + strlen(rest);
					} else {
						if (sc->pos >= sc->argc)
							screen_compat_invalid("-c requires a file");
						sc->screenrc = sc->argv[sc->pos++];
						opt = rest;
					}
					break;
				case 'e':
					if (*rest != '\0') {
						sc->escape = rest;
						opt = rest + strlen(rest);
					} else {
						if (sc->pos >= sc->argc)
							screen_compat_invalid("-e requires two command characters");
						sc->escape = sc->argv[sc->pos++];
						opt = rest;
					}
					break;
				case 'f':
					if (*rest == '\0' || strcmp(rest, "n") == 0 ||
					    strcmp(rest, "a") == 0 || strcmp(rest, "0") == 0 ||
					    strcmp(rest, "1") == 0 || strcmp(rest, "y") == 0) {
						free(sc->unsupported_opt);
						xasprintf(&sc->unsupported_opt,
						    "Screen flow-control option -f%s has no direct tmux equivalent",
						    rest);
						opt = rest + strlen(rest);
					} else {
						xasprintf(&text, "unknown Screen flow option -f%s", rest);
						screen_compat_invalid(text);
					}
					break;
				case 'h':
					if (*rest != '\0')
						screen_compat_invalid("-h requires its argument as the next word");
					if (sc->pos >= sc->argc)
						screen_compat_invalid("-h requires a history size");
					sc->hist = sc->argv[sc->pos++];
					opt = rest;
					break;
				case 'i':
					free(sc->unsupported_opt);
					sc->unsupported_opt = xstrdup(
					    "Screen -i changes XON/XOFF interrupt behavior; tmux has no "
					    "equivalent multiplexer policy");
					opt = rest;
					break;
				case 't':
					if (*rest != '\0')
						screen_compat_invalid("-t requires its argument as the next word");
					if (sc->pos >= sc->argc)
						screen_compat_invalid("-t requires a title");
					sc->title = sc->argv[sc->pos++];
					opt = rest;
					break;
				case 'l':
					if (strcmp(rest, "s") == 0 || strcmp(rest, "ist") == 0) {
						sc->list = 1;
						opt = rest + strlen(rest);
					} else if (*rest == '\0' || strcmp(rest, "n") == 0 ||
					    strcmp(rest, "0") == 0 || strcmp(rest, "y") == 0 ||
					    strcmp(rest, "1") == 0 || strcmp(rest, "a") == 0) {
						free(sc->unsupported_opt);
						sc->unsupported_opt = xstrdup(
						    "Screen login/utmp mode has no tmux pane equivalent");
						opt = rest + strlen(rest);
					} else {
						xasprintf(&text, "unknown Screen -l suboption '%s'", rest);
						screen_compat_invalid(text);
					}
					break;
				case 'L':
					if (strcmp(rest, "ogfile") == 0) {
						if (sc->pos >= sc->argc)
							screen_compat_invalid("-Logfile requires a filename");
						sc->logfile = sc->argv[sc->pos++];
						opt = rest + strlen(rest);
					} else if (*rest == '\0') {
						sc->log = 1;
						opt = rest;
					} else {
						xasprintf(&text, "unknown Screen -L option '-L%s'", rest);
						screen_compat_invalid(text);
					}
					break;
				case 'm':
					sc->mflag = 1;
					opt = rest;
					break;
				case 'O':
					free(sc->unsupported_opt);
					sc->unsupported_opt = xstrdup(
					    "Screen -O is a legacy VT100 output-compatibility mode; tmux uses "
					    "terminfo/terminal-features instead");
					opt = rest;
					break;
				case 'T':
					if (*rest != '\0')
						screen_compat_invalid("-T requires its argument as the next word");
					if (sc->pos >= sc->argc)
						screen_compat_invalid("-T requires TERM");
					sc->term = sc->argv[sc->pos++];
					opt = rest;
					break;
				case 'q':
					sc->quiet = 1;
					opt = rest;
					break;
				case 'Q':
					sc->mode = 'Q';
					opt = rest;
					break;
				case 'r':
					sc->attach = 1;
					sc->attach_strength++;
					opt = rest;
					break;
				case 'R':
					sc->attach = 1;
					if (sc->attach_strength > 0)
						sc->attach_strength = 2;
					sc->attach_strength += 2;
					opt = rest;
					break;
				case 'x':
					sc->attach = 1;
					sc->xflag = 1;
					opt = rest;
					break;
				case 'd':
					sc->detach = 1;
					opt = rest;
					break;
				case 'D':
					sc->detach = 2;
					opt = rest;
					break;
				case 's':
					if (*rest != '\0')
						screen_compat_invalid("-s requires its argument as the next word");
					if (sc->pos >= sc->argc)
						screen_compat_invalid("-s requires a shell");
					sc->shell = sc->argv[sc->pos++];
					opt = rest;
					break;
				case 'S':
					if (*rest != '\0')
						screen_compat_invalid("-S requires its argument as the next word");
					if (sc->pos >= sc->argc)
						screen_compat_invalid("-S requires a session name");
					sc->session = sc->argv[sc->pos++];
					opt = rest;
					break;
				case 'X':
					sc->mode = 'X';
					opt = rest;
					break;
				case 'v':
					screen_compat_unsupported(
					    "Screen -v reports the GNU Screen version; tmux -V reports a "
					    "different program and cannot preserve that result.",

					    "Run the native Screen binary for Screen's version, or tmux -V "
					    "explicitly for tmux's version.");
				case 'U':
					sc->Uflag = 1;
					opt = rest;
					break;
				case 'w':
					if (strcmp(rest, "ipe") == 0) {
						sc->list = 1;
						sc->wipe = 1;
						opt = rest + strlen(rest);
					} else {
						xasprintf(&text, "unknown Screen option '-w%s'", rest);
						screen_compat_invalid(text);
					}
					break;
				default:
					xasprintf(&text, "unknown Screen option '-%c'", *opt);
					screen_compat_invalid(text);
				}
			}
			continue;
		}

		remaining = sc->argc - sc->pos;
		if ((sc->session == NULL || *sc->session == '\0') &&
		    (sc->attach || (sc->detach > 0 && !sc->mflag && remaining == 1))) {
			sc->session = sc->argv[sc->pos++];
			continue;
		}
		break;
	}

	if (sc->unsupported_opt != NULL) {
		xasprintf(&text, "%s.", sc->unsupported_opt);
		screen_compat_unsupported(text,
		    "Configure the corresponding tmux terminal/access behavior "
		    "explicitly; the base Screen operation was not executed.");
	}
	if (sc->screenrc != NULL && *sc->screenrc != '\0') {
		xasprintf(&text,
		    "Translate '%s' to tmux.conf syntax first. Do not pass a screenrc "
		    "directly to tmux -f.",
		    sc->screenrc);
		screen_compat_unsupported(
		    "Screen -c reads Screen configuration syntax; tmux -f reads a "
		    "different command language, so passing the same file to tmux is "
		    "unsafe.",
		    text);
	}
	arg = getenv("SCREENDIR");
	if (arg != NULL && *arg != '\0')
		screen_compat_unsupported(
		    "SCREENDIR selects a directory containing Screen per-session sockets; "
		    "tmux instead selects one server socket with -L name or -S path.",

		    "Choose an explicit tmux server, for example: tmux -L myserver ... or "
		    "tmux -S /path/to/socket ...");

	remaining = sc->argc - sc->pos;
	if (sc->mode == 'X') {
		screen_compat_xcommand(sc, remaining, sc->argv + sc->pos);
		return;
	}
	if (sc->mode == 'Q') {
		screen_compat_query(sc, remaining, sc->argv + sc->pos);
		return;
	}

	if (sc->wipe)
		screen_compat_moot(
		    "Screen -wipe cleans stale per-session socket records; tmux sessions "
		    "are in-memory objects owned by one server and do not leave one stale "
		    "socket per session.",

		    "Use tmux list-sessions. Only clean up the tmux server socket itself "
		    "if that server is actually dead.");
	if (sc->list) {
		screen_compat_cmd_init(&cmd);
		if (sc->quiet) {
			if (sc->session != NULL && *sc->session != '\0') {
				if (screen_compat_session_selector_risky(sc->session))
					screen_compat_approx(
					    "Screen -q -ls matching uses Screen socket-name matching and "
					    "special socket-count exit statuses; safely interpreting this "
					    "selector as a tmux target is ambiguous.",

					    "Choose an explicit tmux session target and use tmux has-session "
					    "-t TARGET when a boolean existence test is sufficient.");
				screen_compat_cmd_add(&cmd, "has-session");
				screen_compat_cmd_add(&cmd, "-t");
				screen_compat_cmd_add(&cmd, sc->session);
				xasprintf(&text,
				    "Executing the closest quiet existence check: tmux has-session -t "
				    "%s.",
				    sc->session);
				screen_compat_approx_exec(sc,
				    "Screen -q -ls suppresses output and returns Screen-specific "
				    "socket-count status codes; tmux has-session is only a boolean "
				    "exact-name existence test.",

				    text, &cmd);
			}
			screen_compat_cmd_add(&cmd, "has-session");
			screen_compat_approx_exec(sc,
			    "Screen -q -ls suppresses output and returns Screen-specific "
			    "socket-count status codes; tmux has-session is only a boolean test "
			    "for a resolvable tmux session.",

			    "Executing the closest quiet existence check: tmux has-session.", &cmd);
		}
		if (sc->session != NULL && *sc->session != '\0') {
			if (screen_compat_session_selector_risky(sc->session))
				screen_compat_approx(
				    "Screen -ls/-list matching uses Screen socket-name matching, while "
				    "safely embedding this selector in a tmux format filter is "
				    "ambiguous.",

				    "Choose a simple literal tmux session-name substring and run tmux "
				    "list-sessions -f with an explicit filter.");
			xasprintf(&filter, "#{m:*%s*,#{session_name}}", sc->session);
			screen_compat_cmd_add(&cmd, "list-sessions");
			screen_compat_cmd_add(&cmd, "-f");
			screen_compat_cmd_add(&cmd, filter);
			xasprintf(&text,
			    "Executing the closest substitute: tmux list-sessions -f '%s'.",
			    filter);
			screen_compat_approx_exec(sc,
			    "Screen -ls/-list reports Screen socket names, attached/detached "
			    "state, dead sockets and socket-directory information; tmux "
			    "list-sessions uses a different session model and output format.",
			    text, &cmd);
		}
		screen_compat_cmd_add(&cmd, "list-sessions");
		screen_compat_approx_exec(sc,
		    "Screen -ls/-list reports Screen socket names, attached/detached "
		    "state, dead sockets and socket-directory information; tmux "
		    "list-sessions uses a different session model and output format.",

		    "Executing the closest substitute: tmux list-sessions.", &cmd);
	}

	if ((sc->attach || (sc->detach > 0 && !sc->mflag)) &&
	    sc->session != NULL && *sc->session != '\0')
		screen_compat_guard_targets(sc);

	if (sc->detach > 0 && !sc->attach && !sc->mflag) {
		screen_compat_cmd_init(&cmd);
		screen_compat_cmd_add(&cmd, "detach-client");
		if (sc->detach == 2)
			screen_compat_cmd_add(&cmd, "-P");
		if (sc->session != NULL && *sc->session != '\0') {
			screen_compat_cmd_add(&cmd, "-s");
			screen_compat_cmd_add(&cmd, sc->session);
		}
		screen_compat_finish(sc, &cmd);
		return;
	}

	if (sc->attach) {
		char *attach_target = NULL;
		if (sc->Aflag)
			screen_compat_approx_notice(sc,
			    "Screen -A explicitly adapts all Screen window sizes to the current "
			    "terminal when attaching; tmux uses its own client/window-size "
			    "policy and has no equivalent adapt-all-windows flag.",

			    "Proceeding with tmux's normal window-size policy; configure "
			    "window-size explicitly if Screen's adapt-all-windows behavior "
			    "matters.");
		if (sc->Uflag)
			screen_compat_approx_notice(sc,
			    "Screen -U tells the attached Screen display to use UTF-8 and also "
			    "changes the default encoding for newly created Screen windows; tmux "
			    "-u only forces the client UTF-8 assumption.",

			    "Proceeding with tmux -u for the client-side UTF-8 portion; Screen's "
			    "per-window encoding policy is not reproduced.");
		if (sc->session != NULL && *sc->session != '\0')
			attach_target = xstrdup(sc->session);
		if (sc->window != NULL && *sc->window != '\0') {
			if (sc->session == NULL || *sc->session == '\0') {
				xasprintf(&text,
				    "Choose the session explicitly, then use tmux attach-session -t "
				    "session:%s.",
				    sc->window);
				screen_compat_approx(
				    "Screen can combine -p with an automatically selected session; tmux "
				    "needs a determinate session when selecting a window at attach "
				    "time.",
				    text);
			}
			xasprintf(&attach_target, "%s:%s", sc->session, sc->window);
		}
		if (sc->attach_strength >= 2) {
			const char *kind = sc->attach_strength >= 4 ? "-RR" : "-R";
			if (sc->session == NULL || *sc->session == '\0')
				screen_compat_unsupported(
				    "Screen -R/-RR can automatically select among detached Screen "
				    "sockets and create a new session if no suitable socket exists; "
				    "tmux has no one-command equivalent with the same selection rules.",

				    "Choose a tmux session explicitly, or implement the Screen "
				    "detached-session selection policy in a wrapper before calling "
				    "tmux.");
			if (sc->window != NULL && *sc->window != '\0') {
				if (sc->detach == 2)
					xasprintf(&text, "tmux new-session -A -D -X -s %s", sc->session);
				else if (sc->detach == 1)
					xasprintf(&text, "tmux new-session -A -D -s %s", sc->session);
				else
					xasprintf(&text, "tmux new-session -A -s %s", sc->session);
				xasprintf(&text2,
				    "Screen %s only considers sockets suitable under Screen's "
				    "attached/detached rules and may create a new session; tmux "
				    "new-session -A has different state and multiple-match rules, and "
				    "preserving -p also needs a second operation.",
				    kind);
				{
					char *suggestion;
					xasprintf(&suggestion,
					    "Closest common-case substitute: %s, then select %s if it exists.",
					    text, attach_target);
					screen_compat_approx(text2, suggestion);
				}
			}
			xasprintf(&text,
			    "Screen %s only considers sockets suitable under Screen's "
			    "attached/detached rules and may create a new session; tmux "
			    "new-session -A will attach an existing named tmux session even when "
			    "Screen would reject it as already attached. Screen -RR also has "
			    "different multiple-match selection behavior.",
			    kind);
			screen_compat_approx_notice(sc, text,
			    "Executing the closest common-case tmux new-session -A mapping for "
			    "the explicit session name.");
			screen_compat_cmd_init(&cmd);
			screen_compat_cmd_add(&cmd, "new-session");
			screen_compat_cmd_add(&cmd, "-A");
			if (sc->detach > 0) {
				screen_compat_cmd_add(&cmd, "-D");
				if (sc->detach == 2)
					screen_compat_cmd_add(&cmd, "-X");
			}
			screen_compat_cmd_add(&cmd, "-s");
			screen_compat_cmd_add(&cmd, sc->session);
			screen_compat_finish_u(sc, &cmd);
			return;
		}
		if (attach_target == NULL) {
			screen_compat_approx_notice(sc,
			    "Screen -r without a selector only succeeds when Screen can resolve "
			    "an appropriate session under Screen's own detached-session rules; "
			    "tmux attach-session without -t selects according to tmux's session "
			    "rules.",

			    "Executing the closest substitute: tmux attach-session.");
			screen_compat_cmd_init(&cmd);
			screen_compat_cmd_add(&cmd, "attach-session");
			screen_compat_finish_u(sc, &cmd);
			return;
		}
		if (sc->detach == 0 && !sc->xflag) {
			xasprintf(&text,
			    "Executing the closest substitute: tmux attach-session -t %s. Use "
			    "Screen -x semantics when multiple simultaneous clients are "
			    "intended, or -d -r when detaching an existing attachment first.",
			    attach_target);
			screen_compat_approx_notice(sc,
			    "Screen -r resumes a detached Screen session and normally refuses an "
			    "already attached session; tmux attach-session normally permits an "
			    "additional client.",
			    text);
		}
		screen_compat_cmd_init(&cmd);
		screen_compat_cmd_add(&cmd, "attach-session");
		if (sc->detach == 2) {
			screen_compat_cmd_add(&cmd, "-d");
			screen_compat_cmd_add(&cmd, "-x");
		} else if (sc->detach == 1)
			screen_compat_cmd_add(&cmd, "-d");
		screen_compat_cmd_add(&cmd, "-t");
		screen_compat_cmd_add(&cmd, attach_target);
		screen_compat_finish_u(sc, &cmd);
		return;
	}

	if (sc->detach == 2 && sc->mflag)
		screen_compat_unsupported(
		    "Screen -D -m has process/daemonization semantics that do not "
		    "correspond to creating one tmux session; tmux -D instead keeps the "
		    "tmux server in the foreground.",

		    "For an ordinary detached session use tmux new-session -d; for a "
		    "foreground tmux server use tmux -D.");
	if (sc->Uflag)
		screen_compat_approx_notice(sc,
		    "Screen -U has two semantics: it declares the Screen display UTF-8 "
		    "capable and sets UTF-8 as the default encoding for newly created "
		    "Screen windows. tmux -u does not implement Screen's per-window "
		    "encoding policy.",

		    "Proceeding with tmux -u for the client-side UTF-8 portion; Screen's "
		    "per-window encoding policy is not reproduced.");
	if (sc->hist != NULL && *sc->hist != '\0') {
		xasprintf(&text,
		    "Configure 'set -g history-limit %s' before creating the "
		    "pane/session.",
		    sc->hist);
		screen_compat_unsupported(
		    "Screen -h sets initial-window scrollback during creation; tmux "
		    "history-limit is a creation-time option whose safe scope cannot be "
		    "changed for only this invocation on an existing server.",
		    text);
	}
	if (sc->term != NULL && *sc->term != '\0') {
		xasprintf(&text,
		    "Configure 'set -g default-terminal %s' in tmux.conf for the intended "
		    "tmux server.",
		    sc->term);
		screen_compat_unsupported(
		    "Screen -T sets the virtual TERM for windows at creation; tmux "
		    "default-terminal is a server option and changing it for only this "
		    "invocation is not equivalent.",
		    text);
	}
	if (sc->shell != NULL && *sc->shell != '\0')
		screen_compat_unsupported(
		    "Screen -s changes the default shell for current and future windows "
		    "in that Screen session; a one-shot tmux new-session command would "
		    "only choose an initial process.",

		    "Configure tmux default-shell, or run the desired shell explicitly in "
		    "each new-session/new-window command.");
	if (sc->escape != NULL && *sc->escape != '\0')
		screen_compat_unsupported(
		    "Screen -e sets Screen's command character plus its literal-escape "
		    "character before startup; tmux models prefix/prefix2 and send-prefix "
		    "differently.",

		    "Translate the intended key behavior explicitly with tmux "
		    "prefix/prefix2 and key bindings.");

	remaining = sc->argc - sc->pos;
	if (remaining > 0 && strncmp(sc->argv[sc->pos], "/dev/tty", 8) == 0) {
		dev = sc->argv[sc->pos++];
		remaining--;
		baud = NULL;
		if (remaining > 0) {
			for (i = 0; sc->argv[sc->pos][i] != '\0'; i++) {
				if (sc->argv[sc->pos][i] < '0' || sc->argv[sc->pos][i] > '9')
					screen_compat_external(
					    "Screen accepts native tty/stty option syntax for direct device "
					    "windows; tmux has no built-in serial endpoint.",

					    "Translate those device settings explicitly for picocom, tio, "
					    "minicom, cu, or another serial client.");
			}
			baud = sc->argv[sc->pos++];
			remaining--;
		}
		if (remaining > 0)
			screen_compat_external(
			    "Screen accepts additional native tty/stty options for direct device "
			    "windows; tmux has no built-in serial endpoint.",

			    "Translate those settings to picocom, tio, minicom, or cu options "
			    "explicitly.");
		i = 0;
		helper_argv[i++] = "picocom";
		if (baud != NULL) {
			helper_argv[i++] = "-b";
			helper_argv[i++] = (char *)baud;
		}
		helper_argv[i++] = (char *)dev;
		xasprintf(&text,
		    "Screen can attach its window directly to %s; tmux panes always run a "
		    "process on a PTY, so a serial client is required.",
		    dev);
		screen_compat_external_launch(sc, "picocom", text,
		    "Using picocom as the serial endpoint when installed.", i, helper_argv);
		return;
	}
	if (remaining > 0 && strcmp(sc->argv[sc->pos], "//telnet") == 0) {
		sc->pos++;
		remaining--;
		if (remaining == 0)
			screen_compat_invalid("//telnet requires a host");
		host = sc->argv[sc->pos++];
		remaining--;
		port = remaining > 0 ? sc->argv[sc->pos++] : NULL;
		remaining = sc->argc - sc->pos;
		if (remaining > 0)
			screen_compat_invalid("//telnet accepts host and optional port");
		i = 0;
		helper_argv[i++] = "telnet";
		if (sc->af == 4)
			helper_argv[i++] = "-4";
		else if (sc->af == 6)
			helper_argv[i++] = "-6";
		helper_argv[i++] = (char *)host;
		if (port != NULL)
			helper_argv[i++] = (char *)port;
		screen_compat_external_launch(sc, "telnet",
		    "Screen's //telnet is built in; tmux has no Telnet client but can run "
		    "one as the pane process.",

		    "Using the external telnet client when installed.", i, helper_argv);
		return;
	}

	if (sc->logfile != NULL && *sc->logfile != '\0' && !sc->log)
		screen_compat_unsupported(
		    "Screen -Logfile stores a default logfile name even when logging is "
		    "not yet enabled; tmux pipe-pane has no equivalent persistent "
		    "logfile-name setting.",

		    "Create the tmux session normally, then use pipe-pane with an "
		    "explicit destination whenever logging is enabled.");

	new_detached = sc->detach == 1 && sc->mflag;
	if (sc->log) {
		const char *path = sc->logfile != NULL && *sc->logfile != '\0' ?
		    sc->logfile : "tmux.log";
		xasprintf(&text,
		    "Closest initial-pane substitute: create the session, then run tmux "
		    "pipe-pane -o 'cat >>%s'; add after-new-window/after-split-window "
		    "hooks if automatic logging of future panes is required.",
		    path);
		screen_compat_approx(
		    "Screen -L enables Screen's built-in logging policy; tmux has no "
		    "matching startup logging flag and pipe-pane only covers selected "
		    "panes unless additional hooks are installed.",
		    text);
	}

	tmux = getenv("TMUX");
	if (tmux != NULL && *tmux != '\0' && sc->mflag && !new_detached)
		screen_compat_approx(
		    "Screen -m forces a new attached Screen session even from inside "
		    "Screen, but tmux normally rejects an attached nested new-session "
		    "while TMUX is set.",

		    "If nesting is intentional, explicitly unset TMUX for the new tmux "
		    "invocation; otherwise omit -m to create a window in the current tmux "
		    "session.");

	remaining = sc->argc - sc->pos;
	if (tmux != NULL && *tmux != '\0' && !sc->mflag &&
	    (sc->session == NULL || *sc->session == '\0')) {
		if (new_detached)
			screen_compat_unsupported(
			    "Screen's nested-session rule and -d -m request conflict here: -d -m "
			    "explicitly creates a new detached Screen session rather than a "
			    "window in the current session.",

			    "Use -m only when a new tmux session is intended; otherwise omit -d "
			    "-m to create a tmux window in the current session.");
		screen_compat_cmd_init(&cmd);
		screen_compat_cmd_add(&cmd, "new-window");
		if (sc->title != NULL && *sc->title != '\0') {
			title_tmux = screen_compat_format_literal(sc->title);
			screen_compat_cmd_add(&cmd, "-n");
			screen_compat_cmd_add(&cmd, title_tmux);
		}
		screen_compat_cmd_add_argv(&cmd, remaining, sc->argv + sc->pos);
		screen_compat_finish_u(sc, &cmd);
		return;
	}

	unique = getenv("SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES");
	if (sc->session != NULL && *sc->session != '\0' &&
	    (unique == NULL || strcmp(unique, "1") != 0)) {
		if (new_detached)
			xasprintf(&text, "tmux new-session -d -s %s", sc->session);
		else
			xasprintf(&text, "tmux new-session -s %s", sc->session);
		xasprintf(&text2,
		    "Executing the closest tmux named-session mapping. If your "
		    "environment relies on duplicate Screen labels, tmux cannot reproduce "
		    "that naming model: %s.",
		    text);
		screen_compat_approx_notice(sc,
		    "GNU Screen permits multiple sessions whose socket names share the "
		    "same -S label (for example different PID.name sockets), while tmux "
		    "requires each session name to be unique.",

		    text2);
	}

	session_tmux = sc->session != NULL && *sc->session != '\0' ?
	    screen_compat_format_literal(sc->session) : NULL;
	title_tmux = sc->title != NULL && *sc->title != '\0' ?
	    screen_compat_format_literal(sc->title) : NULL;
	screen_compat_cmd_init(&cmd);
	screen_compat_cmd_add(&cmd, "new-session");
	if (new_detached)
		screen_compat_cmd_add(&cmd, "-d");
	if (session_tmux != NULL) {
		screen_compat_cmd_add(&cmd, "-s");
		screen_compat_cmd_add(&cmd, session_tmux);
	}
	if (title_tmux != NULL) {
		screen_compat_cmd_add(&cmd, "-n");
		screen_compat_cmd_add(&cmd, title_tmux);
	}
	screen_compat_cmd_add_argv(&cmd, remaining, sc->argv + sc->pos);
	screen_compat_finish_u(sc, &cmd);
}

void
screen_compat_translate(int *argcp, char ***argvp)
{
	struct screen_compat	 sc;
	char		       **args, **copy;
	int			 i, argc;

	if (argcp == NULL || argvp == NULL || *argvp == NULL ||
	    *argcp == 0 || !screen_compat_is_screen((*argvp)[0]))
		return;

	memset(&sc, 0, sizeof sc);
	sc.original_argc = *argcp;
	sc.original_argv = *argvp;
	copy = xcalloc((size_t)*argcp + 1, sizeof *copy);
	args = copy;
	argc = 0;
	for (i = 1; i < *argcp; i++) {
		if (strcmp((*argvp)[i], "--dry-run") == 0 ||
		    strcmp((*argvp)[i], "--dryrun") == 0) {
			sc.dry_run = 1;
			continue;
		}
		if (strcmp((*argvp)[i], "--strict") == 0) {
			sc.strict = 1;
			continue;
		}
		args[argc++] = (*argvp)[i];
	}
	if (argc > 0 && strcmp(args[0], "screen") == 0) {
		args++;
		argc--;
	}
	sc.argc = argc;
	sc.argv = args;
	sc.pos = 0;

	screen_compat_parse(&sc);
	free(copy);
	*argcp = sc.original_argc;
	*argvp = sc.original_argv;
}
