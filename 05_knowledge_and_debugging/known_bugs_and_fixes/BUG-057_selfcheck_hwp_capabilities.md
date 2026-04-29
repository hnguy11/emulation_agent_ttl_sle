---
bug_id: BUG-057
title: "Selfcheck HWP capabilities — HIGHEST_PERFORMANCE mismatch due to missing downbin"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "Test execution — HWP PECI self-check"
bundle: all
category: test
related_patterns: [pattern_hwp_mismatch, pattern_fuse_calculation]
tags: [selfcheck, HWP, IA32_HWP_CAPABILITIES, HIGHEST_PERFORMANCE, downbin, P0_ratio, fuse, PECI, 0xdead]
phase: "TEST_EXECUTION"
symptoms: "selfcheck SelfCheck HWP HIGHEST_PERFORMANCE mismatch 0x54 0x53 0xdead halted IA32_HWP_CAPABILITIES downbin P0_ratio"
keywords: "HWP hardware_pstates capabilities downbin fuse_configuration P0_ratio selfcheck"
trackers: "logbook.log.gz, uop_log_*.log.gz, perspec_fuses.csv.gz, test_end_checker"
---

# BUG-057: Selfcheck HWP Capabilities — HIGHEST_PERFORMANCE Mismatch (Missing Downbin)

## Symptom

HWP PECI test fails with selfcheck assertion on `IA32_HWP_CAPABILITIES(HIGHEST_PERFORMANCE)`. Silicon returns 0x53 but test expects 0x54. Core halts with EBX=0x0000dead.

```
Asserting uncore_msr/pcu::IA32_HWP_CAPABILITIES(HIGHEST_PERFORMANCE) Failed
Expected Value: 0x00000054 - Actual Value: 0x0000000000000053
```

DDT bucket: `pkg_emu::Emu::test_end_checker::SelfCheck::nvlax-a0`

## Triggered By

`hwp_peci_support_random_lnl` test (or similar HWP validation tests) where the test calculates expected HIGHEST_PERFORMANCE without applying the downbin fuse adjustment.

## Root Cause

The Perspec test does NOT apply the `FUSE_CCP_0_IA_P0_RATIO_DOWNBIN` adjustment before calculating HIGHEST_PERFORMANCE.

**Test calculation (WRONG):**
```
expected = base_fuse × scaling_factor = 60 × 1.40 = 84 (0x54)
```

**Correct formula:**
```
expected = (base_fuse + group_delta - downbin) × scaling_factor
expected = (60 + 0 - 1) × 1.40 = 59 × 1.40 = 82.6 → 83 (0x53)
```

Silicon correctly returns 83 (0x53). The test expectation of 84 (0x54) is wrong — it's missing the downbin subtraction.

## Fix / Solution

```bash
# Step 1: Confirm selfcheck failure type
log_scanner search "BUCKET NAME" logbook.log.gz
# Output: pkg_emu::Emu::test_end_checker::SelfCheck::nvlax-a0

# Step 2: Find exact assertion error
log_scanner tail -n 50 uop_log_CDIE0_P0C0.log.gz
# Look for: IA32_HWP_CAPABILITIES(HIGHEST_PERFORMANCE) Failed

# Step 3: Check fuse configuration
log_scanner multi "FUSE_IA_P0_RATIO|||FUSE_CCP_0_IA_P0_RATIO_DOWNBIN|||FUSE_IA_P0_RATIO_GROUP.*BIGCORE_DELTA" perspec_fuses.csv.gz
# Key values: base_fuse=60, downbin=1, group_delta=0

# Step 4: Verify calculation
# Correct: (60 + 0 - 1) × 1.40 = 83 (0x53) ← silicon value is correct
# Test bug: 60 × 1.40 = 84 (0x54) ← test expectation is wrong
```

**Fix:** Update test source to apply formula: `(base_fuse + group_delta - downbin) × scaling_factor`. The test must read `FUSE_CCP_0_IA_P0_RATIO_DOWNBIN` and subtract it from the base ratio before applying the 1.40 scaling factor.

## Files Affected

- `perspec_test.c.gz` — Test calculation logic for HIGHEST_PERFORMANCE
- `perspec_fuses.csv.gz` — Fuse configuration values (read-only reference)

## Verification

```bash
# After fixing test calculation, verify assertion passes
log_scanner search "IA32_HWP_CAPABILITIES.*Failed" uop_log_CDIE0_P0C0.log.gz
# Should show no results
```

## Notes

- Silicon value (0x53) is CORRECT — this is a test bug, not a hardware bug
- The downbin fuse `FUSE_CCP_0_IA_P0_RATIO_DOWNBIN` reduces the effective P0 ratio
- Core group deltas (`FUSE_IA_P0_RATIO_GROUP*_BIGCORE_DELTA`) may further adjust per-core values
- Scaling factor 1.40 converts P0 ratio to HIGHEST_PERFORMANCE field value

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: selfcheck SelfCheck HWP HIGHEST_PERFORMANCE mismatch 0xdead halted IA32_HWP_CAPABILITIES downbin
- **Keywords**: HWP hardware_pstates capabilities downbin fuse_configuration P0_ratio
- **Trackers**: logbook.log.gz, uop_log_*.log.gz, perspec_fuses.csv.gz, test_end_checker
