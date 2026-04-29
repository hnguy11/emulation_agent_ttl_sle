---
bug_id: BUG-036
title: "Memory Corruption / Address Misalignment During SAGV Frequency Transitions"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "Test execution — SAGV/DVFS gear shift"
bundle: all
category: runtime
related_patterns: [pattern_memory_corruption, pattern_sagv_transition]
tags: [memory, corruption, sagv, dvfs, frequency, address, misalignment, undefined_opcode, exception, gear_shift]
phase: "TEST_EXECUTION"
symptoms: "memory corruption sagv dvfs frequency transition undefined_opcode exception address_misalignment gear_shift read_zero data_mismatch 0x2667 DVFSQ"
keywords: "power_state_transition memory_subsystem timing_violation sagv_event dvfs_correlation"
trackers: "PyDoh.Sequence.log, uop_log_*.log, logbook.log, emurun.log, memdump_*.obj"
---

# BUG-036: Memory Corruption / Address Misalignment During SAGV Frequency Transitions

## Symptom

CPU exception (undefined opcode `#UD`, vector=6) or memory data mismatch occurring within ~50ms after an SAGV/DVFS frequency transition event. Memory reads return valid data from a **wrong address** (systematic offset, e.g., +0x10 bytes).

```
<14783447520> lip:<0x26814d4> [PERSPEC_MAESTRO] ERROR: Exiting due to Exception: UnDefined Opcode, vector=6
```

Typical timeline correlation:
```
14316159500ps - DVFSQ toggle to 1
14320000000ps - Memory corruption observed (40ms later)
14887982333ps - CPU exception (undefined opcode)
```

Found in: `uop_log_*.log`, `logbook.log`, `emurun.log`, `DEBUG` file

## Triggered By

Tests exercising SAGV (System Agent Gear/Voltage) or DVFS transitions during active memory operations. Intermittent — may pass on some runs.

## Root Cause

During frequency transition, address translation becomes corrupted:
- Memory controller operates at **new** frequency
- TLB/I-cache still uses **old** frequency timing parameters
- Virtual→Physical address mapping uses mismatched parameters
- CPU fetches valid instructions from **wrong physical address** → `#UD` exception

**Key diagnostic:** If bytes at crash address decode to valid x86-64 instructions but CPU raises `#UD`, this is an address translation failure, NOT random bit corruption.

**Pattern types:** Fixed offset (+0x10) = cache line logic bug; +0x1000 = TLB/page table issue; random = true corruption.

## Fix / Solution

```bash
# 1. Extract crash address from uop_log
grep "RIP:" uop_log_CDIE0_A2C1.log
grep "Exiting due to Exception" uop_log_*.log

# 2. Correlate with DVFS events
grep -i "dvfsq\|dvfs" PyDoh.Sequence.log | tail -50
grep -i "gvfsm\|sagv\|gear\|voltage" PyDoh.Sequence.log

# 3. Analyze memory dump for offset patterns
# Check if "corrupted" data exists at a nearby address (e.g., +0x10)
# Example: Expected at 0x2667040, actually found at 0x2667050

# 4. Check MEMSS timeout correlation
log_scanner search "PKG_PSTATE_CHECKER" tlm_post/gpc_pkg/replay_execution.log.gz
```

**Classification:**
- **Functional bug** (address corruption, fixed offset): Escalate as **critical silicon bug** — will reproduce on silicon
- **Timing issue** (MEMSS timeout by small margin): May be emulation artifact at 400kHz — verify timeout scaling

## Files Affected

- `PyDoh.Sequence.log` — DVFSQ/SAGV event timeline
- `uop_log_*.log` — per-core execution trace with register dumps and crash address
- `memdump_*ps.*.obj` — memory snapshots at crash time
- `pcode_jem_tracker.annotated.log.gz` — GVFSM activity and MEMSS timeouts

## Verification

```bash
# After fix, confirm no exceptions during SAGV transitions
grep -i "exception\|undefined\|illegal" logbook.log
# Verify SAGV transitions complete successfully
grep "dvfsq" PyDoh.Sequence.log | wc -l
```

## Notes

- **Emulation context:** 400kHz = 5,000–10,000× slower than silicon; timing issues may be artifacts, but address corruption is a functional bug
- Distinguish between **two separate issues** in the same test: timing timeout AND address corruption
- Decode instruction bytes at crash RIP before concluding corruption — valid opcodes + `#UD` = address mismapping
- Memory dumps may be in `.obj` (text hex) or `.obj.craff` (compressed binary) format
- Time to root cause: 30–60 minutes

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: memory corruption sagv dvfs frequency undefined_opcode exception address_misalignment DVFSQ gear_shift
- **Keywords**: power_state_transition memory_subsystem timing_violation sagv_event
- **Trackers**: PyDoh.Sequence.log, uop_log_*.log, logbook.log, emurun.log, memdump_*.obj
