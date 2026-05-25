#!/usr/bin/env bash
# =============================================================================
#  bigpicture.sh — Steam Big Picture Mode Launcher
#  For: CachyOS · KDE Plasma (Wayland) · PipeWire
# =============================================================================

TV_OUTPUT=""
TV_SINK=""
LAYOUT_FILE="${XDG_RUNTIME_DIR:-/tmp}/bigpicture_layout"
STEAM_LOG="$HOME/.local/share/Steam/logs/gameprocess_log.txt"

log() { echo "[bigpicture] $*"; }
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# ==========================================================================
#  SETUP MODE
# ==========================================================================
if [[ "${1:-}" == "--setup" ]]; then
    echo ""
    echo "══════════════════════════════════════════════"
    echo "  Big Picture Setup Helper"
    echo "══════════════════════════════════════════════"
    echo ""
    echo "── Monitors ──────────────────────────────────"
    kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -E "^Output:|Geometry:|Scale:" | sed 's/^/  /'
    echo ""
    echo "── Audio Sinks ───────────────────────────────"
    pactl list sinks short | sed 's/^/  /'
    echo ""
    echo "── Current Config in Script ──────────────────"
    echo "  TV_OUTPUT = $TV_OUTPUT"
    echo "  TV_SINK   = $TV_SINK"
    echo "══════════════════════════════════════════════"
    exit 0
fi

find_steam_pid() {
    pgrep -f "ubuntu12_32/steam" 2>/dev/null | head -1
}

# ==========================================================================
#  SAVE MONITOR LAYOUT
# ==========================================================================
save_layout() {
    log "Saving monitor layout..."
    local clean name geom scale cur_mode enabled
    clean=$(kscreen-doctor -o 2>/dev/null | strip_ansi)
    : > "$LAYOUT_FILE"

    flush() {
        [[ -z "$name" ]] && return
        if [[ "$enabled" == "1" ]]; then
            echo "output.$name.enable"
        else
            echo "output.$name.disable"
        fi
        [[ -n "$cur_mode" ]] && echo "output.$name.mode.$cur_mode"
        [[ -n "$geom"     ]] && echo "output.$name.position.$geom"
        [[ -n "$scale"    ]] && echo "output.$name.scale.$scale"
    }

    name="" geom="" scale="" cur_mode="" enabled=""
    while IFS= read -r line; do
        line="${line//$'\r'/}"
        if [[ "$line" =~ ^Output:[[:space:]]+[0-9]+[[:space:]]+([^[:space:]]+) ]]; then
            flush >> "$LAYOUT_FILE"
            name="${BASH_REMATCH[1]}"
            geom="" scale="" cur_mode="" enabled=""
        elif [[ "$line" == *"enabled"* ]]; then
            enabled=1
        elif [[ "$line" =~ Geometry:[[:space:]]+([0-9]+,[0-9]+) ]]; then
            geom="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ Scale:[[:space:]]+([0-9.]+) ]]; then
            scale="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ Modes:.*[[:space:]]([0-9x@.]+)\* ]]; then
            cur_mode="${BASH_REMATCH[1]}"
        fi
    done <<< "$clean"
    flush >> "$LAYOUT_FILE"

    log "Layout saved:"
    sed 's/^/  /' "$LAYOUT_FILE"
}

restore_layout() {
    [[ ! -f "$LAYOUT_FILE" ]] && { log "No layout file found!"; return 1; }
    local args=()
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        # Drop any saved commands for the TV — it always goes OFF on restore,
        # so we ignore its saved enable/mode/position/scale lines here.
        [[ "$cmd" == "output.$TV_OUTPUT".* ]] && continue
        args+=("$cmd")
    done < "$LAYOUT_FILE"
    # Always disable the TV when returning to the desktop.
    args+=("output.$TV_OUTPUT.disable")
    log "Restoring monitors (TV forced off): ${args[*]}"
    kscreen-doctor "${args[@]}" 2>/dev/null \
        && log "Monitors restored, TV disabled." \
        || log "WARNING: monitor restore had errors."
}

# ==========================================================================
#  SAVE STATE
# ==========================================================================
log "=== Starting Big Picture mode ==="
save_layout

ALL_OUTPUTS=()
while IFS= read -r n; do
    [[ -n "$n" ]] && ALL_OUTPUTS+=("$n")
done < <(kscreen-doctor -o 2>/dev/null | strip_ansi | grep '^Output:' | awk '{print $3}')
log "Detected outputs: ${ALL_OUTPUTS[*]:-NONE}"

SAVED_SINK=$(pactl get-default-sink 2>/dev/null || echo "")
log "Current audio sink: $SAVED_SINK"

# ==========================================================================
#  RESTORE FUNCTION
# ==========================================================================
restore() {
    log ""
    log "=== Restoring your setup ==="
    restore_layout
    sleep 2
    if [[ -n "$SAVED_SINK" ]]; then
        log "Restoring audio: $SAVED_SINK"
        pactl set-default-sink "$SAVED_SINK" 2>/dev/null
    fi
    log "Done! Welcome back."
}
trap restore EXIT

# ==========================================================================
#  HANDLE STEAM — shutdown if running, relaunch in -tenfoot
# ==========================================================================
EXISTING_PID=$(find_steam_pid)
if [[ -n "$EXISTING_PID" ]]; then
    log "Steam running (PID: $EXISTING_PID) — restarting in Big Picture mode..."
    /$HOME/.local/share/Steam/ubuntu12_32/steam -shutdown > /dev/null 2>&1 || true
    for i in $(seq 1 15); do
        sleep 1
        kill -0 "$EXISTING_PID" 2>/dev/null || break
    done
    kill -0 "$EXISTING_PID" 2>/dev/null && kill "$EXISTING_PID" 2>/dev/null || true
    sleep 2
    log "Steam closed."
fi

# ==========================================================================
#  DISABLE MONITORS EXCEPT TV
# ==========================================================================
[[ ${#ALL_OUTPUTS[@]} -eq 0 ]] && { log "ERROR: No outputs detected."; exit 1; }

log "Switching to TV-only mode..."
KCMD=()
for output in "${ALL_OUTPUTS[@]}"; do
    if [[ "$output" == "$TV_OUTPUT" ]]; then
        log "  Keeping: $output"
        KCMD+=("output.$output.enable")
    else
        log "  Disabling: $output"
        KCMD+=("output.$output.disable")
    fi
done
kscreen-doctor "${KCMD[@]}" 2>/dev/null && log "Display switch applied." || log "WARNING: display switch had errors."
sleep 2

# ==========================================================================
#  SWITCH AUDIO
# ==========================================================================
log "Switching audio to TV: $TV_SINK"
pactl set-default-sink "$TV_SINK" && log "Audio switched." || log "WARNING: audio switch failed."

# ==========================================================================
#  LAUNCH STEAM IN BIG PICTURE
# ==========================================================================
log "Launching Steam in Big Picture mode..."
steam -tenfoot > /dev/null 2>&1 &

log "Waiting for Steam to start..."
STEAM_PID=""
for i in $(seq 1 25); do
    STEAM_PID=$(find_steam_pid)
    [[ -n "$STEAM_PID" ]] && { log "Steam running (PID: $STEAM_PID)"; break; }
    sleep 2
done

[[ -z "$STEAM_PID" ]] && { log "ERROR: Steam not found after launch."; exit 1; }

# ==========================================================================
#  WATCH FOR BIG PICTURE ACTIVE + EXIT
#
#  Steam logs UI-mode transitions like "UI mode (4->7)" to STEAM_LOG.
#  On this build, the DESTINATION number tells us the current state:
#    ...->4)  = now in Big Picture (gamepad UI)
#    ...->7)  = now on Desktop
#
#  We read only the TAIL of the log each poll (cheap and constant-time),
#  and key off the destination mode of the most recent transition rather
#  than matching exact (from->to) pairs. This is robust to flickers during
#  startup or when launching a game.
# ==========================================================================

# Most recent UI-mode transition, read cheaply from the end of the log.
last_ui_mode() {
    tail -n 200 "$STEAM_LOG" 2>/dev/null | grep -oE "UI mode \([0-9]+->[0-9]+\)" | tail -1
}

# Wait for Big Picture to become active (destination mode 4).
log "Waiting for Big Picture mode to become active..."
while kill -0 "$STEAM_PID" 2>/dev/null; do
    if [[ "$(last_ui_mode)" == *"->4)"* ]]; then
        log "Big Picture mode is active."
        break
    fi
    sleep 1
done
kill -0 "$STEAM_PID" 2>/dev/null || { log "Steam exited before Big Picture became active."; exit 1; }

# Watch for exit (destination mode 7, sustained).
# A real exit = currently on Desktop and still on Desktop a few seconds later.
# Brief flickers (e.g. launching a game) resolve back to ->4 and are ignored.
log "Monitoring for Big Picture exit... (exit Big Picture to restore your setup)"
prev=""
while kill -0 "$STEAM_PID" 2>/dev/null; do
    cur="$(last_ui_mode)"

    if [[ -n "$cur" && "$cur" != "$prev" ]]; then
        log "  [log] $cur"
        prev="$cur"
    fi

    if [[ "$cur" == *"->7)"* ]]; then
        # Possible exit — confirm it sticks before tearing down.
        log "  [log] Possible exit detected, confirming in 4s..."
        sleep 4
        confirm="$(last_ui_mode)"
        if [[ "$confirm" == *"->7)"* ]]; then
            log "Big Picture mode exited (confirmed)."
            break
        else
            log "  [log] Back in Big Picture — still active, continuing..."
            prev="$confirm"
        fi
    fi

    sleep 1
done

# Process exit (Steam closed entirely) also falls through to here and triggers
# the EXIT trap, restoring monitors + audio.
kill -0 "$STEAM_PID" 2>/dev/null || log "Steam process exited."
