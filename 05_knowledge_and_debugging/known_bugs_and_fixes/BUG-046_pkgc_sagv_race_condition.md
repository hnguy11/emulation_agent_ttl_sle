---
bug_id: BUG-046
title: "PKG-C entry during SAGV transition race condition — LT SHUTDOWN"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "test execution — PKG-C deep sleep entry"
bundle: all
category: runtime
related_patterns: [PM_PKGC_SAGV_RACE, SHUTDOWN_LT_ERR, MEMSS_FSM_TIMING]
tags: [pkgc, sagv, race-condition, lt-shutdown, err-shutdown, deep-sleep, fsm, pm-req, pm-rsp, pcode]
phase: "TEST_EXECUTION"
symptoms: "pkgc sagv race shutdown lt_shutdown err_shutdown power_state memory frequency transition pm_req pm_rsp fsm memss_pma hang sleep mwait c61 deep_sleep"
keywords: "power_management sagv dvfs pkg-c deep_sleep race_condition frequency_transition"
trackers: "testbench.log, hub_pwr_jem_tracker.log.gz, iosf_sb_jem_tracker.log.gz, pcode_jem_tracker.annotated.log.gz, uop_log_CDIE0_*.log"
---

# BUG-046: PKG-C Entry During SAGV Transition Race Condition

## Symptom

Core experiences LT SHUTDOWN or ERR. SHUTDOWN during PKG-C61 deep sleep entry while SAGV FSM is active (not idle).

```
[25816978666] test_end_checker: CDIE0_P0C0 sleep reason = LT SHUTDOWN/ERR. SHUTDOWN
```

Found in: `testbench.log`

## Triggered By

Tests combining PKG-C61 entry with SAGV transitions (e.g., `mdiv_pm_do_delay_pkgc61_x5_b2b_do_delay_sagv_all`). Intermittent — depends on timing alignment and test seed.

## Root Cause

Synchronization gap between PKG-C entry FSM (compute die) and SAGV FSM (memory subsystem). The PKG-C FSM proceeds with sleep entry without verifying the SAGV FSM is idle (`Memss_pma_sagv_fsm_curr_s == 0x0`). When SAGV is actively transitioning (states 0x4, 0x6, 0x14, etc.), the memory controller cannot guarantee data integrity, triggering a hardware-enforced LT SHUTDOWN.

**Race timeline:**
1. PM_REQ sent to memory controller (SAGV frequency change)
2. Core enters MWAIT → attempts PKG-C61 completion (~21ns later)
3. **SHUTDOWN occurs** — SAGV FSM not idle
4. PM_RSP arrives ~378ns later (too late)

## Fix / Solution

```bash
# 1. Confirm LT SHUTDOWN
grep -i "LT SHUTDOWN\|ERR.*SHUTDOWN" testbench.log | head -5

# 2. Verify SAGV test configuration
echo "Test: $(basename $(pwd))" && grep -i "sagv\|dvfs" vars.env emurun.log 2>/dev/null | head -5

# 3. Check SAGV FSM state at failure time (should NOT be 0x0)
zcat hub_pwr_jem_tracker.log.gz | grep "sagv_fsm" | tail -10

# 4. Verify PM_REQ/PM_RSP timing gap (shutdown between REQ and RSP)
zcat iosf_sb_jem_tracker.log.gz | grep -E "PM_REQ|PM_RSP" | tail -10

# SAGV FSM States: 0x0=IDLE(safe), 0x4=FREQ_CHANGE_PREP, 0x6=VOLTAGE_RAMP,
#                  0x14=MC_RECONFIGURE, 0x1d=PLL_LOCK_WAIT (all unsafe)
```

**Recommended fixes:**
- **RTL fix:** Add HW fence — block PKG-C entry until `sagv_fsm_curr_s == 0x0`
- **FW fix:** Pcode checks SAGV state before allowing PKG-C entry
- **Workaround:** Add delay margin or disable SAGV+PKG-C stress combinations

## Files Affected

- No code fix — hardware/firmware synchronization bug

## Verification

```bash
# After fix: SAGV FSM should reach 0x0 before PKG-C entry allowed
zcat hub_pwr_jem_tracker.log.gz | grep "sagv_fsm" | tail -5
# No PM_REQ outstanding during PKG-C completion
grep -i "SHUTDOWN" testbench.log | wc -l  # Expected: 0
```

## Notes

- Build a correlation timeline from 3 log sources: testbench.log, hub_pwr_jem_tracker.log.gz, iosf_sb_jem_tracker.log.gz
- The key evidence is SAGV FSM ≠ 0x0 at exact failure timestamp
- Multiple successful PKG-C entries may precede the failure (e.g., fails on 3rd of 5 attempts)
- Do NOT confuse protocol timing (μs) with signal alignment gaps (ns)
- Check pcode_jem_tracker for concurrent SAGV + PKG-C handler execution
