---
bug_id: BUG-042
title: "LPDDR5/DDR5 signal width overflow — DFI parameter truncation causes memory corruption"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "runtime / memory test"
bundle: all
category: runtime
related_patterns: []
tags: [lpddr5, ddr5, signal_width, overflow, dfi, memory_corruption, truncation, x16, timing, rdval_latency, 0xdead]
phase: "RUNTIME"
symptoms: "push_pop_ss cfi fsm hang boot d2d bfm timeout protocol lpddr5 ddr5 memory corruption read_zero write_zero 0xdead ebx fail_memcheck x16 x8 timing signal_width overflow"
keywords: "memory_subsystem signal_width_overflow configuration_mismatch device_width_migration dfi_interface"
trackers: "logbook.log.gz, lpddr5_xtor_memss*_ch*_tracker.log.gz, ddr5_xtor_memss*_tracker.log.gz"
---

# BUG-042: LPDDR5/DDR5 Signal Width Overflow — DFI Parameter Truncation

## Symptom

Memory test fails with `EBX=0x0000dead` (fail_memcheck). Reads return zeros instead of written values. Corruption follows "every second operation" pattern:

```
logbook.log.gz:
  test_end_checker: Error: CDIE0_P0C0 halted, EBX register is 0x0000dead

lpddr5_xtor_memss0_ch2_tracker.log.gz:
  WRDATA showing 0x00000000 instead of expected value (e.g., 0xDEADBEEF)
  Alternating success/failure pattern at address 0x1040
```

## Triggered By

```bash
# x16 LPDDR5/DDR5 memory test at high frequency (7200+ MT/s)
# Typically appears during x8 → x16 device width migration
```

## Root Cause

Signal width overflow in DFI transactor. Configuration parameter `memss0_rdval_latency: 145` exceeds the SystemVerilog signal bit width `[5:0]` (max 63), causing silent truncation:

```
Config value: 145 (0x91) → Truncated to: 17 (145 & 0x3F) → Error: 128 cycles misalignment
```

**In `hub_emu_dfi_lpddr5_xtor.sv`:**
```systemverilog
bit [NUM_OF_WP-1:0] [5:0]  wp_memss0_t_phy_rdval;  // ❌ 6 bits, max 63
// Should be:
bit [NUM_OF_WP-1:0] [9:0]  wp_memss0_t_phy_rdval;  // ✅ 10 bits, max 1023
```

The 128-cycle misalignment causes `dfi_rddata_valid_w0` to assert too early, corrupting data/valid signal alignment.

## Fix / Solution

**Permanent fix: Change signal width `[5:0]` → `[9:0]` in testbench:**
```bash
# Find affected signals
grep "wp_memss.*_t_phy_rdval\|wp_memss.*_t_phy_wrval" hub_emu_dfi_lpddr5_xtor.sv

# Change [5:0] → [9:0] for ALL delay signals:
# wp_memss0_t_phy_rdval, wp_memss1_t_phy_rdval
# wp_memss0_t_phy_wrval, wp_memss1_t_phy_wrval (if exists)
```

**Temporary workaround: Revert to x8 device width** (lower timing requirements fit within [5:0])

```bash
# Quick triage commands:
log_scanner multi -i "0x0000dead|||fail_memcheck" logbook.log.gz
grep -i "ddr_type\|device_width\|x16\|x8" test_cfg/*.dut_cfg
log_scanner multi "rdval_latency|||wrval_latency" src/val/emu/tests/mem_config/*/xtor_config.yaml
python3 -c "val=145; print(f'Config: {val}, Truncated: {val & 0x3F}, Error: {val - (val & 0x3F)}')"
```

## Files Affected

- `hub_emu_dfi_lpddr5_xtor.sv` — signal width declarations `[5:0]` → `[9:0]`
- `xtor_config.yaml` — timing parameters (memss0_rdval_latency: 145)

## Verification

```bash
# After fix, verify signal width
grep "wp_memss.*_t_phy_rdval" hub_emu_dfi_lpddr5_xtor.sv
# Should show [9:0] instead of [5:0]

# Re-run test and check transaction pattern
log_scanner multi "READ|||WRITE|||RDDATA|||WRDATA" lpddr5_xtor_memss0_ch2_tracker.log.gz | grep "0000001040"
# WRDATA should show correct values, no alternating failure pattern
```

## Notes

- SystemVerilog does NOT warn on value truncation — must manually verify signal width vs. config parameters
- [9:0] (10 bits, max 1023) provides headroom for frequencies up to 10000+ MT/s
- If x8 passes but x16 fails, suspect timing parameter overflow immediately
- Check WRDATA (not just RDDATA) — if WRDATA shows zeros, it's a WRITE timing issue
- Affects all DDR types (LPDDR5/DDR5/DDR4) with timing parameters > 63
