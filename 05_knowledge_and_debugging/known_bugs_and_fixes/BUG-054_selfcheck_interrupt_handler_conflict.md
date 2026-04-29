---
bug_id: BUG-054
title: "Selfcheck interrupt count failure due to handler registration conflict"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "Test execution — IPI interrupt validation"
bundle: all
category: test
related_patterns: [pattern_handler_conflict, pattern_ipi_mismatch]
tags: [selfcheck, interrupt, IPI, handler, conflict, vector, IDT, 0xdead, VTD, StaticInterrupt, registration]
phase: "TEST_EXECUTION"
symptoms: "selfcheck interrupt count ipi handler mismatch vector 0xdead ebx halted sent received registration conflict error"
keywords: "test_validation interrupt_handler ipi_delivery apic vector_conflict handler_override maestro"
trackers: "test_end_checker, SelfCheck, SELFCHECK_INTERRUPT_COUNT, uop_log_*.log.gz, perspec_test.c.gz"
---

# BUG-054: Selfcheck Interrupt Count Failure — Handler Registration Conflict

## Symptom

Core halts with EBX=0x0000dead. Test reports IPI count mismatch — IPIs sent does not equal IPIs handled for a specific vector. ~70% of selfcheck interrupt count failures show this pattern.

```
[IPI_handler] ERROR: number of ipi's sent is not equal to ipi's handled for vector 102
Total ipi with vector 102 reached handler=0x00000000; Total ipi sent= 0x00000001; ratio=0x00000000
```

DDT bucket: `pkg_emu::Emu::test_end_checker::SelfCheck`

## Triggered By

Tests with multiple interrupt handlers registered to the same IDT vector (e.g., auto-generated VTD MSI handler + manual IPI test handler both targeting vector 102).

## Root Cause

Multiple interrupt handlers are registered to the same vector in the IDT. Only ONE handler executes when an interrupt arrives. If the executing handler does not increment the test's IPI counter (`g_actual_ipi_ctr[vector]`), the self-check validation fails.

**Common scenario:** VTD auto-generates `VTD_MsiHandler_auto_102()` (no counter increment) which overrides `gen0x66_handler()` (has counter increment) for vector 102. IPI delivered → VTD handler runs → counter stays 0 → test fails.

## Fix / Solution

```bash
# Step 1: Find failing core and EBX=0xDEAD
log_scanner search -i "ebx.*0x0000dead" emurun.log.gz | tail -5

# Step 2: Find mismatch vector in uop_log (NOTE: A0C3 → A2C3 mapping)
log_scanner search "number of ipi.*sent is not equal" uop_log_*.log.gz

# Step 3: Search for multiple handlers on that vector
VECTOR_DEC=102
VECTOR_HEX=0x66
log_scanner multi "StaticInterrupt.*${VECTOR_HEX}|||VTD_MsiHandler_auto_${VECTOR_DEC}|||MAESTRO_INTERRUPT void gen${VECTOR_HEX}" perspec_test.c*

# Step 4: Verify which handler increments counter
# Look for g_actual_ipi_ctr[N]++ in each handler body
```

**Resolution options:**
1. Remove redundant handler (typically the auto-generated VTD one)
2. Adjust vector range constraints to avoid conflicts
3. If test name contains "several_handlers" — this is a validation test; failure is expected behavior

## Files Affected

- `perspec_test.c.gz` — Handler definitions and IDT registrations
- `uop_log_*.log.gz` — Runtime IPI error messages

## Verification

```bash
# After removing conflicting handler, verify no 0xDEAD halt
log_scanner search -i "ebx.*0x0000dead" emurun.log.gz
# Should show no results
```

## Notes

- Core ID mapping: A0C3 in error → A2C3 in uop_log filename
- Convert vector decimal to hex when searching (102 = 0x66)
- `StaticInterrupt` registration is NOT duplication — it registers the handler defined above it
- If test name includes "several_handlers_same_vector" → expected failure (validation test)
- Check BOTH handler definition AND counter increment logic

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: selfcheck interrupt count ipi handler mismatch vector 0xdead ebx halted registration conflict
- **Keywords**: test_validation interrupt_handler ipi_delivery vector_conflict handler_override
- **Trackers**: test_end_checker, uop_log_*.log.gz, perspec_test.c.gz, emurun.log.gz
