# mac-refresh

A simple interactive Bash script for **EdgeRouter X** (EdgeOS) that releases your DHCP lease, temporarily changes the MAC address on `eth0`, and renews the lease — all from a guided menu. No flags to memorize, no permanent changes made.

---

## Why Would You Use This?

Your MAC address is one of the first identifiers a network sees when you connect. There are several legitimate reasons you might want to temporarily change it:

- **DHCP refresh / new IP assignment** — Some ISPs or networks tie lease records to your MAC. Changing it is the most reliable way to get a fresh IP rather than the same one handed back from cache.
- **Network troubleshooting** — Useful when diagnosing whether a device ban, filter, or lease conflict is MAC-based.
- **Privacy on untrusted networks** — Reduces persistent tracking by captive portals or logging systems that fingerprint by hardware address.
- **Testing and lab work** — Simulate a different device on the network without needing separate hardware.
- **ISP re-authentication** — Some ISPs authenticate sessions by MAC. Spoofing a previously registered MAC can restore connectivity after a hardware swap.

> ⚠️ **This script makes a temporary change only.** The MAC address reverts to the original burned-in hardware value on reboot. No configuration files are modified.

---

## Requirements

- Ubiquiti **EdgeRouter X** running EdgeOS (VyOS-based)
- Root / `sudo` access via SSH or the Web GUI terminal
- Standard tools: `ip`, `dhclient` or `dhcpcd` (included in EdgeOS)

---

## Installation

Copy the script to your EdgeRouter via SCP from your local machine:

```bash
scp mac-refresh.sh admin@192.168.1.1:/home/admin/
```

SSH into the router, then make the script executable:

```bash
ssh admin@192.168.1.1
chmod +x mac-refresh.sh
```

---

## Usage

```bash
sudo ./mac-refresh.sh
```

That's it. The script is fully menu-driven — no flags required.

---

## What It Does — Step by Step

When you run the script, you're greeted with a live status banner and a simple menu:

```
========================================
   MAC Address Refresh  —  EdgeRouter X
========================================
  Interface : eth0
  Current MAC: aa:bb:cc:dd:ee:ff
  Current IP : 203.0.113.45/24
========================================

  Choose an option:

    [1]  Generate a random MAC address
    [2]  Enter a MAC address manually
    [3]  Show current interface info only
    [Q]  Quit / Cancel
```

### Option 1 — Random MAC
Generates a locally-administered, unicast MAC address (prefix `02:xx:...`) that is safe for spoofing and won't conflict with real hardware OUIs.

```
  Generated MAC: 02:4f:a1:7c:3e:9b

  ┌─────────────────────────────────────┐
  │  Ready to apply changes              │
  ├─────────────────────────────────────┤
  │  Interface : eth0                   │
  │  Old MAC   : aa:bb:cc:dd:ee:ff      │
  │  New MAC   : 02:4f:a1:7c:3e:9b      │
  └─────────────────────────────────────┘

  NOTE: This is a TEMPORARY change (lost on reboot)

  Proceed? [y/N]:
```

### Option 2 — Manual MAC Entry
Prompts you to type in a specific MAC address. Input is validated before anything is applied — an invalid format sends you back to the menu rather than failing mid-run.

```
  Enter MAC address (format: XX:XX:XX:XX:XX:XX)
  MAC: 02:AB:CD:EF:12:34
```

### Under the Hood — Execution Order

Once confirmed, the script runs these steps in sequence:

| Step | Action |
|------|--------|
| 1 | Release the current DHCP lease (`dhclient -r eth0`) |
| 2 | Bring `eth0` down (`ip link set dev eth0 down`) |
| 3 | Apply the new MAC address (`ip link set dev eth0 address ...`) |
| 4 | Bring `eth0` back up (`ip link set dev eth0 up`) |
| 5 | Request a fresh DHCP lease (`dhclient eth0`) |

The DHCP release happens **first**, before the interface is touched. This ensures the DHCP server properly reclaims the old lease rather than leaving a stale record tied to your previous MAC — improving the chances you receive a genuinely new IP on renewal.

### Results Summary

After completion, the script prints a clear before/after summary:

```
========================================
  Result
========================================
  Interface : eth0
  Old MAC   : aa:bb:cc:dd:ee:ff
  New MAC   : 02:4f:a1:7c:3e:9b
  New IP    : 203.0.113.112/24
========================================
```

---

## Important Notes

| | |
|---|---|
| 🔄 **Temporary only** | Change is lost on reboot. Original hardware MAC is restored automatically. |
| 🔌 **WAN interface** | On the EdgeRouter X, `eth0` is typically the WAN port. Confirm with `show interfaces` in the VyOS CLI before running. |
| 🔒 **Root required** | Must be run with `sudo` — changing MAC and managing DHCP require root privileges. |
| 📋 **Logging** | All actions are logged via `logger` and visible in `/var/log/syslog` under the tag `mac-refresh`. |

---

## Compatibility

Tested on:
- Ubiquiti EdgeRouter X (ER-X) running EdgeOS 2.x

Should work on any EdgeOS device or Debian-based Linux system with `iproute2` installed. On non-EdgeOS systems, replace the `vyatta-dhclient.pl` fallback path if needed.

---

## License

MIT — free to use, modify, and share.

---

*Maintained by [@jermsmit](https://github.com/jermsmit/)*
