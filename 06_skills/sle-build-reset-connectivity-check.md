---
name: sle-build-reset-connectivity-check
description: "Post-elab connectivity check for key reset signals crossing the PCD/hub boundary. USE WHEN: build reaches post-elab (analyze stage complete) or post-build, need to verify reset signal connectivity (epd_on, pwrgd, cold/warm_boot_trigger, pltrst, clk_reqs). Can run after analyze stage — does NOT require full build completion."
argument-hint: "Requires WORKAREA set and analyze stage completed (VCS elab output available)."
---

# Post-Elab Reset Signal Connectivity Check

## Overview

This check verifies that the 6 key reset signals crossing the PCD/hub boundary are properly connected in the elaborated model. A broken connection on any of these signals will cause boot failures that are difficult to diagnose at runtime.

> ⚠️ **Timing**: This check can be run as soon as the **analyze** stage completes (VCS elab output is available). It does NOT require the full build to finish.

> ⚠️ **Non-blocking**: This check does not gate the build — the build can continue while you verify connectivity. Report results to the user but do not stop the build.

---

## Signals to Check

These 6 signals are critical for the PCD-to-hub reset handshake:

| # | Signal | Direction | Function | RTL names at boundaries |
|---|--------|-----------|----------|------------------------|
| 1 | **epd_on** (SLP_S3#) | PCD → Hub | Engine Power Domain on; enables INF_ST PGFSM, cross-die clk_reqs | PCD: `pmc_pwell1_soc_compute_epd_on`, `xxpcd_epd_on.io1p2_inst.xio_pad_1p2`; PKG: `pcd_epd_on`, `hub_epd_on`; Hub: `xx_hub_epd_on` |
| 2 | **vdd2_pwrgd** | PCD → Hub | Proxy for PCH_PWROK powergood | PCD: `xxvdd2_pwrgd`; PKG: via bdie tran gate |
| 3 | **cold_boot_trigger** | PCD → Hub | Cold reset sequencing, forces clocks on | PCD: `d2d_iiosf_cold_boot_trigger_i2h`, `d2d_hiosf_cold_boot_trigger_i2h`; Hub: `yy_hub_pm_cold_boot_trigger` |
| 4 | **warm_boot_trigger** | PCD → Hub | Warm reset sequencing | PCD: `d2d_iiosf_warm_boot_trigger_i2h`; Hub: `warm_boot_trigger_status` |
| 5 | **pltrst** (RSM_RST) | Platform → PCD | Platform reset, triggers powergood generation | PCD: `xxgpp_b_13_pltrst_b`, `pmc_pltrst_b`, `opltrst_cpu_b` |
| 6 | **clk_reqs** | PCD ↔ Hub | Cross-die clock request handshake | Controlled by epd_on and cold_boot_trigger |

---

## Known Signal Paths (documented in sle_dut.utf)

### epd_on full path:
```
pcd...xxpcd_epd_on.io1p2_inst.xio_pad_1p2
  → pkg.pcd_epd_on
  → bdie.xxpcd_epd_on/xxpcd_epd_on_p
  → bdie.xx_hub_epd_on/xx_hub_epd_on_h
  → pkg.hub_epd_on
  → hub.xx_hub_epd_on
```

### cold_boot_trigger path:
```
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_cold_boot_trigger_i2h
  → (d2d link)
  → hub.yy_hub_pm_cold_boot_trigger
```

### warm_boot_trigger path:
```
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_warm_boot_trigger_i2h
  → (d2d link)
  → hub (warm_boot_trigger_status)
```

### pltrst path:
```
tb_top.pkg.pcdpkg.pcd.xxgpp_b_13_pltrst_b
  → pmc_pwell1.pmc_pltrst_b
  → pmc_pwell1_pmci_io_opltrst_cpu_b
```

---

## Step 1: RTL Source Check (pre-elab)

Search the RTL source for port declarations and connections. This can be done at any time (no elab required).

### 1a: Check epd_on connectivity in RTL

```bash
# PCD side — epd_on origin
grep -rn "epd_on" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.utf" --include="*.py" | grep -v ".ref\|.pyc\|__pycache__" | head -20

# Hub side — epd_on destination
grep -rn "xx_hub_epd_on\|hub_epd_on" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -10

# Package level — bdie passthrough
grep -rn "pcd_epd_on\|hub_epd_on" $WORKAREA/integration/ --include="*.sv" --include="*.v" 2>/dev/null | head -10
```

### 1b: Check cold/warm boot trigger connectivity

```bash
# PCD d2d side
grep -rn "cold_boot_trigger\|warm_boot_trigger" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" | grep -v ".ref\|.pyc" | head -20

# Hub side
grep -rn "cold_boot_trigger\|warm_boot_trigger" $WORKAREA/src/val/emu/rtlchanges/hubbx/ --include="*.sv" --include="*.v" | grep -v ".ref" | head -10
```

### 1c: Check pwrgd connectivity

```bash
grep -rn "vdd2_pwrgd\|vnnaon_powergood\|xxvdd2_pwrgd" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -15
```

### 1d: Check pltrst connectivity

```bash
grep -rn "pltrst\|pltreset\|opltrst" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" | grep -v ".ref\|.pyc" | head -15
```

### 1e: Check for dangerous force assigns / tieoffs on reset signals

> ⚠️ **CRITICAL**: Accidental force assigns on reset IO pads have caused boot failures before (see sle_dut.utf ww17 2026 incident).

```bash
# Check for force assigns that might kill reset signals
grep -rn "force.*epd_on\|force.*pwrgd\|force.*boot_trigger\|force.*pltrst\|force.*slp_s[345]" $WORKAREA/src/val/emu/build_cfg/ --include="*.utf" --include="*.tcl" --include="*.py" | grep -v ".ref\|.pyc\|#.*force" | head -20

# Check for broad io pad tieoffs that could catch reset signals
grep -rn "io1p2.*value.*0\|io1p8.*value.*0\|xio_pad.*value.*0" $WORKAREA/src/val/emu/build_cfg/ --include="*.utf" --include="*.tcl" | grep -v ".ref\|#" | head -10
```

**If any active (uncommented) force assign targets a reset signal → FLAG AS CRITICAL and alert the user immediately.**

---

## Step 2: Elab Output Verification (post-elab)

After the analyze stage completes, verify signals in the elaborated design.

### 2a: Check for unconnected ports in elab logs

```bash
# Look for unconnected warnings on reset signals
ZSE5_OUT="$WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5"
grep -i "unconnected\|floating\|undriven" $ZSE5_OUT/log/*/elab.log 2>/dev/null | grep -i "epd_on\|boot_trigger\|pwrgd\|pltrst\|clk_req" | head -20
```

### 2b: Verify signal exists in analyzed libraries

```bash
# Check that key signals are present in the elaborated hierarchy
grep -rn "epd_on\|cold_boot_trigger\|warm_boot_trigger\|vdd2_pwrgd\|pltrst" $ZSE5_OUT/analyzed_libs/ 2>/dev/null | head -20
```

### 2c: Check probes.py force/monitor entries match expected signals

```bash
# Hub probes — should have force entries for epd_on and cold_boot_trigger
grep -n "epd_on\|cold_boot_trigger\|warm_boot_trigger\|pwrgd\|pltrst" $WORKAREA/src/val/emu/build_cfg_overrides/probes_hubbx/probes.py | grep -v ".ref"
```

Expected entries (if present, connectivity is confirmed at probe level):
- `force(f"{HUB}.xx_hub_epd_on")` ← Hub receives epd_on
- `force(f"{par_miscio}.xx_hub_epd_on")` ← Package-level passthrough
- `force(f"{par_d2d_pcd}.yy_hub_pm_cold_boot_trigger")` ← Hub receives cold_boot

---

## Step 3: Report Results

Present a summary table to the user:

```
RESET CONNECTIVITY CHECK RESULTS
═══════════════════════════════════════════════════════════════
Signal               RTL Source    Elab Verify    Force/Tieoff    Status
─────────────────────────────────────────────────────────────────
epd_on               [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
vdd2_pwrgd           [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
cold_boot_trigger    [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
warm_boot_trigger    [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
pltrst               [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
clk_reqs             [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
═══════════════════════════════════════════════════════════════
```

### Result interpretation:
- **RTL Source**: Signal name found in RTL files with proper assign/connection
- **Elab Verify**: No unconnected/floating warnings; signal present in analyzed_libs
- **Force/Tieoff**: No active force assign/tieoff that would kill the signal
- **PASS**: All three columns are clean
- **FAIL**: Any column has an issue → alert user with details

### If any signal FAILs:
1. Report the specific file and line where the problem is
2. Cross-reference with sle_dut.utf to understand the expected signal path
3. Check if a recent rtlchange or force assign modification caused the break
4. Suggest the fix (e.g., remove errant tieoff, add missing connection)

---

## Summary Checklist

| Step | Action | When |
|------|--------|------|
| 1 | RTL source grep for all 6 signals + check for dangerous force assigns | Any time (pre-elab OK) |
| 2 | Elab output verification — unconnected ports, analyzed_libs presence | After analyze stage |
| 3 | Report results table to user | After Steps 1-2 complete |
