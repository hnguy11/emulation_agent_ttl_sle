---
bug_id: BUG-037
title: "LPDDR5 DFI Signal Misalignment — write_lat_adjust / read_lat_adjust Incorrect"
date_discovered: 2026-04-29
status: informational
severity: non-critical
stage: "Test execution — DDR memory read/write operations"
bundle: all
category: runtime
related_patterns: [pattern_dfi_misalignment, pattern_lpddr5_latency]
tags: [lpddr5, dfi, signal, alignment, write_lat_adjust, read_lat_adjust, memory, data_mismatch, timeout, calibration]
phase: "TEST_EXECUTION"
symptoms: "lpddr5 ddr memory read write dfi signal alignment timing data_mismatch timeout calibration training write_lat_adjust read_lat_adjust"
keywords: "memory_subsystem dfi_protocol signal_timing write_lat read_lat"
trackers: "lpddr5_xtor_memss*_ch*_tracker.log.gz, testbench.log, logbook.log"
---

# BUG-037: LPDDR5 DFI Signal Misalignment — write_lat_adjust / read_lat_adjust Incorrect

## Symptom

Memory READ/WRITE operations fail intermittently (e.g., "every second READ fails"). DFI data signals are misaligned with their corresponding valid/enable signals by N clock cycles.

```
[ERROR] Memory read timeout at address 0x1040 on channel 3
[ERROR] Data mismatch: expected 0xDEADBEEF, got 0x00000000
[ERROR] DFI read data valid signal not asserted
```

Found in: `logbook.log`, `lpddr5_xtor_memss*_ch*_tracker.log.gz`

## Triggered By

Tests that perform DDR memory transactions after initialization completes. Memory init passes, but runtime READ/WRITE operations fail. Use this methodology when failures are intermittent and pattern-dependent (not all operations fail).

## Root Cause

DFI (DDR PHY Interface) `write_lat_adjust` or `read_lat_adjust` configuration values are incorrect, causing data and valid/enable signals to be misaligned by N clock cycles. The PHY delivers data at the correct time, but the controller's valid signal arrives early or late.

**Diagnostic pattern in tracker logs:**
```
READ   (succeeds)
WRITE  (succeeds)
WRITE  (succeeds)
READ   (succeeds)
WRITE  (FAILS)  ← failure after specific READ/WRITE sequence
```

## Fix / Solution

```bash
# 1. Find failing channel from tracker logs
for memss in 0 1; do
  for ch in 0 1 2 3 4 5 6 7; do
    echo "=== memss${memss}_ch${ch} ==="
    log_scanner multi -i "error|||fail|||timeout" lpddr5_xtor_memss${memss}_ch${ch}_tracker.log.gz | head -5
  done
done

# 2. Check current latency configuration
grep -i "write_lat_adjust\|read_lat_adjust" testbench.log | grep -i "forcing\|setting"

# 3. Measure actual misalignment using waveform (if FSDB available)
# Query DFI data vs valid signal timing at failure timestamp
python3 /nfs/site/disks/afeldma_wa01/tools/verdi_agent/fsdb_client.py find_edge \
  tb_top.memss0_dfi_rddata_valid_w0 <failure_time_ps> 10000 100 rising

# 4. Count clock cycles in the gap
python3 /nfs/site/disks/afeldma_wa01/tools/verdi_agent/fsdb_client.py count_cycles \
  tb_top.memss0_dfi_clock <data_time> <valid_time> 50
```

**Apply fix:** Set `write_lat_adjust` (or `read_lat_adjust`) to the measured cycle count:
```bash
# Example: measured 5-cycle gap
# Change: memss0_write_lat_adjust = 0x0
# To:     memss0_write_lat_adjust = 0x5
grep -r "write_lat_adjust" content/ test_cfg/ *.cfg
```

## Files Affected

- `testbench.log` — contains forced latency values (`write_lat_adjust`, `read_lat_adjust`)
- `lpddr5_xtor_memss*_ch*_tracker.log.gz` — per-channel DDR transaction logs (16 channels: 2 MEMSS × 8 CH)
- Test configuration files (`test_cfg/memory_config.cfg`, `content/tests/perspec_*.c`)

## Verification

```bash
# Rerun test and confirm no READ/WRITE failures
log_scanner multi -i "error|||fail|||timeout" lpddr5_xtor_memss0_ch3_tracker.log.gz
# Verify all operations succeed in tracker
log_scanner multi "READ|||WRITE" lpddr5_xtor_memss0_ch3_tracker.log.gz | nl | tail -20
```

## Notes

- **DFI signals to check:** `dfi_rddata_valid_w0`, `dfi_rddata_w0`, `dfi_rddata_en_w0`, `dfi_wrdata_en_w0`, `dfi_wrdata_w0`
- Tracker log format: `|GLOBAL_STAMP|MEM_STAMP|RANK|CID|CMD|ADDRESS|BG|BA|RA|CA|DM|DATA|`
- Do NOT use this methodology if all memory operations fail (likely config/model issue) or if failure occurs before memory init
- FSDB time range must cover the failure timestamp — verify with `time_info` query first

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: lpddr5 ddr memory read write dfi signal alignment data_mismatch timeout write_lat_adjust read_lat_adjust
- **Keywords**: memory_subsystem dfi_protocol signal_timing write_lat read_lat
- **Trackers**: lpddr5_xtor_memss*_ch*_tracker.log.gz, testbench.log, logbook.log
