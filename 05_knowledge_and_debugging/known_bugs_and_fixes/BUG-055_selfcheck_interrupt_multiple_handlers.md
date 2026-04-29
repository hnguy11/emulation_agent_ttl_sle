---
bug_id: BUG-055
title: "Selfcheck interrupt count failure with multiple handlers on same vector"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "Test execution — IPI self-check validation"
bundle: all
category: test
related_patterns: [pattern_multiple_handlers, pattern_ipi_count]
tags: [selfcheck, interrupt, IPI, handler, multiple, vector, IDT, 0xdead, VTD, counter, mismatch]
phase: "TEST_EXECUTION"
symptoms: "selfcheck self_check interrupt count IPI handler mismatch vector multiple several 0xdead EBX halted test_end_checker"
keywords: "interrupt_handler IPI vector_registration test_validation duplicate_handler counter_mismatch selfcheck"
trackers: "test_end_checker, SelfCheck, SELFCHECK_INTERRUPT_COUNT, INTERRUPT_HANDLER_MISMATCH, uop_log_*.log.gz"
---

# BUG-055: Selfcheck Interrupt Count — Multiple Handlers Same Vector

## Symptom

Test self-check detects that IPIs sent to a vector don't match IPIs counted by handlers. Core halts with EBX=0xDEAD. Common in tests registering multiple interrupt handlers.

```
[IPI_handler] ERROR: number of ipi's sent is not equal to ipi's handled for vector 102
Total ipi with vector 102 reached handler=0x00000000; Total ipi sent= 0x00000001; ratio=0x00000000
```

DDT bucket: `pkg_emu::Emu::test_end_checker::SelfCheck`

## Triggered By

Tests where auto-generated VTD handlers conflict with manually-defined handlers, or tests using both INTERRUPT and MAESTRO_INTERRUPT macros for the same vector, or multiple scenarios registering handlers to overlapping vector ranges.

## Root Cause

When multiple interrupt handlers are registered for the same IDT vector, only ONE handler executes per interrupt. If the executing handler does NOT increment the test counter (`g_actual_ipi_ctr[vector]`), the count validation fails.

**Typical conflict:**
- `VTD_MsiHandler_auto_102()` — auto-generated, does NOT increment counter
- `gen0x66_handler()` — manual, DOES increment `g_actual_ipi_ctr[102]++`
- Only one executes → counter = 0 → sent ≠ handled → FAIL

## Fix / Solution

```bash
# Step 1: Find failing core (EBX=0xDEAD)
log_scanner search -i 'real error.*halted.*0x0000dead' emurun.log* | tail -5

# Step 2: Find vector mismatch (NOTE: core ID A0C3 → A2C3 in filename)
log_scanner search -i 'IPI_handler.*ERROR' uop_log_CDIE0_A2C3.log.gz

# Step 3: Find all handlers for the failing vector
VECTOR_DEC=102; VECTOR_HEX=0x66
log_scanner multi "StaticInterrupt.*gen${VECTOR_HEX}_hndlr|||INTERRUPT void VTD_MsiHandler_auto_${VECTOR_DEC}|||MAESTRO_INTERRUPT void gen${VECTOR_HEX}" perspec_test.c*

# Step 4: Check which handlers increment counter
# Extract each handler body, look for g_actual_ipi_ctr[N]++

# Step 5: Check test intent — "several_handlers" = validation test (expected failure)
basename $(pwd)
```

**Resolution options:**
1. **Real bug:** Remove redundant handler or exclude conflicting vectors via constraint
2. **Both count:** Fix IDT registration order to ensure counter-handler wins
3. **Validation test:** No fix needed — failure confirms self-check mechanism works

## Files Affected

- `perspec_test.c.gz` — Handler definitions and registrations
- `uop_log_*.log.gz` — Runtime error messages with vector/count details

## Verification

```bash
# Verify count matches after fix
log_scanner search "IPI_handler.*ERROR" uop_log_*.log.gz
# Should show no results
```

## Notes

- ~70% of selfcheck interrupt count failures are caused by multiple handlers
- Average time to root cause: 3-10 minutes
- If test name includes "several_handlers_same_vector" → failure is expected behavior (validation test)
- Always convert vector decimal↔hex when searching (102 = 0x66)
- Core ID mapping varies: A0C3 in emurun → A2C3 in uop_log filename
- Related: BUG-054 (handler registration conflict — same mechanism, different test pattern)

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: selfcheck interrupt count IPI handler mismatch vector multiple 0xdead EBX halted
- **Keywords**: interrupt_handler IPI vector_registration duplicate_handler counter_mismatch
- **Trackers**: test_end_checker, SelfCheck, uop_log_*.log.gz, perspec_test.c.gz
