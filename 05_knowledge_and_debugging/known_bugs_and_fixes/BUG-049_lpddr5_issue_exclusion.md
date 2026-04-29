---
bug_id: BUG-049
title: "LPDDR5 issue exclusion — systematic verification to rule out memory subsystem"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "test execution — memory subsystem triage"
bundle: all
category: runtime
related_patterns: [LPDDR5_DFI_TIMING, MEMORY_READ_ZERO, LOGSCANNER_MASK]
tags: [lpddr5, memory-exclusion, dfi-timing, read-zero, write-lat, data-mismatch, logscanner, systematic-verification]
phase: "TEST_EXECUTION"
symptoms: "lpddr5 memory corruption read_zero write_lat timing dfi sagv dvfs data_mismatch read_write_failure logscanner"
keywords: "memory_subsystem data_integrity dfi_timing power_state_transition systematic_exclusion"
trackers: "lpddr5_xtor_memss*_tracker.log.gz, emu.devices.lpddr5_xtor_*_dbg_msg.txt.gz, emurun.log, testbench.log, cfi_trk.log.gz"
---

# BUG-049: LPDDR5 Issue Exclusion — Systematic Verification

## Symptom

Test fails with suspected memory-related symptoms. LogScanner plugin failures may mask underlying DFI timing issues where READs return zeros instead of written data.

```
FAILED (exit status 15 — LogScanner plugin)
RDDATA returns 0x00000000 when expecting 0xDEADBEEF
67-99% of READ operations return zeros
```

Found in: `results.log`, `lpddr5_xtor_memss*_tracker.log.gz`

## Triggered By

Any test where memory corruption is suspected. Use this methodology to **systematically exclude or confirm** LPDDR5 memory subsystem as root cause before investing in deeper memory debug.

## Root Cause

When memory IS the problem, the most common cause is **DFI timing misalignment**: `dfi_rddata_valid_w*` signal asserts 2-3 cycles too late, so the memory controller samples the bus after data has disappeared. Reads return zeros instead of actual data.

**Configuration cause:** `read_lat` or `write_lat_adjust` parameters set incorrectly. Expected data-to-valid latency: 5-6 DFI clock cycles; actual: 8-9 cycles (+2-3 offset).

**LogScanner masking:** LogScanner catches benign warnings first (exit status 15), hiding the real functional memory corruption underneath.

## Fix / Solution

```bash
# Phase 1: Quick classification (5 min)
cat results.log
grep -i "error\|fail\|fatal" emurun.log | tail -10

# Phase 2: Check LPDDR5 health
ls -lh lpddr5_xtor_memss*_tracker.log.gz | awk '{print $5, $9}'
log_scanner multi -i "error|||fail|||timeout|||violation" lpddr5_xtor_memss*_tracker.log.gz

# Phase 2 CRITICAL: Verify READ data matches WRITE data
echo "=== WRITE Data ===" && \
log_scanner search "WRDATA.*0000001040" lpddr5_xtor_memss0_ch2_tracker.log.gz | head -5
echo "=== READ Data ===" && \
log_scanner search "RDDATA.*0000001040" lpddr5_xtor_memss0_ch2_tracker.log.gz | head -10
# If most READs return zeros → DFI READ TIMING ISSUE

# Phase 3: Count transactions per channel
foreach ch (0 1 2 3)
  echo "=== CH${ch} ===" && \
  log_scanner head -n 99999 lpddr5_xtor_memss0_ch${ch}_tracker.log.gz | awk -F'|' 'BEGIN{r=0;w=0} /READ/{r++} /WRITE/{w++} END{print "READs:"r" WRITEs:"w}'
end

# Phase 4: Cross-correlate with CFI
log_scanner multi "WbMtoIPtl.*0x.*f3c0|||MemData.*0x.*f3c0" cfi_trk.log.gz | head -10
```

**If DFI timing confirmed:** Adjust `read_lat` / `write_lat_adjust` parameters or escalate to LPDDR5 team with FSDB timing evidence.

**If memory is healthy:** Root cause is elsewhere — investigate other domains.

## Files Affected

- LPDDR5 DFI timing parameters (if timing issue confirmed)
- No file changes if memory subsystem is excluded as root cause

## Verification

```bash
# Healthy memory: all READs return correct data
log_scanner search "RDDATA.*<addr>" lpddr5_xtor_memss0_ch*_tracker.log.gz | grep "00 00 00 00" | wc -l
# Expected: 0 (no zero reads)

# Healthy log sizes: 80K-95K compressed per channel
ls -lh lpddr5_xtor_memss*_tracker.log.gz | awk '{print $5, $9}'
```

## Notes

- **Decision tree:** If NO errors and all READs match WRITEs → memory is healthy, investigate other domains
- LogScanner exit status 15 does NOT mean memory is fine — always verify READ/WRITE data match
- Expected healthy DFI data-to-valid latency: 5-8 clock cycles for LPDDR5
- Zero transactions on ALL channels = memory not accessed (check test config)
- For FSDB timing measurement: use `waveform_server.py` + `fsdb_client.py` to measure `dfi_rddata_w*` vs `dfi_rddata_valid_w*` timing
- This methodology is a **triage step** — it confirms or excludes memory, then you apply the appropriate specialized methodology
