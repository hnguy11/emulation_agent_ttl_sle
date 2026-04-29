---
bug_id: BUG-053
title: "All cores SHUTDOWN during SMI handling due to stale Maestro dispatch table"
date_discovered: 2026-04-29
status: informational
severity: blocker
stage: "Test execution — concurrent actions with INTR package"
bundle: all
category: runtime
related_patterns: [pattern_smi_dispatch, pattern_maestro_patch3]
tags: [SMI, SHUTDOWN, dispatch_table, maestro, iautils_patch3, triple_fault, mov_gs, concur_actions, INTR, MCA, UMCF]
phase: "TEST_EXECUTION"
symptoms: "shutdown smi handler triple_fault mov_gs dispatch_table maestro_new_gv_106 iautils_patch3 all_cores_shutdown 0xdead LT_SHUTDOWN smbase"
keywords: "smi_handling smm_wrapper dispatch_table machine_check mca_handler interrupt concur_actions emulation"
trackers: "logbook.log.gz, emurun.log, test_end_checker, uop_log_*.log"
---

# BUG-053: All Cores SHUTDOWN During SMI Handling — Stale Maestro Dispatch Table

## Symptom

Concurrent actions test fails with all cores entering SHUTDOWN. Atom cores crash first (~97M cycles), then big cores with "LT SHUTDOWN/ERR. SHUTDOWN" pattern (triple fault).

```
[97234287] test_end_checker: C15T0 (atomC3) sleep reason = SHUTDOWN
[97331607] test_end_checker: C14T0 (atomC2) sleep reason = SHUTDOWN
[97481407] test_end_checker: C2T0 sleep reason = LT SHUTDOWN/ERR. SHUTDOWN
```

## Triggered By

`concur_actions` test with `CONCUR_PKGS=INTR` enabled. The `do_smi` action sends SMI IPIs to cores whose SMI handler setup used `iautils::patch3()` instead of `InstallSmiHandler::Install()`.

## Root Cause

**Primary:** The Maestro SMI dispatch table `_maestro_new_gv_106` is stale/empty. `iautils::patch3()` writes SMBASE in hardware but does NOT re-register the handler in the dispatch table. After `SmbaseRelocate` consumes the initial entry at boot, subsequent SMI IPIs find an empty table. The SMI wrapper takes the "no handler" cleanup path, restores garbage GS from `_maestro_new_gv_105`, executes `mov gs, ax` with garbage selector → #GP → double fault → triple fault → SHUTDOWN.

**Secondary:** Even after fixing the primary issue, `generate_unctrap` actions can fire UMCF (Uncorrectable Machine Check Fault) while cores are in the SMI wrapper prologue. Without `configure_mca_with_self_check` (gated behind undefined `MCA_CONCUR`), the MCERR is unrecoverable.

**Tertiary:** The `"SMI_handler_once"` tag is shared between `fcf_maestro_execs.sln` and `pm_init.sln` — any code divergence causes a Perspec build error.

## Fix / Solution

```bash
# Step 1: Confirm all-core SHUTDOWN
zgrep "sleep reason.*SHUTDOWN" logbook.log.gz

# Step 2: Verify INTR package is enabled
zgrep "CONCUR_PKGS" .trex.env.gz
# Should show: CONCUR_PKGS='INTR'

# Step 3: Check if iautils::patch3 is used (broken)
grep -n "patch3\|InstallSmiHandler" /path/to/fcf_maestro_execs.sln
```

**Primary Fix (in `fcf_maestro_execs.sln`):**
1. Keep `"SMI_handler_once"` tagged block UNCHANGED (must match `pm_init.sln`)
2. Add separate untagged `exec declaration` with `#include "MaestroSMM.h"`
3. In `exec run_start`, replace `iautils::patch3(...)` with `maestro::InstallSmiHandler::Install(smi_handler<(processor.apic_id)>)`

**Secondary Fix (in `coherency_concur_scenarios.sln`):**
- Remove `#ifdef MCA_CONCUR` guard around `configure_mca_with_self_check`
- Add constraint `.proc_tag in DVE.processor_enable_map.get_all_enabled_procs()` to exclude ep0

## Files Affected

- `fcf_maestro_execs.sln` — SMI handler registration (primary fix)
- `coherency_concur_scenarios.sln` — MCA handler setup (secondary fix)
- `pm_init.sln` — DO NOT MODIFY (shared tag owner)

## Verification

```bash
# After fix, verify no SHUTDOWN events
zgrep "sleep reason.*SHUTDOWN" logbook.log.gz
# Should show no results

# Verify compilation succeeds for both perspec_test.c and perspec_host.cpp
```

## Notes

- Do NOT modify the `"SMI_handler_once"` tagged declaration — it must match `pm_init.sln` exactly
- Do NOT add MCA headers to ep0 — use `get_all_enabled_procs()` to exclude PCIE_XTOR scheme
- Atoms crash first (lower APIC IDs targeted first), then big cores follow
- "LT SHUTDOWN/ERR" is the triple fault variant of the same `mov gs, ax` crash

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: shutdown smi handler triple_fault mov_gs dispatch_table all_cores_shutdown 0xdead SHUTDOWN
- **Keywords**: smi_handling smm_wrapper dispatch_table machine_check concur_actions
- **Trackers**: logbook.log.gz, emurun.log, test_end_checker, uop_log_*.log
