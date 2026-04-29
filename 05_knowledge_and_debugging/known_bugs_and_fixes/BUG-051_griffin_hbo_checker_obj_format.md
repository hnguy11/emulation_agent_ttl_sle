---
bug_id: BUG-051
title: "Griffin HBO checker false-positive data mismatch due to .obj file format mismatch"
date_discovered: 2026-04-29
status: informational
severity: non-critical
stage: "TLM_POST Griffin checker validation"
bundle: all
category: test
related_patterns: [pattern_checker_config, pattern_obj_format]
tags: [griffin, HBO, checker, obj_format, false_positive, post_processing, cache_coherency, 32obj, 8obj]
phase: "POST_PROCESS"
symptoms: "GRIFFIN_ERROR data mismatch 0x60 parsed_obj parsed_memdump fc_hbo_chk cache coherency false_positive"
keywords: "post_processing validation checker_configuration object_file cache_coherency"
trackers: "griffin_run.log.gz, parsed_obj.csv.gz, parsed_memdump.csv.gz"
---

# BUG-051: Griffin HBO Checker False-Positive Due to Object File Format Mismatch

## Symptom

Griffin `fc_hbo_chk` post-processing checker reports data corruption in HBO cache with a systematic 0x60 bit difference across multiple addresses. This is a false positive — not real hardware corruption.

```
GRIFFIN_ERROR /path/to/fc_hbo_chk.py(546) @ 0 ps: [FcHboChk] Address 0x100000,
Read 0x103067, Expected 0x103007/0x0, Data mismatched!
```

## Triggered By

Post-processing checker validation on tests that use `.32.obj` format for memory initialization while the Griffin checker parses `.8.obj` format for expected values.

## Root Cause

The test infrastructure supports two memory initialization file formats with incompatible address encoding:

- **`.32.obj`**: Address >> 2 (divided by 4), 32-byte granularity. E.g., physical 0x100000 stored as `/origin 40000`, data=0x103067
- **`.8.obj`**: Full physical address, 8-byte granularity. E.g., physical 0x100000 stored as `/origin 0x100000`, data=0x103007

When the test loads `.32.obj` but the checker reads `.8.obj`, the expected values differ by 0x60 (bits [6:5]) — appearing as systematic "cache corruption" that is actually a checker configuration error.

## Fix / Solution

```bash
# Step 1: Confirm Griffin checker error
log_scanner search "GRIFFIN_ERROR" tlm_post/fc_hbo_chk/griffin_run.log.gz

# Step 2: Verify systematic 0x60 difference pattern
# If all differences are 0x60 → format mismatch (false positive)
# If random differences → real corruption

# Step 3: Verify both .obj formats exist
ls -lh *.32.obj* *.8.obj*

# Step 4: Fix — configure checker to use same format as testbench
# Update Griffin checker config to parse .32.obj instead of .8.obj
```

**Resolution:** Reconfigure Griffin checker to parse the same `.obj` format used by the testbench for memory initialization, or exclude affected addresses from checker validation.

## Files Affected

- `tlm_post/fc_hbo_chk/griffin_run.log.gz` — Griffin checker error output
- `parsed_obj.csv.gz` — Checker-generated expected values (from wrong .obj format)
- `parsed_memdump.csv.gz` — Actual memory dump values

## Verification

```bash
# After fixing checker config, re-run Griffin and verify no GRIFFIN_ERROR
log_scanner search "GRIFFIN_ERROR" tlm_post/fc_hbo_chk/griffin_run.log.gz
# Should show no results
```

## Notes

- 3+ addresses with identical 0x60 difference = strong indicator of format mismatch, not real corruption
- Random differences or single-bit flips suggest real hardware issues
- Affects all tests using `.32.obj` format with legacy `.8.obj` checker config

## Scoring Metadata (for Phase Detection System)

- **Phase**: POST_PROCESS
- **Symptoms**: GRIFFIN_ERROR data mismatch 0x60 parsed_obj parsed_memdump fc_hbo_chk false_positive
- **Keywords**: post_processing checker_configuration object_file cache_coherency
- **Trackers**: griffin_run.log.gz, parsed_obj.csv.gz, parsed_memdump.csv.gz
