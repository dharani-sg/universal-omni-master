#!/bin/sh
# build-monolith.sh — POSIX-compliant bundler. Produces a single self-extracting script.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/omni-master-core"

# Header: self-extracting wrapper
cat > "$OUT" << 'HEADER'
#!/bin/sh
# omni-master-core — Universal Omni-Master detection monolith
# Auto-generated. Do not edit; modify src/ and rebuild.
set -u
OMI_TMP="${TMPDIR:-/tmp}/omni-master-$$"
mkdir -p "$OMI_TMP/src/core" "$OMI_TMP/bin"
trap 'rm -rf "$OMI_TMP"' EXIT INT TERM
HEADER

# Embed each source module as a heredoc extraction block
for mod in \
    src/core/logging.sh \
    src/core/utils.sh \
    src/core/priv.sh \
    src/core/detect.sh \
    src/core/detect_hw.sh \
    src/core/config.sh; do

    [ -f "$ROOT/$mod" ] || { echo "MISSING: $mod" >&2; exit 1; }

    # Use a unique delimiter per file to avoid collisions
    _delim="OMNI_EOF_$(echo "$mod" | sed 's/[\/.]/_/g')"

    printf '\ncat > "$OMI_TMP/%s" << '\''%s'\''\n' "$mod" "$_delim" >> "$OUT"
    cat "$ROOT/$mod" >> "$OUT"
    printf '\n%s\n' "$_delim" >> "$OUT"
done

# Embed the driver script inline (not as a separate file)
cat >> "$OUT" << 'DRIVER'

# Source all modules from the extracted tree
for _m in \
    src/core/logging.sh \
    src/core/utils.sh \
    src/core/priv.sh \
    src/core/detect.sh \
    src/core/detect_hw.sh; do
    . "$OMI_TMP/$_m"
done

# Run detection (same logic as bin/omni-detect)
log_info "omni-master-core: probing system (sysroot='${OMNI_SYSROOT:-/}')"

_distro=$(detect_distro)
_init=$(detect_init)
_libc=$(detect_libc)
_arch=$(detect_arch)
_pkg=$(detect_pkgmgr)
_priv=$(detect_priv)
_boot=$(detect_bootloader)
_seat=$(detect_seat_model)
_cpu_vendor=$(detect_cpu_vendor)
_cpu_model=$(detect_cpu_model)
_cpu_count=$(detect_cpu_count)
_cpu_hybrid=$(detect_cpu_hybrid)
_gpu_count=$(detect_gpu_count)
_gpu_vendors=$(detect_gpu_vendors)
_gpu_hybrid=$(detect_gpu_hybrid)
_storage=$(detect_storage_types)
_power=$(detect_power_source)

log_info "distro=$_distro init=$_init libc=$_libc pkg=$_pkg priv=$_priv"

printf '{\n'
json_kv distro        "$_distro"
json_kv init          "$_init"
json_kv libc          "$_libc"
json_kv arch          "$_arch"
json_kv pkgmgr        "$_pkg"
json_kv priv_helper   "$_priv"
json_kv bootloader    "$_boot"
json_kv seat_model    "$_seat"
json_kv cpu_vendor    "$_cpu_vendor"
json_kv cpu_model     "$_cpu_model"
json_kv cpu_count     "$_cpu_count"
json_kv cpu_hybrid    "$_cpu_hybrid"
json_kv gpu_count     "$_gpu_count"
json_kv gpu_vendors   "$_gpu_vendors"
json_kv gpu_hybrid    "$_gpu_hybrid"
json_kv storage       "$_storage"
json_kv power_source  "$_power" ""
printf '}\n'
DRIVER

chmod +x "$OUT"
_sz=$(wc -c < "$OUT" | tr -d ' ')
echo "Built: $OUT (${_sz} bytes)"
sh -n "$OUT" && echo "Monolith syntax: OK"
