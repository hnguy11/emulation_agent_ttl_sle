---
bug_id: BUG-041
title: "Protocol not implemented in emulation model — boot hang from config-model mismatch"
date_discovered: 2026-04-29
status: informational
severity: blocker
stage: "boot / runtime"
bundle: all
category: runtime
related_patterns: []
tags: [protocol, model, emulation, boot_hang, configuration, mismatch, unsupported, bfm, timeout, d2d, ucie, cfi]
phase: "RUNTIME"
symptoms: "boot hang protocol timeout configuration model bfm unsupported d2d ucie cfi security handshake fsm stuck 0x36"
keywords: "emulation_model protocol_support configuration_mismatch feature_not_implemented"
trackers: "boot_fsm.log.gz, waitings.log, iosf_sb_jem_tracker.log.gz, SBLinkBfm.log, emurun.log, logbook.log"
---

# BUG-041: Protocol Not Implemented in Emulation Model — Config-Model Mismatch

## Symptom

Boot FSM hangs in a protocol handshake state. Transaction trackers show one-way communication (request without response). BFM logs show "unsupported" or "ignored" message warnings:

```
boot_fsm.log.gz:
  Boot FSM stuck at protocol-dependent state (e.g., 0x36: SECURE_LINK)
  No state transitions for 60M+ cycles

SBLinkBfm.log:
  Subopcode 0xNN currently ignored/unsupported

iosf_sb_jem_tracker.log.gz:
  >100K ps gap between last transaction and hang time
```

## Triggered By

```bash
# Configuration enables protocol feature not supported by emulation model variant
# Example: CFI_UPI=1 on compute-only model (c204ur_ave_model_compute0_zse5)
```

## Root Cause

Configuration parameters enable features (e.g., `CFI_UPI=1`, `UPI_SECURE=1`, `CXL_AUTH=1`) that are not implemented in the selected emulation model variant. The pattern is:

1. Configuration enables protocol → Boot FSM adds protocol state
2. Hardware sends protocol request (e.g., IP_READY to PUNIT)
3. Firmware/handler **missing** in model → No response generated
4. Protocol times out or hangs indefinitely

Common scenarios: CFI security handshakes, D2D link establishment, UCIE initialization, CXL authentication, advanced P-states on reduced models.

## Fix / Solution

```bash
# Step 1: Identify the stuck state
log_scanner tail -n 100 boot_fsm.log.gz

# Step 2: Check what test is waiting for
log_scanner multi -i "link|||secure|||ready" waitings.log

# Step 3: Find configuration parameter enabling the feature
log_scanner multi "CFI_UPI|||SECURE|||PROTOCOL" logbook.log
grep -i "cfi\|upi\|secure\|protocol" vars.env

# Step 4: Check BFM for unsupported warnings
grep -i "unsupported\|ignored\|not implemented" *Bfm.log

# Step 5: Disable the unsupported feature
# Example: Set CFI_UPI=0 in vars.env or test_cfg/systeminit.dut_cfg
```

## Files Affected

- Test configuration (`vars.env`, `test_cfg/systeminit.dut_cfg`) — feature enable parameters
- Simics init scripts (`*.simics`) — protocol initialization
- Testbench forces files (`*forces*.sv`) — may have `ifndef EMULATION` guards

## Verification

```bash
# After disabling unsupported feature, verify boot completes
log_scanner tail -n 20 boot_fsm.log.gz
# Should show boot progressing past previously-stuck state
```

## Notes

- **Decision tree:** Is protocol request sent? → Is response received? → Are there BFM "unsupported" warnings? → Are there firmware patches? → If no: **Missing Implementation**
- Timing gap >100K ps between last transaction and hang = definitive protocol deadlock (not timing issue)
- Check `minibios_extensions/` and `emu/patches/` for existing firmware patches before filing bugs
- Model variant names often indicate capability: `compute0` = compute-only, may lack full protocol support
- Always check testbench forces for `ifndef EMULATION` guards that disable protocol handling in emulation mode
