#!/bin/bash
# Tüm testleri çalıştırır: Mac uygulaması, Windows uygulaması ve Chrome eklentisi (Tests/README.md).
#
#   scripts/test.sh                 → hepsi
#   scripts/test.sh mac             → yalnızca Mac (swift test)
#   scripts/test.sh windows         → yalnızca Windows'un mantık katmanı (dotnet test; Mac'te de çalışır)
#   scripts/test.sh extension       → yalnızca Chrome eklentisi (node --test)
#   scripts/test.sh mac extension   → birkaçı
#   KD_TEST_FILTER=StoreTests scripts/test.sh mac windows   → yalnızca adında "StoreTests" geçenler
#
# Testler gerçek listeye, ayarlara, indirme klasörüne ve kurulu uygulamanın portuna dokunmaz: her şey geçici bir
# klasörde (KD_TEST_ROOT) olur, iş bitince silinir. Biri başarısız olursa çıkış kodu 1.
# Push öncesi (scripts/hooks/pre-push) ve yayın betikleri (release.sh, release-windows.sh) bunu çalıştırır.
set -uo pipefail
cd "$(dirname "$0")/.."

SUITES=("$@")
[[ ${#SUITES[@]} -gt 0 ]] || SUITES=(mac windows extension)

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kd-tests.XXXXXX")"
export KD_TEST_ROOT="$ROOT"
trap 'rm -rf "$ROOT"' EXIT

FAILED=()
PASSED=()
SKIPPED=()
START=$SECONDS

dotnet_bin() {
    if command -v dotnet >/dev/null; then command -v dotnet
    elif [[ -x "$HOME/.dotnet/dotnet" ]]; then echo "$HOME/.dotnet/dotnet"
    fi
}

run_mac() {
    local args=(--parallel)
    [[ -n "${KD_TEST_FILTER:-}" ]] && args+=(--filter "$KD_TEST_FILTER")
    swift test "${args[@]}" 2>&1 | tee "$ROOT/mac.log" \
        | grep -E --line-buffered '✘|error:|Test run with|^↳' | grep -Ev --line-buffered '^↳ (///|Testing Library|Target Platform)'
    return "${PIPESTATUS[0]}"
}

run_windows() {
    local dotnet
    dotnet="$(dotnet_bin)"
    if [[ -z "$dotnet" ]]; then
        echo "  .NET SDK yok. Kurmak için (sudo gerekmez):"
        echo "    curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0"
        return 2
    fi
    local args=(test Tests/Windows --nologo -v quiet --logger "console;verbosity=normal")
    [[ -n "${KD_TEST_FILTER:-}" ]] && args+=(--filter "DisplayName~$KD_TEST_FILTER")
    DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 "$dotnet" "${args[@]}" 2>&1 | tee "$ROOT/windows.log" \
        | grep -E --line-buffered '^\s+Failed |error |Passed!|Failed!|Test Run (Successful|Failed)|^\s*(Total tests|Passed|Failed|Skipped): |Assert\.|Expected:|Actual:|^\s+at KDDownloadManager\.Tests' \
        | grep -v --line-buffered '^\[xUnit'
    return "${PIPESTATUS[0]}"
}

run_extension() {
    if ! command -v node >/dev/null; then
        echo "  node yok (brew install node); eklenti testleri atlandı."
        return 2
    fi
    local args=(--test)
    [[ -n "${KD_TEST_FILTER:-}" ]] && args+=(--test-name-pattern "$KD_TEST_FILTER")
    node "${args[@]}" Tests/Extension/*.test.mjs 2>&1 | tee "$ROOT/extension.log" \
        | grep -E --line-buffered '^✖|^ℹ (pass|fail)|AssertionError|actual:|expected:'
    return "${PIPESTATUS[0]}"
}

for SUITE in "${SUITES[@]}"; do
    case "$SUITE" in
        mac) TITLE="Mac uygulaması" ;;
        windows) TITLE="Windows uygulaması" ;;
        extension) TITLE="Chrome eklentisi" ;;
        *) echo "Bilinmeyen test grubu: $SUITE (mac, windows, extension)" >&2; exit 64 ;;
    esac
    echo "━━ $TITLE"
    STEP=$SECONDS
    "run_$SUITE"
    STATUS=$?
    case $STATUS in
        0) PASSED+=("$TITLE ($((SECONDS - STEP)) sn)") ;;
        2) SKIPPED+=("$TITLE") ;;
        *) FAILED+=("$TITLE") ;;
    esac
done

echo "━━ Sonuç ($((SECONDS - START)) sn)"
for item in ${PASSED[@]+"${PASSED[@]}"}; do echo "  ✓ $item"; done
for item in ${SKIPPED[@]+"${SKIPPED[@]}"}; do echo "  – $item: atlandı (araç yok)"; done
for item in ${FAILED[@]+"${FAILED[@]}"}; do echo "  ✗ $item"; done

[[ ${#FAILED[@]} -eq 0 ]] || exit 1
# Yayın ve push sırasında araç eksikliği de engel: bir platform denetlenmeden çıkmasın.
[[ ${#SKIPPED[@]} -eq 0 || -z "${KD_TESTS_REQUIRE_ALL:-}" ]] || { echo "✗ Bazı testler çalıştırılamadı" >&2; exit 1; }
exit 0
