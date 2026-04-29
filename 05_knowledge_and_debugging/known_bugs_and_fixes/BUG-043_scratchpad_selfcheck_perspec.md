---
bug_id: BUG-043
title: "Scratchpad selfcheck failure — Perspec constraint tautology generates random addresses"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "runtime / test execution"
bundle: all
category: runtime
related_patterns: []
tags: [scratchpad, selfcheck, perspec, constraint, tautology, random_address, base_addr, 0xdead, fcf, sncu, mmio, offset_selector]
phase: "RUNTIME"
symptoms: "scratchpad self-check failure EBX 0xDEAD halt value mismatch 0xFFFFFFFF random base_addr WRITE_FAIL doorbell cores halted"
keywords: "access_scratchpads perspec constraint tautology base_addr untrusted_offset random_address"
trackers: "uop_log_*.log.gz, perspec_test.c.gz, fcf_operation.sln"
---

# BUG-043: Scratchpad Selfcheck Failure — Perspec Constraint Tautology

## Symptom

Coherency/FLR test fails with all cores halting (`EBX=0xDEAD`). Scratchpad write-then-read self-check returns `0xFFFFFFFF`. Base addresses are random 64-bit numbers instead of valid BAR addresses:

```
uop_log:
  [Access Sctatchpads] Base Addr: 0x2980df63bc63c58e  Access Offset: 0x30
  [Access Sctatchpads] Prev Value: 18446744073709551615  Writing Value: ...
  Error: value read from scratchpad in addr: ... not match expected value
```

Valid addresses should be `0x40000000` (SNCU BAR) or `0x385E310000` (CNCU BAR), not random 64-bit values.

## Triggered By

```bash
# Any test using access_scratchpads action from fcf model on PTL or LNL/WCL
# Bug is seed-dependent: triggers when constraint solver picks offset_selector==0
```

## Root Cause

Typo in `perspec/models/fcf/model/fcf_operation.sln` — tautological constraint:

```
# Line ~599 (PTL) and ~605 (LNL):
constraint (offset_selector == 0) => (base_addr == base_addr);  // ❌ TAUTOLOGY (always true)
# Should be:
constraint (offset_selector == 0) => (base_addr == base);       // ✅ Pins to 0x40000000
```

`base_addr == base_addr` is always true, so the constraint solver fills `base_addr` with an arbitrary random 64-bit value. The computed address points to unmapped MMIO space, writes are silently dropped, and reads return `0xFFFFFFFF`.

## Fix / Solution

**Fix in `perspec/models/fcf/model/fcf_operation.sln`:**
```bash
# Verify the bug exists
grep -n "base_addr == base_addr" perspec/models/fcf/model/fcf_operation.sln

# Fix: Change base_addr == base_addr → base_addr == base
# For BOTH PTL (~line 599) and LNL (~line 605)

# After fix, verify
grep -n "offset_selector == 0.*base_addr" perspec/models/fcf/model/fcf_operation.sln
# All lines should show: base_addr == base
```

```bash
# Quick triage commands:
# Step 1: Check for scratchpad errors
zgrep -c "Error.*scratchpad" ect_run/uop_logs/uop_log_*.log.gz

# Step 2: Extract base addresses (look for random 64-bit values)
for f in ect_run/uop_logs/uop_log_*.log.gz; do
    zgrep "Base Addr:" "$f" 2>/dev/null | sed 's/.*Base Addr: //' | awk '{print $1}'
done | sort -u

# Step 3: Check generated test code for random addresses
zcat content/perspec_tests/*/perspec_test.c.gz | grep "addr = " | grep -v "1073741824\|242098438144" | head -10
```

## Files Affected

- `perspec/models/fcf/model/fcf_operation.sln` — tautological constraint on lines ~599 (PTL) and ~605 (LNL)

## Verification

```bash
# After fix, regenerate test and verify addresses
zcat content/perspec_tests/*/perspec_test.c.gz | grep "addr = " | sort -u
# Should only show: addr = 1073741824 + <offset> (0x40000000) or addr = 242098438144 + <offset> (0x385E310000)

# Re-run with same seed, verify no scratchpad errors
zgrep "Error.*scratchpad" ect_run/uop_logs/uop_log_*.log.gz
# Expected: no output
```

## Notes

- **Seed-dependent:** only triggers when constraint solver picks `offset_selector==0`; tests with `is_standalone==FALSE` are immune (constraint forces `offset_selector != 0`)
- Don't confuse with FLR/BAR reconfiguration issues — these random addresses are compile-time constants in generated C code, not runtime BAR problems
- LT doorbell `WRITE_FAIL` errors may co-occur but are a separate issue
- One core's scratchpad failure cascades to all 8 cores via Perspec error mailbox — identify the primary failure by finding earliest error timestamp
- The partial match on some cores (e.g., `0xFFFFFFFFFFFFB8B8`) is coincidental, not a bus width issue
