#!/bin/sh
# src/desktop/telemetry.sh — M27.1 desktop telemetry dashboard.
# POSIX, BusyBox ash-safe, no eval.

desktop_telemetry_profile_stats() {
    _distro="$1"
    _profile="$2"
    _log="$3"
    _ok=0
    _fail=0
    _total=0

    case "$_profile" in
        ''|*[!A-Za-z0-9_]*) return 2 ;;
    esac

    if [ -f "$_log" ]; then
        _stats=$(awk -v distro="$_distro" -v profile="$_profile" '
            /"event":"desktop_install_result"/ {
                if (distro != "all" &&
                    $0 !~ "\"distro\":\"" distro "\"") {
                    next
                }

                if ($0 ~ "\"profile\":\"" profile "\"") {
                    total++
                    if ($0 ~ "\"status\":\"success\"") {
                        ok++
                    } else {
                        failed++
                    }
                }
            }

            END {
                print (ok + 0), (failed + 0), (total + 0)
            }
        ' "$_log")

        _ok=${_stats%% *}
        _rest=${_stats#* }
        _fail=${_rest%% *}
        _total=${_rest#* }
    fi

    _score=$(( (_ok + 1) * 100 / (_total + 2) ))

    printf '%s|%s|%s|%s|%s|%s\n' \
        "$_profile" "$_distro" "$_ok" "$_fail" "$_total" "$_score"
}

desktop_telemetry_package_stats() {
    _distro="$1"
    _profile="$2"
    _package="$3"
    _log="$4"
    _co=0
    _total=0

    case "$_profile" in
        ''|*[!A-Za-z0-9_]*) return 2 ;;
    esac

    case "$_package" in
        ''|*[!A-Za-z0-9+_.:@-]*) return 2 ;;
    esac

    if [ -f "$_log" ]; then
        _stats=$(awk \
            -v distro="$_distro" \
            -v profile="$_profile" \
            -v wanted="$_package" '
            /"event":"desktop_install_result"/ {
                if (distro != "all" &&
                    $0 !~ "\"distro\":\"" distro "\"") {
                    next
                }

                if ($0 !~ "\"profile\":\"" profile "\"") {
                    next
                }

                total++

                packages = $0
                sub(/^.*"packages":"/, "", packages)
                sub(/".*$/, "", packages)

                count = split(packages, package_array, /[[:space:]]+/)
                for (i = 1; i <= count; i++) {
                    if (package_array[i] == wanted) {
                        co++
                        break
                    }
                }
            }

            END {
                print (co + 0), (total + 0)
            }
        ' "$_log")

        _co=${_stats%% *}
        _total=${_stats#* }
    fi

    _score=$(( (_co + 1) * 100 / (_total + 2) ))

    printf '%s|%s|%s|%s\n' \
        "$_package" "$_co" "$_total" "$_score"
}

desktop_telemetry_dashboard() {
    _distro="$1"
    _log="$2"
    _format="${3:-table}"

    case "$_format" in
        table|ndjson) : ;;
        *) return 2 ;;
    esac

    if [ "$_format" = "table" ]; then
        printf '%-12s %-12s %4s %4s %5s %5s\n' \
            PROFILE DISTRO OK FAIL TOTAL SCORE
    fi

    desktop_profile_names | while IFS= read -r _profile; do
        [ -n "$_profile" ] || continue

        _stats=$(desktop_telemetry_profile_stats \
            "$_distro" "$_profile" "$_log") || continue

        _stats_profile=${_stats%%|*}
        _stats_rest=${_stats#*|}
        _stats_distro=${_stats_rest%%|*}
        _stats_rest=${_stats_rest#*|}
        _stats_ok=${_stats_rest%%|*}
        _stats_rest=${_stats_rest#*|}
        _stats_fail=${_stats_rest%%|*}
        _stats_rest=${_stats_rest#*|}
        _stats_total=${_stats_rest%%|*}
        _stats_score=${_stats_rest#*|}

        if [ "$_format" = "table" ]; then
            printf '%-12s %-12s %4s %4s %5s %4s%%\n' \
                "$_stats_profile" \
                "$_stats_distro" \
                "$_stats_ok" \
                "$_stats_fail" \
                "$_stats_total" \
                "$_stats_score"
        else
            printf '{"profile":"%s","distro":"%s","success":%s,' \
                "$_stats_profile" "$_stats_distro" "$_stats_ok"
            printf '"failed":%s,"total":%s,"score":%s}\n' \
                "$_stats_fail" "$_stats_total" "$_stats_score"
        fi
    done
}
