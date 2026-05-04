# mac-refresh

Interactive Bash script for the Ubiquiti EdgeRouter X. Releases your DHCP lease, changes the MAC address on `eth0`, and renews the lease. All temporary -- nothing survives a reboot.

---

## Use Cases

MAC-based lease tracking is common on ISP equipment. When the DHCP server ties a lease to your hardware address, you tend to get the same IP back no matter how many times you release and renew. Changing the MAC breaks that association and forces the server to treat your device as new.

Other reasons to use this:

- Get a fresh IP when your ISP or upstream router is handing back the same lease from cache
- Troubleshoot whether a block, filter, or conflict is tied to the hardware address
- Test network behavior with a different device identity without swapping hardware
- Recover connectivity after a hardware swap when the ISP has the old MAC on file

**The change is temporary.** Rebooting the router restores the original burned-in MAC. No config files are touched.

---

## Requirements

- Ubiquiti EdgeRouter X running EdgeOS (VyOS-based)
- `sudo` access via SSH or the Web GUI terminal
- `ip` and `dhclient` or `dhcpcd` -- both included in EdgeOS by default

---

## Installation

Copy the script to your router from your local machine:

```bash
scp mac-refresh.sh admin@192.168.1.1:/home/admin/
```

SSH in and make it executable:

```bash
ssh admin@192.168.1.1
chmod +x mac-refresh.sh
```

---

## Usage

```bash
sudo ./mac-refresh.sh
```

The script is menu-driven. No flags, no arguments needed.

---

## How It Works

On launch, the script displays the current interface state and presents three options:

```
========================================
   MAC Address Refresh  -  EdgeRouter X
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

**Option 1** generates a locally-administered unicast MAC (prefix `02:xx:...`). This format is specifically reserved for software-assigned addresses and will not conflict with any real hardware OUI.

**Option 2** lets you specify a MAC manually. The input is validated before anything runs -- a bad format drops you back to the menu cleanly.

Before applying any change, the script shows a confirmation prompt with the old and new MAC side by side:

```
  +-----------------------------------------+
  |  Ready to apply changes                  |
  +-----------------------------------------+
  |  Interface : eth0                        |
  |  Old MAC   : aa:bb:cc:dd:ee:ff           |
  |  New MAC   : 02:4f:a1:7c:3e:9b           |
  +-----------------------------------------+

  NOTE: This is a TEMPORARY change (lost on reboot)

  Proceed? [y/N]:
```

### Execution Order

| Step | Action |
|------|--------|
| 1 | Release DHCP lease (`dhclient -r eth0`) |
| 2 | Bring `eth0` down |
| 3 | Apply new MAC address |
| 4 | Bring `eth0` back up |
| 5 | Request new DHCP lease |

The release runs first, before the interface goes down. This gives the DHCP server a proper teardown so it can reclaim the lease cleanly rather than leaving a stale record associated with the old MAC.

### Output

After the process completes, the script prints a before/after summary:

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

## Notes

**eth0 is the WAN port** on the EdgeRouter X. Verify your interface assignments with `show interfaces` in the VyOS CLI before running.

**Root is required.** Run with `sudo`. The script will exit early with an error if it detects it is not running as root.

**Logging.** Every action is passed to `logger` and will show up in `/var/log/syslog` under the tag `mac-refresh`.

**Compatibility.** Tested on EdgeOS 2.x. Should work on any Debian-based system with `iproute2`. On non-EdgeOS systems the `vyatta-dhclient.pl` fallback path can be ignored or removed.

---

## License

MIT

---

Maintained by [@jermsmit](https://github.com/jermsmit/)
