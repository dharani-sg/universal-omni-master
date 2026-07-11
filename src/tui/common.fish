#!/usr/bin/env fish
# src/tui/common.fish — centralized TUI rendering, validation, confirmation.
# Honors NO_COLOR, TERM=dumb, column width, and OMNI_SYSROOT guard.

set -g OMNI_TUI_VERSION "0.12.0"

# ── Terminal capability detection ─────────────────────────────────────────────
# D6 fix: detect NO_COLOR and TERM=dumb; strip ANSI when either is set.
function _tui_color_enabled
    if set -q NO_COLOR; return 1; end
    if test "$TERM" = dumb; return 1; end
    if not isatty stdout; return 1; end
    return 0
end

# D7 fix: detect terminal width; use compact rendering below 80 cols.
function _tui_cols
    set -l w (tput cols 2>/dev/null)
    if test -z "$w"; or not string match -qr '^[0-9]+$' -- $w
        echo 80
    else
        echo $w
    end
end

function _tui_is_compact
    test (_tui_cols) -lt 80
end

# ── ANSI color helpers ────────────────────────────────────────────────────────
function _tui_set_color
    if _tui_color_enabled
        set_color $argv
    end
end

function _tui_reset_color
    if _tui_color_enabled
        set_color normal
    end
end

# ── Screen layout helpers ─────────────────────────────────────────────────────
function tui_header
    set -l title $argv[1]
    if _tui_is_compact
        # D7 compact path
        echo "=== $title ==="
        return 0
    end
    set -l w (_tui_cols)
    set -l inner "═══ Universal Omni-Master v$OMNI_TUI_VERSION ═══ $title ═══"
    set -l pad (math $w - (string length -- "╔$inner╗") - 1)
    set -l padding ""
    if test $pad -gt 0
        set padding (string repeat -n $pad " ")
    end
    _tui_set_color -o cyan
    printf '╔%s%s╗\n' $inner $padding
    _tui_reset_color
end

function tui_separator
    if _tui_is_compact
        echo "────────────────────"
    else
        set -l w (_tui_cols)
        printf '%s\n' (string repeat -n (math $w - 2) "─")
    end
end

function tui_print_help
    echo "omni-tui v$OMNI_TUI_VERSION"
    echo
    echo "Usage: omni-tui [subcommand]"
    echo
    echo "Subcommands (non-interactive):"
    echo "  dashboard          Show system status"
    echo "  snapshots          Snapshot management menu"
    echo "  help               Show this message"
    echo
    echo "Options:"
    echo "  --plain            Plain text output (no ANSI); auto-set on non-TTY"
    echo
    echo "Interactive mode: omni-tui  (requires a TTY)"
end

# ── Confirmation engine ───────────────────────────────────────────────────────
# D10 fix (partial): generic multi-step confirmation.
# Usage: tui_confirm "Prompt" EXPECTED_WORD
# Returns 0 if user types exactly EXPECTED_WORD, 1 otherwise.
function tui_confirm
    set -l prompt $argv[1]
    set -l required $argv[2]
    _tui_set_color yellow
    printf '%s\n' $prompt
    _tui_reset_color
    read --prompt-str "Type '$required' to confirm: " -l _ans
    test "$_ans" = "$required"
end

# Two-step confirmation: type a specific ID, then type an action word.
# Usage: tui_confirm_two <id_prompt> <id_value> <action_word>
function tui_confirm_two
    set -l id_prompt $argv[1]
    set -l id_value  $argv[2]
    set -l action    $argv[3]

    read --prompt-str "Type the exact $id_prompt to confirm target [$id_value]: " -l _id
    if test "$_id" != "$id_value"
        _tui_set_color red
        echo "  Mismatch — aborted."
        _tui_reset_color
        return 1
    end

    read --prompt-str "Type '$action' to execute: " -l _act
    if test "$_act" != "$action"
        _tui_set_color red
        echo "  Action word mismatch — aborted."
        _tui_reset_color
        return 1
    end

    return 0
end

# ── Command execution helper ──────────────────────────────────────────────────
# Builds cmd as a Fish list (no eval, no string interpolation injection).
# D1/D2 fix philosophy: all calls use explicit list construction.
function tui_run
    _tui_set_color yellow
    echo "→ $argv"
    _tui_reset_color
    $argv
    set -l _rc $status
    if test $_rc -eq 0
        _tui_set_color green
    else
        _tui_set_color red
    end
    echo "  [rc=$_rc]"
    _tui_reset_color
    return $_rc
end

# ── OMNI_SYSROOT guard at TUI layer (D15 fix) ─────────────────────────────────
# Any mutation-path function must call this first.
# Returns 126 if OMNI_SYSROOT is set (fixture/read-only mode).
function _tui_guard_mutation
    if set -q OMNI_SYSROOT
        _tui_set_color red
        printf 'omni-tui: REFUSING mutation — OMNI_SYSROOT is set (fixture mode).\n' >&2
        _tui_reset_color
        return 126
    end
    return 0
end
