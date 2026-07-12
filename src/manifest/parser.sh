#!/bin/sh
# src/manifest/parser.sh
# Strict INI-style manifest parser for Universal Omni-Master.
# Input:
#   [section]
#   key=value
#
# Output:
#   section.key=value

_manifest_trim() {
    printf '%s\n' "$1" | sed \
        -e 's/^[[:space:]]*//' \
        -e 's/[[:space:]]*$//'
}

_manifest_section_valid() {
    case "$1" in
        packages|services|sysctl) return 0 ;;
        *) return 1 ;;
    esac
}

_manifest_key_valid() {
    _mkv_section=$1
    _mkv_key=$2

    case "$_mkv_key" in
        '') return 1 ;;
    esac

    case "$_mkv_section" in
        packages)
            case "$_mkv_key" in
                *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.+-]*)
                    return 1
                    ;;
            esac
            ;;
        services)
            case "$_mkv_key" in
                *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.@-]*)
                    return 1
                    ;;
            esac
            ;;
        sysctl)
            case "$_mkv_key" in
                *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-]*)
                    return 1
                    ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac

    case "$_mkv_key" in
        .*|*.) return 1 ;;
        *..*) return 1 ;;
    esac

    return 0
}

manifest_parse() {
    _mp_file=${1:-}

    [ -n "$_mp_file" ] || {
        printf 'manifest: manifest_parse: file required\n' >&2
        return 1
    }

    [ -f "$_mp_file" ] || {
        printf 'manifest: file not found: %s\n' "$_mp_file" >&2
        return 1
    }

    _mp_section=
    _mp_lineno=0

    while IFS= read -r _mp_raw || [ -n "$_mp_raw" ]; do
        _mp_lineno=$((_mp_lineno + 1))
        _mp_line=$(_manifest_trim "$_mp_raw")

        case "$_mp_line" in
            ''|'#'*) continue ;;
        esac

        case "$_mp_line" in
            \[*)
                case "$_mp_line" in
                    \[*\])
                        _mp_name=${_mp_line#\[}
                        _mp_name=${_mp_name%]}

                        [ "$_mp_name" = "$(_manifest_trim "$_mp_name")" ] || {
                            printf 'manifest: line %d: malformed section header\n' "$_mp_lineno" >&2
                            return 1
                        }

                        _manifest_section_valid "$_mp_name" || {
                            printf 'manifest: line %d: invalid section name: %s\n' "$_mp_lineno" "$_mp_name" >&2
                            return 1
                        }

                        _mp_section=$_mp_name
                        continue
                        ;;
                    *)
                        printf 'manifest: line %d: malformed section header\n' "$_mp_lineno" >&2
                        return 1
                        ;;
                esac
                ;;
        esac

        [ -n "$_mp_section" ] || {
            printf 'manifest: line %d: key/value before section header\n' "$_mp_lineno" >&2
            return 1
        }

        case "$_mp_line" in
            *=*)
                _mp_key=${_mp_line%%=*}
                _mp_val=${_mp_line#*=}

                _mp_key=$(_manifest_trim "$_mp_key")
                _mp_val=$(_manifest_trim "$_mp_val")

                _manifest_key_valid "$_mp_section" "$_mp_key" || {
                    printf 'manifest: line %d: invalid key name: %s\n' "$_mp_lineno" "$_mp_key" >&2
                    return 1
                }

                printf '%s.%s=%s\n' "$_mp_section" "$_mp_key" "$_mp_val"
                ;;
            *)
                printf 'manifest: line %d: expected key=value\n' "$_mp_lineno" >&2
                return 1
                ;;
        esac
    done < "$_mp_file"
}
