---
bug_id: BUG-035
title: "Mailbox Timeout (0xdead) — Pcode Never Saw Request via GT P24C/Driver Interface"
date_discovered: 2026-04-29
status: informational
severity: blocker
stage: "Test execution — mailbox request/response phase"
bundle: all
category: runtime
related_patterns: [pattern_mailbox_timeout, pattern_pcode_communication]
tags: [mailbox, pcode, timeout, 0xdead, gt_driver, p24c, tap, bios, firmware]
phase: "TEST_EXECUTION"
symptoms: "mailbox timeout pcode 0xdead EBX dead request response hang communication p24c gt_driver halted"
keywords: "firmware_communication pcode_mailbox interface_timeout hardware_path register_write"
trackers: "pcode_jem_tracker.annotated.log.gz, testbench.log, PyDoh.Agent.log, uop_log_*.log"
---

# BUG-035: Mailbox Timeout (0xdead) — Pcode Never Saw Request

## Symptom

Core halts with `EBX=0xdead` indicating mailbox timeout. Pcode did not read or respond to the mailbox request within the polling window.

```
LPA0C0 halted at 12306659120 ps with EBX=0xdead
```

Found in: `testbench.log`, `uop_log_*.log`, `emurun.log`

## Triggered By

Any test exercising pcode mailbox communication (GT_Driver, P24C, TAP, BIOS, dcode2pcode). Example test: `gtpm_basic_gtdriver2pcode_mailbox`.

## Root Cause

Three possible failure modes — the key question is **"Did the request reach pcode?"**:

1. **Test configuration error** — test framework symbolic constant (e.g., `SEND_PCODE_P24C_MAILBOX=42911`) not mapped to actual register writes; pcode never sees the request bit in `fastpath_mailboxes`.
2. **Hardware path broken** — mailbox interface clock/power gated or not present in this configuration; IO writes never arrive at pcode.
3. **Pcode scheduling delay** — pcode saw request too late (after software timeout); scheduler busy with higher-priority tasks (ThermalDRAM, etc.).

## Fix / Solution

**Determine which mode applies:**

```bash
# 1. Check if pcode ever saw the mailbox request
log_scanner search "fastpath_mailboxes" pcode_jem_tracker.annotated.log.gz

# 2. Check for your specific mailbox bit (e.g., GT P24C = bit 5)
log_scanner search "gt_p24c_req:0x1" pcode_jem_tracker.annotated.log.gz

# 3. Check pcode activity at failure time
log_scanner head -n 99999 pcode_jem_tracker.annotated.log.gz | awk '/^\[123[0-9]{8}\]/' | grep STACK | head -20

# 4. Check IO writes around failure time
log_scanner head -n 99999 pcode_jem_tracker.annotated.log.gz | awk '/^\[12300[0-9]{6}\]/,/^\[12310[0-9]{6}\]/' | grep "IOWR"
```

**Fixes by root cause:**
- **Config error**: Update test framework register mappings or use correct mailbox type
- **HW path**: Enable clock/power for mailbox interface, or use an available mailbox
- **Scheduling**: Increase mailbox polling frequency, raise mailbox task priority, or increase test timeout

## Files Affected

- `pcode_jem_tracker.annotated.log.gz` — pcode execution trace (ground truth for mailbox requests)
- `content/perspec_tests/*/perspec_scenario_*.json.gz` — test scenario config
- `content/perspec_tests/*/perspec_test.c.gz` — test source with mailbox constants

## Verification

```bash
# Confirm pcode sees the mailbox bit after fix
log_scanner search "fastpath_mailboxes" pcode_jem_tracker.annotated.log.gz | grep "<your_mailbox>_req:0x1"

# Confirm no 0xdead timeout
log_scanner multi -i "0xdead|||timeout" testbench.log
```

## Notes

- **Mailbox bit reference:** peci=bit0, tap=bit1, gt_driver=bit2, bios=bit4, gt_p24c=bit5, dcode2pcode=bit9
- Waveform trace window may not cover failure time (e.g., trace starts at 4983μs but failure at 12.3μs) — verify coverage first
- `fastpath_mailboxes` register is the single source of truth for pending requests
- Time to root cause: 20–45 minutes with pcode JEM tracker logs

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: mailbox timeout pcode 0xdead EBX dead request hang communication halted
- **Keywords**: firmware_communication pcode_mailbox interface_timeout hardware_path
- **Trackers**: pcode_jem_tracker.annotated.log.gz, testbench.log, uop_log_*.log
