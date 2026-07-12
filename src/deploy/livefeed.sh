#!/bin/sh
# src/deploy/livefeed.sh — M20: Live telemetry feed during deployment.
# Wraps command execution with real-time annotated output.
# Adapts verbosity to TUI_LAYOUT (portrait=summary, landscape=full).

OMNI_LIVEFEED_LOG="${OMNI_LIVEFEED_LOG:-/tmp/omni-livefeed.log}"

# livefeed_exec <phase_label> <command> [args...]
# Runs the command, streams its output with timestamps, and logs to file.
# Returns the command's exit code.
livefeed_exec() {
    _lf_phase="$1"
    shift

    _lf_layout="${TUI_LAYOUT:-landscape}"
    _lf_ts_start=$(date +%s)

    printf '[%s] ── %s ──\n' "$(date +%H:%M:%S)" "$_lf_phase" >&2

    # Create a FIFO for streaming without losing the exit code.
    _lf_fifo="${TMPDIR:-/tmp}/omni-livefeed-fifo.$$"
    rm -f "$_lf_fifo"
    mkfifo "$_lf_fifo" 2>/dev/null || {
        # Fallback if mkfifo is unavailable (some minimal BusyBox configs)
        "$@" 2>&1
        return $?
    }

    # Background reader: annotate and display each line
    (
        _lf_count=0
        while IFS= read -r _lf_line; do
            _lf_count=$((_lf_count + 1))
            _lf_ts=$(date +%H:%M:%S)

            # Always log to file
            printf '[%s] [%s] %s\n' "$_lf_ts" "$_lf_phase" "$_lf_line" \
                >> "$OMNI_LIVEFEED_LOG" 2>/dev/null

            # Display based on layout
            case "$_lf_layout" in
                portrait)
                    # Show every 10th line + lines containing key markers
                    case "$_lf_line" in
                        *error*|*Error*|*ERROR*|*warning*|*Warning*|*WARN*|\
                        *Installing*|*installing*|*Extracting*|*extracting*|\
                        *Configuring*|*configuring*|*done*|*Done*|*DONE*)
                            printf '[%s] %s\n' "$_lf_ts" "$_lf_line" >&2
                            ;;
                        *)
                            if [ $((_lf_count % 10)) -eq 0 ]; then
                                printf '[%s] ... line %d ...\n' "$_lf_ts" "$_lf_count" >&2
                            fi
                            ;;
                    esac
                    ;;
                compact)
                    # Show every 5th line + markers
                    case "$_lf_line" in
                        *error*|*Error*|*ERROR*|*warning*|*done*|*Done*|\
                        *Installing*|*Extracting*|*Configuring*)
                            printf '[%s] %s\n' "$_lf_ts" "$_lf_line" >&2
                            ;;
                        *)
                            if [ $((_lf_count % 5)) -eq 0 ]; then
                                printf '[%s] %s\n' "$_lf_ts" "$_lf_line" >&2
                            fi
                            ;;
                    esac
                    ;;
                *)
                    # landscape: full stream
                    printf '[%s] %s\n' "$_lf_ts" "$_lf_line" >&2
                    ;;
            esac
        done < "$_lf_fifo"
    ) &
    _lf_reader_pid=$!

    # Run the actual command, directing output to the FIFO
    "$@" > "$_lf_fifo" 2>&1
    _lf_rc=$?

    # Wait for reader to finish processing
    wait "$_lf_reader_pid" 2>/dev/null || true
    rm -f "$_lf_fifo"

    _lf_ts_end=$(date +%s)
    _lf_dur=$((_lf_ts_end - _lf_ts_start))
    printf '[%s] ── %s complete (rc=%d, %ds) ──\n' \
        "$(date +%H:%M:%S)" "$_lf_phase" "$_lf_rc" "$_lf_dur" >&2

    return "$_lf_rc"
}

# livefeed_summary — print a one-line summary of the last feed session.
livefeed_summary() {
    [ -f "$OMNI_LIVEFEED_LOG" ] || {
        printf 'livefeed: no log recorded\n'
        return 0
    }
    _lfs_lines=$(wc -l < "$OMNI_LIVEFEED_LOG" | tr -d ' ')
    _lfs_errors=$(grep -ci 'error\|fail' "$OMNI_LIVEFEED_LOG" 2>/dev/null || echo 0)
    printf 'livefeed: %s lines logged, %s errors/failures\n' "$_lfs_lines" "$_lfs_errors"
}

# livefeed_clear — reset the log file.
livefeed_clear() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        return 126
    fi
    : > "$OMNI_LIVEFEED_LOG" 2>/dev/null
}
