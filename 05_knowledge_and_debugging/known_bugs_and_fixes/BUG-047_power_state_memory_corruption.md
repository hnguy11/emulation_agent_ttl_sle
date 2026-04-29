---
bug_id: BUG-047
title: "Address translation failure during SAGV/DVFS transitions — #UD exception at valid instructions"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "test execution — DVFS frequency transition"
bundle: all
category: runtime
related_patterns: [PKG__PKG_PSTATE__MEMSS_P-state_Timeout_failure__W4_Ratio]
tags: [sagv, dvfs, address-translation, undefined-opcode, memss-timeout, w4-ratio, frequency-transition, pstate]
phase: "TEST_EXECUTION"
symptoms: "memory corruption power_state pstate sagv dvfs frequency transition undefined_opcode exception address_translation timeout w4_ratio"
keywords: "power_management address_translation timing_mismatch frequency_change"
trackers: "logbook.log, uop_log_*.log, PyDoh.Sequence.log, memdump_*.obj, lpddr5_xtor_memss*_tracker.log, ddt_all_buckets.log"
---

# BUG-047: Power State Memory Corruption — Address Translation Failure

## Symptom

CPU throws #UD (Undefined Opcode, vector=6) exception at valid instructions after SAGV/DVFS frequency transition. MEMSS P-state timeout in W4_Ratio state.

```
ERROR: Exiting due to Exception: UnDefined Opcode, vector=6
RIP: 0x0000000002667042
Signature: PKG__PKG_PSTATE__MEMSS_P-state_Timeout_failure__W4_Ratio
```

Found in: `uop_log_*.log`, `logbook.log`, `ddt_all_buckets.log`

## Triggered By

Tests with SAGV/DVFS transitions (e.g., `qclk_gv_cycle_selfcheck`). The CPU exception occurs 1-5 seconds after the frequency transition, indicating delayed system instability.

## Root Cause

**Address translation failure due to timing parameter mismatch** between memory controller (updated to new frequency) and TLB/I-cache (still using old frequency parameters). The CPU fetches valid instructions from the wrong physical address, producing #UD on valid x86-64 code.

**Key timeline pattern:**
- DVFSQ toggle and MEMSS timeout occur at the SAME timestamp (strong causal link)
- CPU exception follows 3-4 seconds later (delayed instability)
- Memory transactions themselves are CLEAN — no data corruption, this is an instruction fetch address translation issue

**This is NOT DFI signal timing** — memory data is correct; the problem is the address used to fetch it.

## Fix / Solution

```bash
# 1. Check DDT buckets for MEMSS P-state timeout
cat ddt_all_buckets.log | grep -i "MEMSS\|W4_Ratio\|SelfCheck"

# 2. Find CPU exception and RIP
grep "Exiting due to Exception:" uop_log_*.log
grep "RIP:" uop_log_*.log

# 3. Correlate DVFSQ timing with MEMSS timeout
grep -i "dvfsq" PyDoh.Sequence.log | awk '{print $1}'
grep -i "memss.*timeout\|W4_Ratio" logbook.log

# 4. Verify memory transactions are clean (rules out data corruption)
log_scanner multi -i "error|||corrupt|||mismatch" lpddr5_xtor_memss*_tracker.log.gz | head -10

# 5. Verify valid instructions at crash address (confirms address translation, not bit flip)
# Memory dump should show valid x86-64 instructions at RIP
ls -lh memdump_*.obj
```

**Fixes:**
- **Workaround (emulation):** Increase W4_Ratio timeout (32M → 60M cycles) — reduces timeout failures but CPU exception persists
- **Permanent fix:** Fix SAGV synchronization to ensure TLB/I-cache parameters update atomically with frequency change

## Files Affected

- No code fix — hardware SAGV synchronization bug

## Verification

```bash
# After SAGV sync fix: no exceptions, no timeouts
grep "FAIL\|PASS" logbook.log | tail -1      # Expected: PASS
grep "Exception:" uop_log_*.log | wc -l       # Expected: 0
grep "MEMSS.*timeout" logbook.log | wc -l      # Expected: 0
```

## Notes

- 90-95% likely to reproduce on silicon — this is a FUNCTIONAL issue, not emulation-only
- Do NOT just increase timeout without fixing root cause — CPU exception will still occur
- Do NOT confuse with DFI signal timing issues — check memory transaction logs first (should be clean)
- DVFSQ toggle simultaneous with MEMSS timeout is the strongest evidence
- Known crash address 0x02667042 documented in qclk_gv_cycle_selfcheck tests
