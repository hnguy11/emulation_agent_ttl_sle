---
bug_id: BUG-050
title: "Core MCA from HBO aggregate error during clock gating transition"
date_discovered: 2026-04-29
status: informational
severity: blocker
stage: "POST_PROCESS / late-stage runtime"
bundle: all
category: test
related_patterns: [pattern_hbo_clock_gating, pattern_mca_cascade]
tags: [MCA, HBO, CATERR, clock_gating, coherency, CSTATE, SNCU, crashlog, power_management]
phase: "POST_PROCESS"
symptoms: "Core_got_MCA MCAKIND CATERR hbo_aggr hbo_errlog IERR bus_infr_IERR bus_biu_IERR pma_IERR bbl_mc_status clock_gating cclk shutdown halt multiple_jobs_failed"
keywords: "power_management clock_gating HBO home_base_orchestrator MCA machine_check_architecture CATERR"
trackers: "mca_trk.log.gz, hbo_power_trk.log.gz, logbook.log.gz, ddt_all_buckets.log"
---

# BUG-050: Core MCA from HBO Aggregate Error During Clock Gating Transition

## Symptom

Coherency stress test fails late in execution with DDT bucket `CORE__CSTATE__Core_got_MCA`. GPC CSTATE_CHECKER reports "Core got MCA: MCAKIND" on multiple cores. Failure occurs at billions of ps during active execution — NOT during boot.

```
Signature:pkg_emu::Post::TLM_POST::multiple_jobs_failed::CORE__CSTATE__Core_got_MCA::<stepping>
CSTATE_CHECKER: ERROR!  EID: 105336 C1: Core got MCA: MCAKIND Post check has failed
```

## Triggered By

Coherency stress tests with active power management where HBO clock slices gate simultaneously during in-flight coherency requests.

## Root Cause

HBO (Home Base Orchestrator) encounters an error while its clock slices are gated off. During coherency stress, power management logic periodically gates HBO clock domains. If a coherency request (snoop, writeback) is in-flight during the gating window, it triggers an HBO aggregate error (`hbo_aggr0 ≠ 0`). The error escalates: HBO SNCU → CATERR → BBL MCA → IERR → Core MCA → crashlog → SHUTDOWN.

**Key distinguishing feature:** `hbo_aggr0` has non-zero value and `hbo_errlog` changes from init value `0x3000000` to a value with bit 63 set. CDC (coherency data check) typically PASSES — error caught before data corruption.

## Fix / Solution

```bash
# Step 1: Confirm DDT bucket
log_scanner search "" ddt_all_buckets.log.gz
# Look for CORE__CSTATE__Core_got_MCA

# Step 2: Find initial HBO error in MCA tracker
log_scanner multi -i "hbo_aggr|||hbo_errlog" mca_trk.log.gz | grep -v "= 0x0\|= 0x3000000"
# Look for hbo_aggr0 = 0x4, hbo_errlog with bit 63 set

# Step 3: Correlate with clock gating transitions
log_scanner tail -n 100 hbo_power_trk.log.gz
# Verify HBO Cclk → 0 transitions bracket the error timestamp

# Step 4: Verify data integrity
log_scanner tail -n 5 coh_data_check_merged.out.gz
```

**Resolution options:**
- Report as HBO clock gating errata (recommended for A0)
- Disable HBO clock gating via fuse overrides (workaround)
- Waive if documented A0 known issue

## Files Affected

- `mca_trk.log.gz` — MCA cascade timeline analysis
- `hbo_power_trk.log.gz` — HBO clock domain state correlation
- `ddt_all_buckets.log` — DDT bucket classification

## Verification

```bash
# Verify CATERR follows HBO error by <500ns (confirms HBO is root cause)
TRIGGER_TIME=<hbo_aggr0_timestamp>
log_scanner search "" mca_trk.log.gz | awk -v t="$TRIGGER_TIME" '$1 >= t && $1 <= t+500000 {print}'
```

## Notes

- Do NOT confuse with PCODE_MCA AI_HGS — same bucket but different mechanism (HBO error vs pCode exception)
- Filter init-time `hbo_errlog = 0x3000000` — this is benign boot-time value
- CATERR cascade: HBO SNCU (~0ns) → CATERR (~300ns) → BBL MCA (~400ns) → IERR (~2200ns) → CNCU event_core_ierr (~3000ns)
- Affected configs: coherency stress + power mgmt, multi-slice HBO, EMU_FLUSH_MUFASA=1

## Scoring Metadata (for Phase Detection System)

- **Phase**: POST_PROCESS
- **Symptoms**: Core_got_MCA MCAKIND CATERR hbo_aggr hbo_errlog IERR clock_gating shutdown halt crashlog
- **Keywords**: power_management clock_gating HBO MCA CATERR coherency_stress
- **Trackers**: mca_trk.log.gz, hbo_power_trk.log.gz, ddt_all_buckets.log, logbook.log.gz
