#!/bin/bash
# mac-refresh.sh - Release DHCP, change MAC on eth0, renew DHCP
# EdgeRouter X / EdgeOS compatible
# Temporary change only - does NOT survive reboot

INTERFACE="eth0"
LOG_TAG="mac-refresh"

# ─────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1"
}

validate_mac() {
    echo "$1" | grep -qiE '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
}

generate_random_mac() {
    # Locally administered (bit 1 set), unicast (bit 0 clear) = safe for spoofing
    printf '02:%02x:%02x:%02x:%02x:%02x' \
        $((RANDOM % 256)) $((RANDOM % 256)) \
        $((RANDOM % 256)) $((RANDOM % 256)) \
        $((RANDOM % 256))
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo ""
        echo "  ERROR: This script must be run as root."
        echo "         Try:  sudo $0"
        echo ""
        exit 1
    fi
}

# ─────────────────────────────────────────
#  Banner
# ─────────────────────────────────────────
print_banner() {
    clear
    echo "========================================"
    echo "   MAC Address Refresh  —  EdgeRouter X "
    echo "========================================"
    echo "  Interface : $INTERFACE"
    echo "  Current MAC: $(ip link show "$INTERFACE" 2>/dev/null | awk '/ether/ {print $2}')"
    echo "  Current IP : $(ip addr show "$INTERFACE" 2>/dev/null | awk '/inet / {print $2}' | head -1)"
    echo "========================================"
    echo ""
}

# ─────────────────────────────────────────
#  Interactive Menu
# ─────────────────────────────────────────
interactive_menu() {
    print_banner

    echo "  Choose an option:"
    echo ""
    echo "    [1]  Generate a random MAC address"
    echo "    [2]  Enter a MAC address manually"
    echo "    [3]  Show current interface info only"
    echo "    [Q]  Quit / Cancel"
    echo ""
    read -rp "  Your choice: " CHOICE

    case "$CHOICE" in
        1)
            NEW_MAC=$(generate_random_mac)
            echo ""
            echo "  Generated MAC: $NEW_MAC"
            echo ""
            confirm_and_run
            ;;
        2)
            echo ""
            echo "  Enter MAC address (format: XX:XX:XX:XX:XX:XX)"
            read -rp "  MAC: " NEW_MAC
            NEW_MAC="${NEW_MAC^^}"   # uppercase for consistency
            if ! validate_mac "$NEW_MAC"; then
                echo ""
                echo "  ERROR: Invalid format — expected XX:XX:XX:XX:XX:XX"
                echo "         Example: 02:AB:CD:EF:12:34"
                echo ""
                read -rp "  Press Enter to return to menu..." _
                interactive_menu
            else
                echo ""
                confirm_and_run
            fi
            ;;
        3)
            echo ""
            ip link show "$INTERFACE"
            echo ""
            ip addr show "$INTERFACE"
            echo ""
            read -rp "  Press Enter to return to menu..." _
            interactive_menu
            ;;
        [Qq])
            echo ""
            echo "  Cancelled. No changes made."
            echo ""
            exit 0
            ;;
        *)
            echo ""
            echo "  Invalid option. Please try again."
            sleep 1
            interactive_menu
            ;;
    esac
}

# ─────────────────────────────────────────
#  Confirm Before Running
# ─────────────────────────────────────────
confirm_and_run() {
    OLD_MAC=$(ip link show "$INTERFACE" | awk '/ether/ {print $2}')

    echo "  ┌─────────────────────────────────────┐"
    echo "  │  Ready to apply changes              │"
    echo "  ├─────────────────────────────────────┤"
    printf  "  │  Interface : %-23s│\n" "$INTERFACE"
    printf  "  │  Old MAC   : %-23s│\n" "$OLD_MAC"
    printf  "  │  New MAC   : %-23s│\n" "$NEW_MAC"
    echo "  └─────────────────────────────────────┘"
    echo ""
    echo "  NOTE: This is a TEMPORARY change (lost on reboot)"
    echo ""
    read -rp "  Proceed? [y/N]: " CONFIRM

    case "$CONFIRM" in
        [Yy])
            run_refresh
            ;;
        *)
            echo ""
            echo "  Cancelled. No changes made."
            echo ""
            read -rp "  Press Enter to return to menu..." _
            interactive_menu
            ;;
    esac
}

# ─────────────────────────────────────────
#  Core Logic
# ─────────────────────────────────────────
run_refresh() {
    echo ""
    log "Starting MAC refresh on $INTERFACE"
    log "Old MAC: $OLD_MAC  →  New MAC: $NEW_MAC"

    # Step 1 — Release DHCP lease
    log "Step 1/4 — Releasing DHCP lease..."
    if command -v dhclient &>/dev/null; then
        dhclient -r "$INTERFACE" 2>/dev/null
    elif command -v dhcpcd &>/dev/null; then
        dhcpcd -k "$INTERFACE" 2>/dev/null
    else
        kill "$(cat /var/run/dhclient-"$INTERFACE".pid 2>/dev/null)" 2>/dev/null
    fi
    sleep 1

    # Step 2 — Bring interface down
    log "Step 2/4 — Bringing $INTERFACE down..."
    if ! ip link set dev "$INTERFACE" down; then
        log "ERROR: Failed to bring $INTERFACE down. Aborting."
        exit 1
    fi
    sleep 1

    # Step 3 — Change MAC
    log "Step 3/4 — Applying new MAC address $NEW_MAC..."
    if ! ip link set dev "$INTERFACE" address "$NEW_MAC"; then
        log "ERROR: Failed to set MAC. Restoring interface..."
        ip link set dev "$INTERFACE" up
        exit 1
    fi

    # Step 4 — Bring interface back up
    log "Step 4/4 — Bringing $INTERFACE up..."
    if ! ip link set dev "$INTERFACE" up; then
        log "ERROR: Failed to bring $INTERFACE back up."
        exit 1
    fi
    sleep 2

    # Step 5 — Renew DHCP
    log "Requesting new DHCP lease..."
    if command -v dhclient &>/dev/null; then
        dhclient "$INTERFACE" 2>/dev/null
    elif command -v dhcpcd &>/dev/null; then
        dhcpcd "$INTERFACE" 2>/dev/null
    else
        /opt/vyatta/sbin/vyatta-dhclient.pl --op=start --interface="$INTERFACE" 2>/dev/null
    fi
    sleep 3

    # ── Results ──
    ACTIVE_MAC=$(ip link show "$INTERFACE" | awk '/ether/ {print $2}')
    NEW_IP=$(ip addr show "$INTERFACE" | awk '/inet / {print $2}' | head -1)

    echo ""
    echo "========================================"
    echo "  Result"
    echo "========================================"
    echo "  Interface : $INTERFACE"
    echo "  Old MAC   : $OLD_MAC"
    echo "  New MAC   : $ACTIVE_MAC"
    echo "  New IP    : ${NEW_IP:-"(pending — try: dhclient $INTERFACE)"}"
    echo "========================================"

    if [ "$ACTIVE_MAC" != "$NEW_MAC" ]; then
        echo ""
        log "WARNING: Active MAC ($ACTIVE_MAC) does not match requested ($NEW_MAC)"
        echo "  The change may not have taken. Try running again."
    else
        echo ""
        log "Success — MAC changed and DHCP renewed."
    fi

    echo ""
    read -rp "  Press Enter to return to menu..." _
    interactive_menu
}

# ─────────────────────────────────────────
#  Entry Point
# ─────────────────────────────────────────
require_root
interactive_menu
