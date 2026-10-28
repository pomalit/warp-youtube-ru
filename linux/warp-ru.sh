#!/usr/bin/env bash
# Reconnects Cloudflare WARP (proxy mode, 127.0.0.1:40000) until YouTube sees a Russian IP.
# Usage:
#   ./warp-ru.sh               # reconnect until RU
#   ./warp-ru.sh --check       # only show current country
#   ./warp-ru.sh --install     # also run at every login (systemd user service)
#   ./warp-ru.sh --uninstall   # stop running at login
# Options: --max-tries N (default 40), --want CC (default RU)
set -u

PROXY=127.0.0.1:40000
WANT=RU
MAX_TRIES=40
MODE=run
SERVICE=warp-ru.service
UNIT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$SERVICE"

while [ $# -gt 0 ]; do
    case "$1" in
        --check)     MODE=check ;;
        --startup)   MODE=startup ;;
        --install)   MODE=install ;;
        --uninstall) MODE=uninstall ;;
        --max-tries) MAX_TRIES="$2"; shift ;;
        --want)      WANT="$2"; shift ;;
        -h|--help)   sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ "$MODE" = uninstall ]; then
    systemctl --user disable --now "$SERVICE" 2>/dev/null
    rm -f "$UNIT_FILE"
    systemctl --user daemon-reload
    echo "Removed from startup."
    exit 0
fi

if ! command -v warp-cli >/dev/null; then
    echo "Cloudflare WARP is not installed. See README for install steps." >&2
    exit 2
fi
if ! command -v curl >/dev/null; then
    echo "curl is not installed." >&2
    exit 2
fi

if [ "$MODE" = install ]; then
    mkdir -p "$(dirname "$UNIT_FILE")"
    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Reconnect Cloudflare WARP until YouTube sees $WANT

[Service]
Type=oneshot
ExecStart=$(realpath "$0") --startup --want $WANT --max-tries $MAX_TRIES

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE"
    echo "Added to startup: $UNIT_FILE"
    echo "Log after each login: journalctl --user -u $SERVICE"
fi

if [ "$MODE" = startup ]; then
    # wait up to 3 minutes for the internet to come up after login
    for _ in $(seq 36); do
        curl -s -o /dev/null --max-time 5 https://www.youtube.com/ && break
        sleep 5
    done
fi

warp() { warp-cli --accept-tos "$@"; }

warp_connected() { warp status 2>/dev/null | grep -q 'Status update: Connected'; }

youtube_country() {
    # SOCKS4 over IPv4, same as the browser: WARP's IPv4 and IPv6 exits geolocate differently,
    # and when WARP resolves the name itself it picks IPv6
    curl -s -4 --max-time 20 --socks4 "$PROXY" -H 'Accept-Language: en-US' https://www.youtube.com/ \
        | grep -o '"GL":"[A-Z][A-Z]"' | head -n 1 | cut -d '"' -f 4
}

connect_warp() {
    warp disconnect >/dev/null 2>&1
    sleep 2
    warp connect >/dev/null 2>&1
    # wait for the proxy to come up
    for _ in $(seq 15); do
        warp_connected && break
        sleep 1
    done
    sleep 3
}

if ! pgrep -x warp-svc >/dev/null; then
    echo "The WARP daemon is not running. Run: sudo systemctl enable --now warp-svc" >&2
    exit 2
fi

# first run on this machine: create a free WARP registration
warp registration show >/dev/null 2>&1 || warp registration new >/dev/null

# make sure WARP never takes over the whole machine
if ! warp settings 2>/dev/null | grep -q 'Mode: WarpProxy on port 40000'; then
    warp mode proxy >/dev/null
    warp proxy port 40000 >/dev/null
fi

warp_connected || connect_warp

country=$(youtube_country)
echo "YouTube sees: $country"
if [ "$country" = "$WANT" ]; then echo "Good, already $WANT."; exit 0; fi
[ "$MODE" = check ] && exit 1

for try in $(seq "$MAX_TRIES"); do
    connect_warp
    country=$(youtube_country)
    echo "try $try : $country"
    if [ "$country" = "$WANT" ]; then
        echo "Got $WANT. Stay connected (don't reconnect WARP) to keep it."
        exit 0
    fi
done

echo "No $WANT address after $MAX_TRIES tries. Try again later."
exit 1
