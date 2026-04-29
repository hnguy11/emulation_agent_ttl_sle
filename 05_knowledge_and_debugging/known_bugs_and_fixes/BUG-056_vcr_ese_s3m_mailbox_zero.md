---
bug_id: BUG-056
title: "VCR ESE/S3M mailbox register reads return zero"
date_discovered: 2026-04-29
status: informational
severity: critical
stage: "Test execution — VCR register validation"
bundle: all
category: test
related_patterns: [pattern_vcr_read_zero, pattern_ese_mailbox]
tags: [VCR, ESE, S3M, mailbox, register, read_zero, IOSF_SB, CRRD, CRWR, CMPD, ESE_LLEP, 0xDA0C]
phase: "TEST_EXECUTION"
symptoms: "VCR_FAIL ese s3m mailbox read zero write succeed register mismatch 0xda0c ese_mailbox s3m_mailbox ese_llep CRRD CRWR CMPD"
keywords: "vcr_validation register_read_write ese_endpoint s3m_security mailbox_interface iosf_sideband"
trackers: "VCR_FAIL, VCR_READ_MISMATCH, uop_log_*.log, idi.log.gz, iosf_sb_jem_tracker.log.gz, results.log"
---

# BUG-056: VCR ESE/S3M Mailbox Register Reads Return Zero

## Symptom

VCR (Virtual Configuration Register) test fails because reads from ESE and S3M mailbox registers return 0x00000000 instead of the written test pattern (0xDA0C). Writes succeed (CMP SUCCESS) but reads return zeros.

```
[PERSPEC_MAESTRO] VCR_FAIL: VCR read 0x4000C1A8 returned=0x00000000, expected=0x0000DA0C
[PERSPEC_MAESTRO] VCR_FAIL: VCR read 0x4000C1E8 returned=0x00000000, expected=0x0000DA0C
```

## Triggered By

VCR validation tests (e.g., `check_only_vcrs_bkc`) that write a test pattern then read back from ESE/S3M mailbox registers.

## Root Cause

The ESE_LLEP endpoint does not implement read-back for specific mailbox register offsets. Write transactions (CRWR) are acknowledged with CMP SUCCESS, but the data is NOT stored in a readable register. Subsequent reads (CRRD) return CMPD with data=0x00000000.

**Possible causes:**
1. Registers are write-only by design (mailbox command triggers)
2. Register implementation is stubbed/missing in emulation model
3. VCR translation table entries are incorrect for these offsets

**Affected registers:** ESE_MAILBOX_COMMAND (0x586208), ESE_MAILBOX_DATA_BUFFER (0x586210), ESE_MAILBOX_FLOW_STATUS (0x586200), ESE2UCODE_PATCH_REV_ID (0x488958), S3M_ENABLED_FEATURES (0x488110)

## Fix / Solution

```bash
# Step 1: Confirm VCR failure pattern
grep "VCR_FAIL" uop_log_CDIE0_P0C0.log | head -20

# Step 2: Extract unique failing addresses
grep "VCR_FAIL" uop_log_CDIE0_P0C0.log | sed -n 's/.*VCR read \(0x[0-9A-Fa-f]*\).*/\1/p' | sort -u

# Step 3: Trace IDI transactions (verify zeros in U2C DATA)
zcat idi.log.gz | grep -E "003c5c586208" | grep -E "U2C DATA|C2U DATA" | head -20

# Step 4: Trace IOSF SB transactions (verify CMPD returns zeros)
zcat iosf_sb_jem_tracker.log.gz | grep "PCD0_ESE_LLEP" | grep "CRRD" | head -5
# Then trace TXNID to see CMPD response data = 00000000
```

**Resolution options:**
1. File bug against ESE/S3M emulation model team with transaction traces
2. Exclude failing addresses from VCR test: `VCR_SKIP_ADDRESSES="0x4000C1A8,0x4000C1E8,..."`
3. If write-only by design, update VCR test to skip read-back for these registers

## Files Affected

- `uop_log_CDIE0_P0C0.log` — VCR test failure messages
- `idi.log.gz` — IDI fabric transaction data (U2C DATA shows zeros)
- `iosf_sb_jem_tracker.log.gz` — IOSF SB endpoint CMPD responses

## Verification

```bash
# After fix (model update or test waiver), verify no VCR_FAIL
grep "VCR_FAIL" uop_log_CDIE0_P0C0.log
# Should show no results or reduced count
```

## Notes

- CMP SUCCESS only means protocol completed — NOT that data was retained
- Write data (C2U DATA = 0xDA0C) is correct; only reads return zeros
- Transaction flow: CPU → IDI → IOSF SB → ESE_LLEP → CMPD with 0x00000000
- VCR address mapping: VCR 0x4000C1A8 → Physical 0x488958 → IOSF SB offset 0x8958
- Some addresses may work correctly — compare working vs failing to identify register-specific issues

## Scoring Metadata (for Phase Detection System)

- **Phase**: TEST_EXECUTION
- **Symptoms**: VCR_FAIL ese s3m mailbox read zero 0xda0c register mismatch CRRD CMPD 00000000
- **Keywords**: vcr_validation register_read_write ese_endpoint s3m_security mailbox_interface
- **Trackers**: uop_log_*.log, idi.log.gz, iosf_sb_jem_tracker.log.gz, results.log
