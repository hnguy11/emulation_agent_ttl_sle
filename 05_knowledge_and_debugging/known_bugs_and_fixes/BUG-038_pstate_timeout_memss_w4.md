---
bug_id: BUG-038
title: "P-State Timeout — MEMSS W4 Ratio Transition Failure (NVLAX)"
date_discovered: 2026-04-29
status: informational
severity: blocker
stage: "Test execution — P-state / frequency transition"
bundle: all
category: runtime
related_patterns: [pattern_pstate_timeout, pattern_memss_w4_ratio]
tags: [pstate, timeout, memss, w4_ratio, frequency, transition, nvlax, stepping, power_state]
phase: "TEST_EXECUTION"
symptoms: "pstate timeout memss w4_ratio transition nvlax stepping frequency power_state PKG_PSTATE MEMSS_P-state_Timeout"
keywords: "power_state_transition platform_specific memss_timeout w4_ratio"
trackers: "logbook.log, PyDoh.Sequence.log, pcode_jem_tracker.annotated.log.gz"
---

# BUG-038: P-State Timeout — MEMSS W4 Ratio Transition Failure (NVLAX)

## Symptom

MEMSS P-state timeout during W4 ratio frequency transition. Power state checker reports timeout failure.

```
PKG__PKG_PSTATE__MEMSS_P-state_Timeout_failure__W4_Ratio
```

Found in: `logbook.log`, `PyDoh.Sequence.log`

## Triggered By

P-state frequency transition tests on NVLAX platform, particularly during W4 ratio changes. Behavior may differ between A0 and B0 steppings.

## Root Cause

MEMSS (Memory Subsystem) fails to complete P-state transition within the expected timeout window. The W4 ratio frequency change triggers a transition sequence that stalls or exceeds the configured timeout threshold. NVLAX platform-specific configurations and stepping differences (A0 vs B0) affect transition timing.

## Fix / Solution

```bash
# 1. Identify stepping version
grep -i "stepping\|revision\|A0\|B0" logbook.log testbench.log | head -10

# 2. Check P-state transition logs
grep -i "pstate\|p-state\|w4_ratio" PyDoh.Sequence.log | tail -30

# 3. Check for MEMSS timeout events
log_scanner search "PKG_PSTATE_CHECKER" logbook.log
grep -i "timeout\|EID.*105337" logbook.log

# 4. Review platform-specific P-state settings
grep -i "w4_ratio\|memss.*freq\|pstate.*config" testbench.log | head -20

# 5. Check pcode GVFSM activity
log_scanner multi -i "gvfsm_trigger|||gvfsm_end|||pstate" pcode_jem_tracker.annotated.log.gz
```

**Workaround:** Verify timeout threshold is scaled correctly for emulation speed (400kHz = 5,000–10,000× slower). Validate W4 ratio configuration for the specific NVLAX stepping.

## Files Affected

- `logbook.log` — test status and timeout errors
- `PyDoh.Sequence.log` — P-state transition event timeline
- `pcode_jem_tracker.annotated.log.gz` — pcode GVFSM and scheduler activity
- Platform/stepping configuration files

## Verification

```bash
# Confirm P-state transitions complete without timeout
grep -i "pstate.*timeout\|MEMSS.*timeout" logbook.log
# Verify W4 ratio transitions succeed
grep -i "w4_ratio" PyDoh.Sequence.log | tail -10
```

## Notes

- **NVLAX stepping matters:** A0 and B0 steppings have different timing characteristics and platform-specific configurations
- Bucket classification: `PKG__PKG_PSTATE__MEMSS_P-state_Timeout_failure__W4_Ratio`
- May co-occur with BUG-036 (memory corruption during SAGV) — debug each independently
- Timing timeouts at emulation speed may not reproduce on silicon; functional stalls will

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: pstate timeout memss w4_ratio transition nvlax stepping PKG_PSTATE MEMSS_P-state_Timeout frequency
- **Keywords**: power_state_transition platform_specific memss_timeout w4_ratio
- **Trackers**: logbook.log, PyDoh.Sequence.log, pcode_jem_tracker.annotated.log.gz
