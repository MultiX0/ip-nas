# Hardware measurements

Caliper numbers (mm) taken 2026-10-15 to 2026-10-17 on the real parts. The case model uses these, not datasheet values.

## Drives

| Item | Measured | Spec |
|---|---|---|
| Drive 1 WD3200LPVX (320 GB): length x width | 100.0 x 69.5 | 100 x 69.85 |
| Drive 1 thickness | 6.4 | 7.0 |
| Drive 2 WD1600BEVT (160 GB) thickness | 8.9 | 9.5 |

## UGREEN 20611 (USB 3.0 to SATA, 12 V input)

| Item | Measured |
|---|---|
| Head alone: length (along drive) x width x thickness | 52.3 x 50.0 x 13.1 |
| Drive + head, end to end | 147.8 (head sticks out 47.8; 4.5 overlaps the drive connector) |
| 12 V plug alone (tip to end of rubber, no wire) | 44.0 |
| 12 V plug sticking out behind the head | about 33-34 (barrel 5.5 x 2.1 goes about 10-11 in), plus wire bend |
| USB-A plug at the Pi end (tip to wire) | 39.1 |

## USB hub HAING HI-U302

| Item | Measured |
|---|---|
| Body | 77.0 x 41.4 x 12.1 |
| Ports | 4, on one 77 x 12.1 face |
| Edge to first port / gap between ports | 5.6 / 4.66 |
| Port width (derived) | about 12.96 |
| Cable exit | one short end, near the back face |
| USB-A plug (tip to wire) | 39.4 |
| Wire length, hub to plug | 144 |

## Screen Guition JC3248W535C_I_Y (3.5", capacitive)

| Item | Measured | Official |
|---|---|---|
| Front frame width x height | 94.6 x 61.8 | 94.5 x 62.0 |
| Total thickness | 12.3 | |
| Raised back part | 82.0 x 57.7, sticks out 6.7 | cut-out 82.9 x 58.4 |
| Front frame thickness | 5.6 | |
| Angled USB-C plug behind the back face | 11.1 (screen + plug = 23.4 from the glass) | |

The USB-C port is on the back face, near a short edge. The angled plug lies flat on the back and the cable leaves past the
bottom-right corner (seen from the back).

## Raspberry Pi 5

| Item | Measured | Official |
|---|---|---|
| Pi 5 + Active Cooler, bottom of board to top of fan | 14.2 | 1.6 board + 13.7 cooler = 15.3 (design keeps 15.3) |

## Power tests

| Test | Setup | Result |
|---|---|---|
| Drive 1 idle current (2026-10-15) | Drive 1 on UGREEN head, USB meter in a Pi 5 port, no 12 V | 4.88 V, 0.25 A (label: 5 V 0.55 A); links as UAS |
| Pi power budget | Official 5 A PSU, `usb_max_current_enable=1` | 1.6 A shared USB budget |
| One drive spin-up, Pi power only | Each drive alone from standby | about 2 s, no errors |
| Two drives spin-up together, Pi power only (5 + 5 runs) | No 12 V | **FAIL**: drive 2 hangs 30 s every time, recovers only after a USB reset. 5 V input stayed at 5.01 V or more, not throttled |
| Two drives spin-up together, 12 V plugged into both heads (5 runs) | Both on USB 3 (5000M) | **PASS**: about 2.0 s each, 0 resets, 0 errors, lowest 5 V input 5.016 V, not throttled |

Result: **the 12 V adapter is required for two drives.** Pi-only power (case option C) was dropped; the case uses
straight 12 V plugs (option A, about 209 mm tall).

A drive that links at 480M (USB 2) in a blue port usually has a badly seated plug, or a USB meter in line.

## Drive health (SMART)

| | HDD1 WD3200LPVX | HDD2 WD1600BEVT |
|---|---|---|
| Overall | PASSED | PASSED |
| Reallocated sectors | 0 | **255 raw** (normalised 178, threshold 140) |
| Reallocated events | 0 | 4 |
| Pending / offline uncorrectable | 0 / 0 | 0 / 0 |
| UDMA CRC errors | 0 | 1 |
| Power-on hours | 6913 | 2958 |
| Other (HDD1) | Power cycles 3338, start/stop 5547, load cycles 85130, G-sense 98, no errors logged, last short test OK | |
| Temperature | 28-31 C | 35 C |
| Format | GPT, one ext4 partition labelled HDD1, 293 GB free | GPT, one ext4 partition labelled HDD2, 146 GB free |

[pi/README.md](../pi/README.md) formats them, mounts them from `/etc/fstab` by UUID at `/DATA/HDD1` and `/DATA/HDD2`,
and makes the folders the apps use.

**HDD2 has reallocated sectors: use it for copies and backups, never as the only copy of anything.**
Check its long self-test with `sudo smartctl -d sat -l selftest /dev/sdb`.
