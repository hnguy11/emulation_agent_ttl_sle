---
bug_id: BUG-052
title: "Multi-stage test SVA failure detected in TLM_POST despite emulation PASS"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "TLM_POST SVA post-processing"
bundle: all
category: test
related_patterns: [pattern_sva_post, pattern_multi_stage]
tags: [SVA, TLM_POST, sva_post_proc, multi_stage, assertion, post_processing, emulation_pass]
phase: "POST_PROCESS"
symptoms: "TLM_POST sva_post_proc SVA_ASSERTION_ERROR assertion_failures PASSED FAILED multi_stage test_result"
keywords: "sva_validation post_processing multi_stage_test assertion_checking emulation"
trackers: "logbook.log.gz, results.log, bbb.log.gz, assertion_failures.log.gz, zse_assertions.log.gz, emurun.log.gz"
---

# BUG-052: Multi-Stage Test SVA Failure in TLM_POST Despite Emulation PASS

## Symptom

Test shows PASSED in `emurun.log` but overall status is FAILED. The failure is an SVA (SystemVerilog Assertion) violation detected during TLM_POST post-processing — not during emulation execution.

```
TEST RESULT: TLM_POST: sva_post_proc: Detected SVA Error
```

Emulation log shows:
```
* The number of tests PASSED are 1
* test_name    Result: PASSED  SimTime: 32625387 clocks
```

## Triggered By

Any emulation test where the multi-stage pipeline has a TLM_POST SVA checking phase. Failure occurs after emulation completes, during post-processing assertion validation.

## Root Cause

Test execution follows a multi-stage pipeline: Model Build → Emulation Execution → TLM_POST (post-processing) → Final Status Aggregation. The test FAILS if ANY stage fails. Engineers often see "PASSED" in `emurun.log` and assume the test passed, but the SVA post-processing stage detected assertion violations in the recorded transaction data.

**Critical rule:** `results.log` is the authoritative single source of truth — NOT `emurun.log`.

## Fix / Solution

```bash
# Step 1: Check authoritative status
cat results.log
# Should show: FAILED

# Step 2: Confirm emulation passed but post-processing failed
log_scanner search -i "TEST RESULT" logbook.log.gz | tail -10
# Look for "TLM_POST" and "SVA" in the result line

# Step 3: Verify emulation completed
log_scanner tail -n 100 emurun.log.gz | grep -E "Total Test Summary|tests PASSED"

# Step 4: Identify specific SVA assertion failure
log_scanner search "SVA_ASSERTION_ERROR\|assertion.*fail" assertion_failures.log.gz
# OR
log_scanner head -n 50 zse_assertions.log.gz

# Step 5: Check post-processing errors
log_scanner multi -i "TLM.*POST.*ERROR|||final rpt error" logbook.log.gz | head -20
log_scanner multi "ERROR|||Stage with errors" bbb.log.gz | head -20
```

**Resolution:** Investigate the specific SVA assertion that fired — it may indicate a real RTL issue, a checker bug, or a known waivable condition.

## Files Affected

- `results.log` — Authoritative test status (single source of truth)
- `logbook.log.gz` — Complete test log with all stages
- `assertion_failures.log.gz` — SVA error summary
- `zse_assertions.log.gz` — Full SVA assertion trace

## Verification

```bash
# After fixing the SVA issue or applying waiver, re-run and check:
cat results.log
# Should show: PASSED
```

## Notes

- **WRONG conclusion:** "emurun.log shows PASSED → test passed"
- **CORRECT conclusion:** "emurun.log shows PASSED → emulation stage passed, check post-processing separately"
- Always check `results.log` first — it aggregates all stages
- Common pitfall: wasting hours debugging emulation when the issue is in post-processing checkers
- SVA violations may be waivable if they are known checker limitations

## Scoring Metadata (for Phase Detection System)

- **Phase**: POST_PROCESS
- **Symptoms**: TLM_POST sva_post_proc SVA_ASSERTION_ERROR assertion_failures PASSED FAILED
- **Keywords**: sva_validation post_processing multi_stage_test assertion_checking
- **Trackers**: logbook.log.gz, results.log, bbb.log.gz, assertion_failures.log.gz, zse_assertions.log.gz
