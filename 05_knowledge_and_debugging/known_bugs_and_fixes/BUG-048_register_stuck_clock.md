---
bug_id: BUG-048
title: "Register stuck at 0 — clock not toggling due to clock gating or power sequencing"
date_discovered: 2026-04-29
status: informational
severity: blocker
stage: "test execution — hardware initialization"
bundle: all
category: runtime
related_patterns: [pattern_clock_stuck, pattern_warm_reset]
tags: [register-stuck, clock-gating, clock-not-toggling, power-sequencing, warm-reset, timeout, polling, crif, fsdb]
phase: "TEST_EXECUTION"
symptoms: "register stuck timeout clock gating polling hardware warm_reset initialization state_machine mirror did_not_hit_value 0x000"
keywords: "clock_enable power_sequencing hardware_initialization reset_behavior"
trackers: "uop_log_*.log.gz, testbench.log.gz, logbook.log.gz, FSDB waveforms"
---

# BUG-048: Register Stuck at 0 — Clock Not Toggling

## Symptom

Register reads return constant 0x000 when expecting dynamic updates. CPU polling times out waiting for hardware register value.

```
<14504177870> Did not hit value on MIRROR_TARGET_WP1_RPM_GCD, Expected Value (1536) - value: 0x00000000
<14504309870> CPU LPA0C0 halted with EBX=0x0000DEAD
```

Found in: `uop_log_*.log.gz`

## Triggered By

Any test where hardware registers must update from non-zero sources. Common on warm reset (works on cold boot, fails on warm reset). CPU polls register in a loop, never sees expected value, times out.

## Root Cause

**Clock not enabled/toggling** for the hardware block containing the target register. The register's clock input is stuck at 0 due to:
- Clock gating logic preventing clock from reaching registers
- Power sequencing not enabling clock during certain boot modes (e.g., warm reset)
- Clock enable tied to incorrect condition (power-on-reset only)
- Clock mux selecting disabled clock source

**Proof chain:** Register output = 0 → Data source = 0 → Write enable = 0 → **Clock = 0 (stuck, never toggles)** → Reset properly de-asserted (rst_b = 1) → Power good asserted

## Fix / Solution

```bash
# 1. Find the failing register and time
log_scanner multi -i "did not hit|||timeout|||0xDEAD|||halt" uop_log_*.log.gz | head -10

# 2. Use CRIF parser to get RTL signal path (1000x faster than FSDB search)
python3 /nfs/site/disks/afeldma_wa01/tools/verdi_agent/crif_parser.py search "$CRIF_FILE" "MIRROR_TARGET_WP1_RPM_GCD"

# 3. Query clock signal in waveform at failure time
/nfs/site/disks/afeldma_wa01/tools/verdi_agent/fsdb_client.py get_signals \
    "<rtl_path>.clk,<rtl_path>.rst_b" <failure_time>

# 4. Verify clock is actually stuck (not just sampled during low phase)
/nfs/site/disks/afeldma_wa01/tools/verdi_agent/fsdb_client.py trace_signal \
    "<rtl_path>.clk" <start_time> <end_time> 100000
# 0 value changes = clock stuck; multiple = toggling normally
```

**Fix depends on scenario:**
- Warm reset issue → Add warm reset detection to clock enable conditions
- Power good not propagating → Fix power good synchronizer/CDC
- Clock mux wrong → Fix clock mux control signals
- Clock enable gated on wrong condition → Trace clock enable back to control logic

## Files Affected

- RTL clock gating logic for the affected hardware block (varies by instance)

## Verification

```bash
# After fix: register should update to non-zero value
# Clock signal should show transitions (toggling)
/nfs/site/disks/afeldma_wa01/tools/verdi_agent/fsdb_client.py trace_signal "<rtl_path>.clk" <start> <end> 100000
# Expected: multiple value changes (clock toggling)
```

## Notes

- **CRITICAL:** Always use CRIF parser first for register-to-RTL mapping (10ms vs 10+ seconds for FSDB search)
- Do NOT assume power good = clock enabled — these are separate conditions
- Do NOT conclude clock is stuck from a single sample — use `trace_signal` over a time window
- Always check rst_b first: if rst_b = 0, hardware is in reset (expected behavior)
- Common scenario: works on cold boot, fails on warm reset — clock enable logic only triggers on POR
- Tools: `crif_parser.py`, `fsdb_client.py`, `waveform_server.py` in `/nfs/site/disks/afeldma_wa01/tools/verdi_agent/`
