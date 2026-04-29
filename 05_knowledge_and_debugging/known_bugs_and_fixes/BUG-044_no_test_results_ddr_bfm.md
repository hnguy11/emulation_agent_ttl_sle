---
bug_id: BUG-044
title: "NO TEST RESULTS runtime failure due to DDR BFM read corruption of IDT entries"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "test execution — runtime phase"
bundle: all
category: runtime
related_patterns: [E2E_MEMORY_CORRUPTION, DDR_BFM_READ_ZERO]
tags: [ddr-bfm, memory-corruption, idt, nmi, ipi, e2e-checker, read-zero, runtime-failure]
phase: "TEST_EXECUTION"
symptoms: "NO_TEST_RESULTS runtime failure model_tool IPI NMI IDT corruption memory DDR_BFM read_zero 0x2b020 cacheline E2E soc_e2e_checker halted shutdown error"
keywords: "runtime_failure memory_corruption ddr_bfm_bug interrupt_handling e2e_checker"
trackers: "logbook.log.gz, e2e_result.out.gz, merged_idi.log.gz, cfi_trk.log.gz"
---

# BUG-044: NO TEST RESULTS — DDR BFM Read Corruption of IDT Entries

## Symptom

Test fails during runtime with no results reported. E2E checker finds memory corruption on critical data structures (e.g., IDT entries).

```
WARNING: NO TEST RESULTS REPORTED FROM MODEL TOOL !!!
Model run ... FAIL
Got to end of channel and found no matching write address=00000002b020 data=0000
```

Found in: `logbook.log.gz` and `e2e_result.out.gz`

## Triggered By

Any test that uses interrupt handling (IPI/NMI) where DDR BFM read corruption hits IDT entries or handler pointers during runtime execution.

## Root Cause

DDR BFM read bug returns zeros when reading critical memory structures. The failure chain:
1. DDR BFM silently returns zeros on read for a valid memory address
2. Corrupted address contains IDT entries or handler pointers (e.g., 0x2b020 = NMI handler)
3. CPU reads corrupted IDT, handler never executes, test hangs
4. E2E checker also detects the corruption (secondary symptom)

This is a **READ corruption** — no agent writes bad data. CFI tracker confirms MemData returns zeros from memory controller with no intervening write transactions.

## Fix / Solution

```bash
# 1. Confirm E2E corruption explains the runtime failure
log_scanner search "no matching write" e2e_result.out.gz | head -10

# 2. Correlate corrupted address with test structures (IDT, handlers)
CORRUPT_ADDR=$(log_scanner search "no matching write" e2e_result.out.gz | head -1 | sed 's/.*address=//' | sed 's/ data.*//')
log_scanner search -i "${CORRUPT_ADDR:8}" *.lst.gz | head -10

# 3. Validate via CFI tracker — MemData should show zeros (read bug, not write bug)
log_scanner search "$CORRUPT_ADDR" cfi_trk.log.gz | grep -i "MemData" | head -5

# 4. Rule out write corruption from non-core agents
log_scanner search "$CORRUPT_ADDR" cfi_trk.log.gz | grep -iE 'IOC|GT|MEDIA|DISPLAY' | wc -l
# Expected: 0 (confirms DDR BFM read bug, not agent write corruption)
```

**Escalation:** Report to emulation/DDR BFM team with CFI evidence, corruption timeline, and affected addresses.

## Files Affected

- No code fix — this is a DDR BFM/memory model bug in the emulation infrastructure

## Verification

```bash
# Verify E2E address maps to critical test structure
log_scanner search "no matching write" e2e_result.out.gz | sed 's/.*address=//' | sed 's/ data.*//' | sort -u
# Verify no write transactions from non-core agents on corrupted cacheline
log_scanner search "<cacheline_pattern>" cfi_trk.log.gz | grep -iE 'TRANSMIT_DATA' | wc -l
```

## Notes

- Always check `e2e_result.out.gz` when investigating runtime failures — E2E errors can explain the root cause
- Build a timeline: prove E2E corruption timestamp precedes runtime failure
- ~50% of reads may return valid data (intermittent), making this hard to spot
- This is NOT a test logic bug — memory corruption causes test logic to fail
- Key distinction from agent write corruption: NO write transactions in CFI tracker during corruption window
