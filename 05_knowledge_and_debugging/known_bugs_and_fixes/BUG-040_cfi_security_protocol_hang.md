---
bug_id: BUG-040
title: "CFI security protocol boot hang — emulation guards disable testbench forces"
date_discovered: 2026-04-29
status: informational
severity: blocker
stage: "boot / runtime"
bundle: all
category: runtime
related_patterns: []
tags: [cfi, security, protocol, boot_hang, emulation, guards, ucie, sideband, deadlock, forces, sb_link]
phase: "RUNTIME"
symptoms: "cfi security protocol boot hang sb_link secure fsm bfm unsupported ucie sideband deadlock 0x36 SB_link_is_secured"
keywords: "boot_fsm security_handshake cfi_protocol emulation testbench_forces"
trackers: "boot_fsm.log.gz, waitings.log, iosf_sb_jem_tracker.log.gz, SBLinkBfm.log, emurun.log"
---

# BUG-040: CFI Security Protocol Boot Hang — Emulation Guards Disable Forces

## Symptom

Boot FSM stuck at state 0x36 (`BOOT_FSM_SB_LINK_SECURE_AND_OPEN`) when `CFI_UPI=1` in emulation mode:

```
boot_fsm.log.gz:
  1399445 ps: BOOT_FSM_SB_LINK_SECURE_AND_OPEN (0x36)
  [No further transitions for 60M cycles]

waitings.log:
  ID:33 waiting for SB_link_is_secured==1 (started 1395377 ps)

SBLinkBfm.log:
  Time 1256958 ps: Subopcode 0x90 currently ignored/unsupported
```

## Triggered By

```bash
# Test with CFI_UPI=1 on emulation platform (e.g., compute-only model)
# push_pop_ss.max or similar boot test with CFI security enabled
```

## Root Cause

Testbench forces for CFI security protocol in `soc_ucie_bring_up_forces.sv` (lines 26-75) are disabled in EMULATION mode via ``ifndef EMULATION`` preprocessor guards. The EMULATION version (lines 76-100) only provides simple loopback — no security protocol handling. When `CFI_UPI=1`, the boot FSM enters state 0x36 expecting a security handshake that the testbench never completes, causing a protocol deadlock.

**Evidence chain:** PUNIT receives IP_READY → BFM marks subopcode 0x90 unsupported → no response generated → `SB_link_is_secured` stuck at 0 → boot hangs.

## Fix / Solution

**Option 1 (Recommended): Disable CFI security protocol**
```bash
# Set CFI_UPI=0 in test configuration
grep -i "CFI_UPI" vars.env test_cfg/systeminit.dut_cfg
# Change CFI_UPI=1 → CFI_UPI=0
```

**Option 2: Add security forces to EMULATION section of soc_ucie_bring_up_forces.sv**

```bash
# Debug commands to confirm this is the issue:
log_scanner search -A 2 "0x36" boot_fsm.log.gz
log_scanner multi -i "link|||secure" waitings.log
log_scanner multi -i "subopcode|||unsupported" SBLinkBfm.log
grep -n "ifndef EMULATION" soc_ucie_bring_up_forces.sv
```

## Files Affected

- `soc_ucie_bring_up_forces.sv` — CFI security forces guarded by `ifndef EMULATION`
- `verif/tb/soc_d2d_tb.sv` — includes forces file (line 537, no EMULATION guard at include site)
- Test configuration (`vars.env`, `systeminit.dut_cfg`) — `CFI_UPI` parameter

## Verification

```bash
# After setting CFI_UPI=0, verify boot progresses past state 0x36
log_scanner search "0x36" boot_fsm.log.gz
# Should show state 0x36 is either skipped or quickly transitions
```

## Notes

- The forces file IS included in emulation but forces INSIDE the file don't execute due to `ifndef EMULATION` guards
- Absence of `$display` messages in emurun.log ("Compute side UCI_CFI_PMA to PUNIT IP ready is seen") confirms forces not executing
- 143K ps gap between last sideband transaction and hang confirms protocol deadlock, not timing issue
- Compute-only model variants lack PUNIT firmware handler for CFI security (subopcode 0x90)
