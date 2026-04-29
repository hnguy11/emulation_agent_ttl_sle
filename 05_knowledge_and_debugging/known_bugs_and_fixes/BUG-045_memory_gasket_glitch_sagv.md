---
bug_id: BUG-045
title: "Memory gasket glitch during SAGV transitions — intermittent uncacheable read corruption"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "test execution — SAGV power transitions"
bundle: all
category: runtime
related_patterns: [MEMORY_CORRUPTION_SAGV, LPDDR5_GASKET_GLITCH, POWER_TRANSITION_DATA_LOSS]
tags: [sagv, dvfs, memory-gasket, dfi, lpddr5, uncacheable, read-zeros, power-transition, glitch]
phase: "TEST_EXECUTION"
symptoms: "instruction_misalignment uncacheable memory_corruption sagv dvfs power_state lpddr5 gasket read_zeros random_glitch pwrup pwrdwn srx dfi"
keywords: "memory_subsystem power_management voltage_transition data_corruption dfi_interface"
trackers: "lip_tracker_*.annotated.log.gz, lpddr5_xtor_memss*_tracker.log, PyDoh.Sequence.log, cfi_trk.log.gz"
---

# BUG-045: Memory Gasket Glitch During SAGV Transitions

## Symptom

Uncacheable memory reads intermittently return zeros (~50% failure rate) during SAGV power state transitions. CPU may execute instructions at wrong address boundaries or reset unexpectedly.

```
LIP trace: Execution at offset addresses (e.g., 0x4ab4a instead of 0x4ab48)
RDDATA: ~50% reads return 0x00000000, ~50% return valid data
PyDoh.Sequence.log: DVFSQ toggle events during corruption window
```

Found in: `lip_tracker_*.annotated.log.gz`, `lpddr5_xtor_memss*_tracker.log`

## Triggered By

Tests with SAGV/DVFS transitions active (e.g., `coh_hello_vtc`, tests in `msc4_SAGV.list`) where uncacheable memory regions are accessed during rapid power state cycling.

## Root Cause

Hardware bug in the memory gasket/DFI layer between cache fabric and LPDDR5 controller. During rapid power state transitions (PWRUP → SRX → PWRDWN → PWRUP within ~600ns), the gasket experiences timing violations causing:
- Data retention loss during Self-Refresh Exit (SRX)
- Signal timing misalignment on DFI interface
- Race conditions between power state signals and data valid signals

**Only uncacheable (UC) accesses are affected** — cached reads bypass the gasket and hold valid data. The glitch window is narrow (~50-100ns around power transitions).

## Fix / Solution

```bash
# Workaround: Disable SAGV to prevent triggering transitions
export SAGV_DISABLE=1
# Or in test config (vars.env / test_cfg/*.cfg):
# QCLK_GV := 0
# SAGV_ENABLE := 0

# Debug: Verify SAGV correlation
zsh -lc 'grep -i "dvfsq\|sagv\|gear" PyDoh.Sequence.log | head -20'

# Debug: Check ~50% zero reads (hallmark of this bug)
zsh -lc 'zcat lpddr5_xtor_memss0_ch0_tracker.log | grep RDDATA | awk "{print \$NF}" | sort | uniq -c'

# Debug: Confirm uncacheable path (no CFI transactions = UC)
zsh -lc "zgrep '<corrupt_addr>' cfi_trk.log.gz | head -5"
```

**Long-term fix:** RTL fix in memory gasket — file HW bug with power transition timeline evidence.

## Files Affected

- No code fix — hardware/RTL bug in memory gasket DFI layer

## Verification

```bash
# With SAGV disabled, test should complete without memory corruption
zsh -lc 'grep -i "sagv.*disable\|qclk.*disable" emurun.log'
# Verify no more intermittent zero reads
zsh -lc 'zcat lpddr5_xtor_memss0_ch0_tracker.log | grep RDDATA | grep "0x00000000$" | wc -l'
```

## Notes

- **Key differentiator:** ~50% reads return zeros (random glitch), NOT 100% (that's a timing parameter issue)
- Same address returns different data on different reads — timing-dependent, not address-specific
- Correlate failure timestamp with SAGV events in PyDoh.Sequence.log (must be within ±10ms)
- Rapid power cycling gaps < 100ns are suspicious — document for RTL team
- Do NOT confuse with LPDDR5 write latency timing (systematic 100% corruption)
