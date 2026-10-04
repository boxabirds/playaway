#!/bin/bash
# Launch-time harness (launch.measure.harness).
#
# Usage: scripts/launch-bench.sh <app-bundle> <cold|warm> [runs=10] [document-fixture]
#        scripts/launch-bench.sh --verdict <elapsed-ms>      (prints the verdict for one elapsed time)
#
# Start point (a PROPOSAL for the owner to confirm): CLOCK_MONOTONIC_RAW read immediately before `open -n`.
# Stop point (same proposal): the "windowShown" line the app writes to the file named by LOCALPLAYER_LAUNCH_TRACE,
# which uses the same clock. Elapsed whole milliseconds are rounded up.
#
# Cold: runs `purge` first when it is possible (needs root; this script never prompts for a password). The purge is a
# PROXY for a restart and every cold result is labelled as such. When purge is not possible the cold runs are labelled
# "NOT COLD: cache not purged" and must not be read as cold results.
#
# Writes only its own results file (LAUNCH_BENCH_RESULTS, default under $TMPDIR) plus a scratch directory for per-run
# trace files and its clock helper, which is removed on exit. Never touches playlists or audio files: the optional
# document fixture is only passed to `open` for the app to read.
#
# Test seams: LAUNCH_BENCH_OPEN replaces `open`; LAUNCH_BENCH_TIMEOUT_SECONDS (default 10) bounds each run.
set -u

BUDGET_MS=1000
DEFAULT_RUNS=10
DEFAULT_TIMEOUT_SECONDS=10
POLL_INTERVAL_SECONDS=0.02
QUIT_WAIT_ITERATIONS=100
QUIT_POLL_SECONDS=0.1
NS_PER_MS=1000000
TRACE_ENV="LOCALPLAYER_LAUNCH_TRACE"
OPEN_COMMAND="${LAUNCH_BENCH_OPEN:-open}"
TIMEOUT_SECONDS="${LAUNCH_BENCH_TIMEOUT_SECONDS:-$DEFAULT_TIMEOUT_SECONDS}"

# Verdict for one elapsed time in ms: 1000 within, 1001 over, <=0 or empty invalid.
verdict_for() {
    local ms="${1:-}"
    if [[ -z "$ms" || ! "$ms" =~ ^-?[0-9]+$ || "$ms" -le 0 ]]; then echo "invalid"; return; fi
    if [[ "$ms" -le "$BUDGET_MS" ]]; then echo "within"; else echo "over"; fi
}

if [[ "${1:-}" == "--verdict" ]]; then verdict_for "${2:-}"; exit 0; fi

APP="${1:-}"; TEMPERATURE="${2:-}"; RUNS="${3:-$DEFAULT_RUNS}"; FIXTURE="${4:-}"
if [[ -z "$APP" || ( "$TEMPERATURE" != "cold" && "$TEMPERATURE" != "warm" ) || ! "$RUNS" =~ ^[0-9]+$ || "$RUNS" -lt 1 ]]; then
    echo "usage: $0 <app-bundle> <cold|warm> [runs=$DEFAULT_RUNS] [document-fixture]" >&2; exit 2
fi
if [[ ! -d "$APP" ]]; then echo "app bundle not found: $APP" >&2; exit 2; fi
if [[ -n "$FIXTURE" && ! -e "$FIXTURE" ]]; then echo "fixture not found: $FIXTURE" >&2; exit 2; fi
APP="$(cd "$APP" && pwd)"
EXECUTABLE_DIR="$APP/Contents/MacOS/"

RESULTS="${LAUNCH_BENCH_RESULTS:-${TMPDIR:-/tmp}/localplayer-launch-bench-$TEMPERATURE-$(date +%Y%m%d-%H%M%S).txt}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/launch-bench.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

# Clock helper: writes CLOCK_MONOTONIC_RAW nanoseconds to a file, then execs the rest, so the start timestamp is read
# immediately before `open`.
cat > "$WORK/clock.c" <<'CSRC'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
int main(int argc, char **argv) {
    if (argc < 3) return 2;
    unsigned long long ns = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    FILE *f = fopen(argv[1], "w");
    if (!f) return 3;
    fprintf(f, "%llu\n", ns);
    fclose(f);
    execvp(argv[2], argv + 2);
    return 4;
}
CSRC
if ! cc -O1 -o "$WORK/clock" "$WORK/clock.c"; then echo "could not build clock helper" >&2; exit 2; fi

SYSTEM="$(sysctl -n machdep.cpu.brand_string 2>/dev/null) / macOS $(sw_vers -productVersion 2>/dev/null)"
LABEL="$TEMPERATURE"
if [[ "$TEMPERATURE" == "cold" ]]; then
    if [[ "$(id -u)" == "0" ]] || sudo -n true 2>/dev/null; then
        PURGE_CMD="sudo -n purge"; [[ "$(id -u)" == "0" ]] && PURGE_CMD="purge"
        LABEL="cold (PROXY: file cache purged, not a restart)"
    else
        PURGE_CMD=""
        LABEL="cold requested but NOT COLD: cache not purged (purge needs root; run with sudo or restart the Mac)"
        echo "note: purge needs root and no passwordless sudo is available; skipping purge." >&2
    fi
fi

emit() { echo "$*" | tee -a "$RESULTS"; }
: > "$RESULTS"
emit "launch-bench: app=$APP"
emit "launch-bench: system=$SYSTEM; this is a measurement of THIS machine only"
emit "launch-bench: class=$LABEL runs=$RUNS budget=${BUDGET_MS}ms fixture=${FIXTURE:-none}"
emit "launch-bench: start=CLOCK_MONOTONIC_RAW before 'open -n'; stop=windowShown line of the app trace (proposal, owner to confirm)"

running_pids() { pgrep -f "$EXECUTABLE_DIR" 2>/dev/null; }

quit_app() {
    local pids; pids="$(running_pids)"
    [[ -z "$pids" ]] && return 0
    kill -TERM $pids 2>/dev/null
    local i=0
    while [[ -n "$(running_pids)" && $i -lt $QUIT_WAIT_ITERATIONS ]]; do sleep "$QUIT_POLL_SECONDS"; i=$((i+1)); done
    [[ -n "$(running_pids)" ]] && { kill -KILL $(running_pids) 2>/dev/null; sleep "$QUIT_POLL_SECONDS"; }
    return 0
}

quit_app
within=0; over=0; invalid=0
for ((run = 1; run <= RUNS; run++)); do
    TRACE="$WORK/trace-$run.jsonl"; STARTFILE="$WORK/start-$run"; : > "$TRACE"
    [[ -n "${PURGE_CMD:-}" ]] && $PURGE_CMD >/dev/null 2>&1
    OPEN_ARGS=(-n --env "$TRACE_ENV=$TRACE" "$APP")
    if [[ -n "$FIXTURE" ]]; then OPEN_ARGS=(-n --env "$TRACE_ENV=$TRACE" -a "$APP" "$FIXTURE"); fi
    "$WORK/clock" "$STARTFILE" "$OPEN_COMMAND" "${OPEN_ARGS[@]}" >/dev/null 2>&1

    stop=""; deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
    while [[ -z "$stop" && $(date +%s) -le $deadline ]]; do
        stop="$(sed -n 's/.*"phase":"windowShown","nanoseconds":\([0-9]*\).*/\1/p' "$TRACE" 2>/dev/null | head -1)"
        [[ -z "$stop" ]] && sleep "$POLL_INTERVAL_SECONDS"
    done
    start="$(cat "$STARTFILE" 2>/dev/null)"

    ms=""
    if [[ -n "$stop" && -n "$start" ]]; then
        delta=$(( stop - start ))
        ms=$(( delta / NS_PER_MS )); [[ $(( delta % NS_PER_MS )) -gt 0 && $delta -gt 0 ]] && ms=$(( ms + 1 ))
    fi
    v="$(verdict_for "$ms")"
    case "$v" in
        within)  within=$((within+1)); emit "run $run: ${ms} ms  within budget" ;;
        over)    over=$((over+1));     emit "run $run: ${ms} ms  OVER BUDGET" ;;
        *)       invalid=$((invalid+1)); emit "run $run: INVALID (${ms:-no stop timestamp within ${TIMEOUT_SECONDS}s})" ;;
    esac
    quit_app
done

if [[ $over -eq 0 && $invalid -eq 0 ]]; then BATCH="PASS"; STATUS=0; else BATCH="FAIL"; STATUS=1; fi
emit "BATCH [$LABEL]: $BATCH ($within within, $over over budget, $invalid invalid of $RUNS)"
emit "results file: $RESULTS"
exit $STATUS
