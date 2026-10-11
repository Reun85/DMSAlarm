#!/bin/sh
# Play a sound once or loop it until killed.
#
#   ck-sound.sh <name-or-path> <volume-percent> <loop: 0|1>
#
# A bare name is resolved, in order, as:
#   1. the plugin's own sounds/<name>.oga (bundled: "alarm", "chime")
#   2. sounds/<theme>/stereo/<name>.{oga,ogg,wav} when given as "<theme>/<name>"
#      (e.g. "ocean/bell"), else in the freedesktop theme
# searching $XDG_DATA_DIRS (on NixOS that covers the user and system profiles)
# and a few fixed fallbacks. pw-play is preferred, paplay is the fallback.
#
# The QML side runs this through a Process and stops a loop by killing it, so
# the loop needs no exit condition of its own. exec on the final player keeps
# the one-shot case to a single process.
set -u

name=${1:-}
vol=${2:-100}
loop=${3:-0}

[ -n "$name" ] || exit 0

here=$(cd "$(dirname "$0")" && pwd)

resolve() {
    case "$1" in
        /*) [ -f "$1" ] && { printf '%s\n' "$1"; return 0; }; return 1 ;;
        */*) theme=${1%%/*}; base=${1#*/} ;;
        *)
            if [ -f "$here/../sounds/$1.oga" ]; then
                printf '%s\n' "$here/../sounds/$1.oga"
                return 0
            fi
            theme=freedesktop; base=$1 ;;
    esac
    dirs="${XDG_DATA_DIRS:-}:${HOME:-}/.nix-profile/share:/etc/profiles/per-user/${USER:-}/share:/run/current-system/sw/share:/usr/local/share:/usr/share"
    old_ifs=$IFS
    IFS=:
    for d in $dirs; do
        [ -n "$d" ] || continue
        for ext in oga ogg wav; do
            f="$d/sounds/$theme/stereo/$base.$ext"
            if [ -f "$f" ]; then
                IFS=$old_ifs
                printf '%s\n' "$f"
                return 0
            fi
        done
    done
    IFS=$old_ifs
    return 1
}

file=$(resolve "$name") || { echo "ck-sound: sound not found: $name" >&2; exit 2; }

# pw-play takes a 0..1(+) float; paplay takes 0..65536.
pw_vol=$(awk -v v="$vol" 'BEGIN { printf "%.2f", v / 100 }')
pa_vol=$(awk -v v="$vol" 'BEGIN { printf "%d", v * 655.36 }')

# exec, so that in the looping case `$!` is the player itself and the trap
# below kills the actual audio rather than a wrapper subshell.
play() {
    if command -v pw-play >/dev/null 2>&1; then
        exec pw-play --volume "$pw_vol" "$file"
    elif command -v paplay >/dev/null 2>&1; then
        exec paplay --volume "$pa_vol" "$file"
    else
        echo "ck-sound: neither pw-play nor paplay found" >&2
        exit 3
    fi
}

if [ "$loop" != 1 ]; then
    play
fi

# Looping: the player runs in the background so a TERM from the shell (the QML
# Process being stopped) can take it down too. Without this the current play-
# through would finish after "Dismiss" — several seconds of alarm too many.
child=""
trap 'kill "$child" 2>/dev/null; exit 0' TERM INT HUP
while :; do
    (play) &
    child=$!
    wait "$child" || exit $?
    sleep 0.4
done
