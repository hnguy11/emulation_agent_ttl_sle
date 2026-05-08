---
name: sle-build-reset-connectivity-check
description: "Post-elab connectivity check for key reset/power/clock/sideband signals crossing the PCD/hub boundary. USE WHEN: build reaches post-elab (analyze stage complete) or post-build, need to verify connectivity of reset signals, clock requests, pmsync/pmdown, and IOSF SB structural path. Can run after analyze stage — does NOT require full build completion."
argument-hint: "Requires WORKAREA set and analyze stage completed (VCS elab output available)."
---

# Post-Elab Reset & Power Signal Connectivity Check

## Overview

This check verifies that the key signals crossing the PCD/hub boundary are properly connected in the elaborated model. Signals are organized into 3 groups:
- **Group A** — Reset/Power signals (epd_on, pwrgd, boot triggers, pltrst, pmsync/pmdown)
- **Group B** — IOSF Sideband structural path (d2d SB link modules, ISM states, PMA FSM)
- **Group C** — Cross-die clock requests (XTAL, CRO, OCB, PMC wake)

A broken connection on any of these signals will cause boot failures or hangs that are difficult to diagnose at runtime.

> ⚠️ **Timing**: This check can be run as soon as the **analyze** stage completes (VCS elab output is available). It does NOT require the full build to finish.

> ⚠️ **Non-blocking**: This check does not gate the build — the build can continue while you verify connectivity. Report results to the user but do not stop the build.

---

## Signals to Check

### Group A — Reset/Power Signals

| # | Signal | Direction | Function | RTL names at boundaries |
|---|--------|-----------|----------|------------------------|
| A1 | **epd_on** (SLP_S3#) | PCD → Hub | Engine Power Domain on; enables INF_ST PGFSM, cross-die clk_reqs | PCD: `pmc_pwell1_soc_compute_epd_on`, `xxpcd_epd_on.io1p2_inst.xio_pad_1p2`; PKG: `pcd_epd_on`, `hub_epd_on`; Hub: `xx_hub_epd_on` |
| A2 | **vdd2_pwrgd** | PCD → Hub | Proxy for PCH_PWROK powergood | PCD: `xxvdd2_pwrgd`; PKG: via bdie tran gate |
| A3 | **cold_boot_trigger** | PCD → Hub | Cold reset sequencing, forces clocks on | PCD: `d2d_iiosf_cold_boot_trigger_i2h`, `d2d_hiosf_cold_boot_trigger_i2h`; Hub: `yy_hub_pm_cold_boot_trigger` |
| A4 | **warm_boot_trigger** | PCD → Hub | Warm reset sequencing | PCD: `d2d_iiosf_warm_boot_trigger_i2h`; Hub: `warm_boot_trigger_status` |
| A5 | **pltrst** (RSM_RST) | Platform → PCD | Platform reset, triggers powergood generation | PCD: `xxgpp_b_13_pltrst_b`, `pmc_pltrst_b`, `opltrst_cpu_b` |
| A6 | **pmsync_pmdown_own_req** | Hub internal | PM sync power-down request from punit | Hub: `punit_inf_st_top.punit_io_regs_inf_st.PunitIOoutput_punit_inf_st_top.io_pmsync_pmdown_own_req_ack.pmsync_pmdown_own_req` |
| A7 | **pmsync_pmdown_own_ack** | Hub internal | PM sync power-down acknowledge | Hub: `punit_inf_st_top.punit_io_regs_inf_st.PunitIOoutput_punit_inf_st_top.io_pmsync_pmdown_own_req_ack.pmsync_pmdown_own_ack` |
| A8 | **d2d_pma_fsm_state (hub2pcd)** | Hub → PCD | D2D PMA link FSM state for hub-to-pcd link | Hub: `punit_inf_st_top.punit_io_regs_inf_st.PunitIOoutput_punit_inf_st_top.io_ip_driver_fsm_state_hub2pcd_d2d_pma.state[4:0]` |

### Group B — IOSF Sideband Structural Path

| # | Signal | Side | Function | RTL path |
|---|--------|------|----------|----------|
| B1 | **iosfsb_gpsbb_side_ism_fabric** | PCD | GPSB fabric ISM state [2:0] — SB ready indicator | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_iosfsb_gpsbb_side_ism_fabric` |
| B2 | **iosfsb_gpsbb_side_ism_agent** | PCD | GPSB agent ISM state [2:0] — SB agent ready | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_iosfsb_gpsbb_side_ism_agent` |
| B3 | **d2d_sb_link_secure_est_in_prog** | PCD | SB link security establishment in progress | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_sb_link_secure_est_in_prog` |
| B4 | **sb_link_rst_b** | PCD | SB link reset (active low) — if disconnected, SB is dead | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.sb_link_rst_b` |
| B5 | **d2d_pma_sb_controller.PMA_FSM_state** | PCD | SB PMA controller FSM [5:0] — manages physical link | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_sb_link.d2d_pma_sb_controller.PMA_FSM_state` |
| B6 | **d2d_hiosf_sb_link (Hub side)** | Hub | Hub-side D2D HIOSF sideband link module | `{HUB_TOP}.titan.par_d2d_pcd.d2d_hiosf_top.d2d_hiosf_sb_link` |
| B7 | **hbsb_chicken_bits_1** | Hub | SB bridge chicken bits (SLE workaround touches this) | `{HUB_TOP}.titan.par_d2d_pcd.d2d_hiosf_top.d2d_hiosf_sb_link.d2d_sb_ll.d2d_sbb_hb.SBHB_REGS_HIOSF...registers.hbsb_chicken_bits_1` |

### Group C — Cross-Die Clock Requests

| # | Signal | Direction | Function | RTL path (PCD side) |
|---|--------|-----------|----------|---------------------|
| C1 | **XTAL_CLK_req_h2i** | Hub → PCD | Hub requests XTAL clock from PCD | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_XTAL_CLK_req_h2i` |
| C2 | **XTAL_CLK_ack_i2h** | PCD → Hub | PCD acknowledges XTAL clock request | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_XTAL_CLK_ack_i2h` |
| C3 | **CRO_CLK_req_h2i** | Hub → PCD | Hub requests CRO clock from PCD | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_CRO_CLK_req_h2i` |
| C4 | **CRO_CLK_ack_i2h** | PCD → Hub | PCD acknowledges CRO clock request | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_CRO_CLK_ack_i2h` |
| C5 | **OCB_CLK_req_h2i** | Hub → PCD | Hub requests RTC/OCB clock from PCD | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_OCB_CLK_req_h2i` |
| C6 | **pmc_wake_clk_req** | PCD ↔ Hub | PMC wake clock request handshake | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_pmc_wake_clk_req` |
| C7 | **pmc_wake_clk_ack** | PCD ↔ Hub | PMC wake clock acknowledge handshake | `pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_pmc_wake_clk_ack` |

---

## Known Signal Paths (documented in sle_dut.utf and JEM tracker)

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

### Cross-die clock request paths (all on d2d_iiosf):
```
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_XTAL_CLK_req_h2i  (Hub→PCD)
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_XTAL_CLK_ack_i2h  (PCD→Hub)
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_CRO_CLK_req_h2i   (Hub→PCD)
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_CRO_CLK_ack_i2h   (PCD→Hub)
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_OCB_CLK_req_h2i   (Hub→PCD)
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_pmc_wake_clk_req
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_pmc_wake_clk_ack
```

### IOSF SB link path (PCD side):
```
pcd.pard2dittif.pard2dittif_pwell_wrapper.d2d_iiosf.d2d_iiosf_sb_link
  └── d2d_pma_sb_controller.PMA_FSM_state[5:0]  (physical link management)
  └── sb_link_rst_b                               (SB link reset)
  └── d2d_sb_link_secure_est_in_prog              (security handshake)
```

### IOSF SB link path (Hub side):
```
{HUB_TOP}.titan.par_d2d_pcd.d2d_hiosf_top.d2d_hiosf_sb_link
  └── d2d_sb_ll.d2d_sbb_hb.SBHB_REGS_HIOSF...registers.hbsb_chicken_bits_1
```

### pmsync/pmdown path (Hub punit internal):
```
HUB.titan.par_punit.punit.punit_inf_st_top.punit_io_regs_inf_st
  └── PunitIOoutput_punit_inf_st_top.io_pmsync_pmdown_own_req_ack.pmsync_pmdown_own_req
  └── PunitIOoutput_punit_inf_st_top.io_pmsync_pmdown_own_req_ack.pmsync_pmdown_own_ack
  └── PunitIOoutput_punit_inf_st_top.io_ip_driver_fsm_state_hub2pcd_d2d_pma.state[4:0]
```

---

## Step 1: RTL Source Check (pre-elab)

Search the RTL source for port declarations and connections. This can be done at any time (no elab required).

### 1a: Check Group A — Reset/Power signals in RTL

```bash
# epd_on — PCD side origin
grep -rn "epd_on" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.utf" --include="*.py" | grep -v ".ref\|.pyc\|__pycache__" | head -20

# epd_on — Hub side destination
grep -rn "xx_hub_epd_on\|hub_epd_on" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -10

# Package level — bdie passthrough
grep -rn "pcd_epd_on\|hub_epd_on" $WORKAREA/integration/ --include="*.sv" --include="*.v" 2>/dev/null | head -10

# cold/warm boot trigger
grep -rn "cold_boot_trigger\|warm_boot_trigger" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" | grep -v ".ref\|.pyc" | head -20

# pwrgd
grep -rn "vdd2_pwrgd\|vnnaon_powergood\|xxvdd2_pwrgd" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -15

# pltrst
grep -rn "pltrst\|pltreset\|opltrst" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" | grep -v ".ref\|.pyc" | head -15

# pmsync_pmdown (Hub internal)
grep -rn "pmsync_pmdown\|pmdown_own" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -10

# D2D PMA FSM state
grep -rn "ip_driver_fsm_state_hub2pcd\|d2d_pma.*state" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -10
```

### 1b: Check Group B — IOSF SB structural path

```bash
# PCD-side d2d_iiosf_sb_link module instantiation
grep -rn "d2d_iiosf_sb_link\|d2d_iiosf.*sb_link" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" | grep -v ".ref\|.pyc" | head -15

# GPSB ISM fabric/agent state signals
grep -rn "iosfsb_gpsbb_side_ism" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" | grep -v ".ref\|.pyc" | head -10

# SB link reset
grep -rn "sb_link_rst_b" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" | grep -v ".ref\|.pyc" | head -10

# Hub-side d2d_hiosf_sb_link
grep -rn "d2d_hiosf_sb_link\|d2d_hiosf_top" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -15

# PMA SB controller (manages physical D2D link)
grep -rn "d2d_pma_sb_controller\|PMA_FSM_state" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" | grep -v ".ref\|.pyc" | head -10
```

### 1c: Check Group C — Cross-die clock requests

```bash
# XTAL clock request/ack
grep -rn "XTAL_CLK_req\|XTAL_CLK_ack\|xtal_clkreq" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -15

# CRO clock request/ack
grep -rn "CRO_CLK_req\|CRO_CLK_ack\|cro_clkreq" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -15

# OCB/RTC clock request
grep -rn "OCB_CLK_req\|rtc_clkreq" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -10

# PMC wake clock handshake
grep -rn "pmc_wake_clk" $WORKAREA/src/val/emu/ --include="*.sv" --include="*.v" --include="*.py" | grep -v ".ref\|.pyc" | head -10
```

### 1d: Check for dangerous force assigns / tieoffs on all checked signals

> ⚠️ **CRITICAL**: Accidental force assigns on reset IO pads have caused boot failures before (see sle_dut.utf ww17 2026 incident).

```bash
# Check for force assigns that might kill reset/power signals
grep -rn "force.*epd_on\|force.*pwrgd\|force.*boot_trigger\|force.*pltrst\|force.*slp_s[345]" $WORKAREA/src/val/emu/build_cfg/ --include="*.utf" --include="*.tcl" --include="*.py" | grep -v ".ref\|.pyc\|#.*force" | head -20

# Check for force assigns on clock request signals
grep -rn "force.*CLK_req\|force.*CLK_ack\|force.*clkreq\|force.*wake_clk" $WORKAREA/src/val/emu/build_cfg/ --include="*.utf" --include="*.tcl" --include="*.py" --include="*.v" | grep -v ".ref\|.pyc\|#.*force" | head -15

# Check for force assigns on SB link signals
grep -rn "force.*sb_link\|force.*ism_fabric\|force.*ism_agent\|force.*PMA_FSM" $WORKAREA/src/val/emu/build_cfg/ --include="*.utf" --include="*.tcl" --include="*.py" | grep -v ".ref\|.pyc\|#.*force" | head -10

# Check for broad io pad tieoffs that could catch reset signals
grep -rn "io1p2.*value.*0\|io1p8.*value.*0\|xio_pad.*value.*0" $WORKAREA/src/val/emu/build_cfg/ --include="*.utf" --include="*.tcl" | grep -v ".ref\|#" | head -10

# Check pcd_tb.v for clkreq force statements (these are expected but verify values)
grep -n "clkreq_forcible\|CLK_req_h2i\|CLK_ack" $WORKAREA/src/val/emu/rtlchanges/pcd*/emu/pchlp/pcd_tb/pcd_tb.v 2>/dev/null | head -15
```

**If any active (uncommented) force assign targets a reset/clock signal → FLAG AS CRITICAL and alert the user immediately.**

> ⚠️ **Expected force in pcd_tb.v**: The config-R reduced model forces `d2d_hiosf_XTAL_CLK_req_h2i`, `d2d_hiosf_CRO_CLK_req_h2i`, `d2d_hiosf_OCB_CLK_req_h2i` to 0 (via `compute_xtal_clkreq_forcible` etc.). This is intentional for the reduced-PCD model — verify that these forces have matching `release` logic or are only active when hub_model is disabled.

---

## Step 2: Elab Output Verification (post-elab)

After the analyze stage completes, verify signals in the elaborated design.

### 2a: Check for unconnected ports in elab logs (all groups)

```bash
ZSE5_OUT="$WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5"

# Group A — Reset/Power
grep -i "unconnected\|floating\|undriven" $ZSE5_OUT/log/*/elab.log 2>/dev/null | grep -i "epd_on\|boot_trigger\|pwrgd\|pltrst\|pmsync\|pmdown" | head -20

# Group B — IOSF SB
grep -i "unconnected\|floating\|undriven" $ZSE5_OUT/log/*/elab.log 2>/dev/null | grep -i "sb_link\|ism_fabric\|ism_agent\|PMA_FSM\|hiosf" | head -20

# Group C — Clock requests
grep -i "unconnected\|floating\|undriven" $ZSE5_OUT/log/*/elab.log 2>/dev/null | grep -i "CLK_req\|CLK_ack\|clkreq\|wake_clk" | head -20
```

### 2b: Verify key modules/signals exist in analyzed libraries

```bash
# Group A signals
grep -rn "epd_on\|cold_boot_trigger\|warm_boot_trigger\|vdd2_pwrgd\|pltrst\|pmsync_pmdown" $ZSE5_OUT/analyzed_libs/ 2>/dev/null | head -20

# Group B — SB link modules
grep -rn "d2d_iiosf_sb_link\|d2d_hiosf_sb_link\|sb_link_rst_b\|ism_fabric" $ZSE5_OUT/analyzed_libs/ 2>/dev/null | head -15

# Group C — Clock request signals
grep -rn "XTAL_CLK_req\|CRO_CLK_req\|OCB_CLK_req\|pmc_wake_clk" $ZSE5_OUT/analyzed_libs/ 2>/dev/null | head -15
```

### 2c: Check probes.py force/monitor entries match expected signals

```bash
# Hub probes — should have force entries for epd_on and cold_boot_trigger
grep -n "epd_on\|cold_boot_trigger\|warm_boot_trigger\|pwrgd\|pltrst\|pmsync\|pmdown" $WORKAREA/src/val/emu/build_cfg_overrides/probes_hubbx/probes.py 2>/dev/null | grep -v ".ref"

# SLE workarounds — check epd_on bypass assign and SB chicken_bits
grep -n "epd_on\|sb_link\|hbsb_chicken\|CLK_req\|clkreq" $WORKAREA/src/val/emu/build_cfg/probes_pkg/sle_workarounds.py 2>/dev/null | grep -v ".ref"
```

Expected entries (if present, connectivity is confirmed at probe level):
- `force(f"{HUB}.xx_hub_epd_on")` ← Hub receives epd_on
- `force(f"{par_miscio}.xx_hub_epd_on")` ← Package-level passthrough
- `force(f"{par_d2d_pcd}.yy_hub_pm_cold_boot_trigger")` ← Hub receives cold_boot
- `assign(src=..., dst=f"tb_top.pkg.pcd_epd_on")` ← SLE epd_on bypass (sle_workarounds.py)
- `force(f"...d2d_hiosf_sb_link...hbsb_chicken_bits_1...")` ← SB link accessible

### 2d: Verify JEM tracker (d2d_iiosf) is present in elab

The `pch_d2d_iiosf_jem_tracker` monitors all Group B and C signals at runtime. If it elaborated successfully, the d2d_iiosf interface is connected:

```bash
# Check if the JEM tracker compiled without errors
grep -i "pch_d2d_iiosf_jem_tracker" $ZSE5_OUT/log/*/elab.log 2>/dev/null | head -5

# If present, confirms: sb_link, GPSB ISM, clk_req, clk_ack, PMA_FSM are all connected
```

---

## Step 3: Report Results

Present a summary table to the user:

```
CONNECTIVITY CHECK RESULTS
═══════════════════════════════════════════════════════════════════════════════
GROUP A — RESET/POWER SIGNALS
Signal                  RTL Source    Elab Verify    Force/Tieoff    Status
─────────────────────────────────────────────────────────────────────────────
epd_on                  [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
vdd2_pwrgd              [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
cold_boot_trigger       [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
warm_boot_trigger       [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
pltrst                  [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
pmsync_pmdown_req       [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
pmsync_pmdown_ack       [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
d2d_pma_fsm (hub2pcd)  [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]

GROUP B — IOSF SIDEBAND STRUCTURAL PATH
Signal                  RTL Source    Elab Verify    Force/Tieoff    Status
─────────────────────────────────────────────────────────────────────────────
gpsb_ism_fabric (PCD)   [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
gpsb_ism_agent (PCD)    [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
sb_secure_est_in_prog   [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
sb_link_rst_b           [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
PMA_FSM_state (PCD SB)  [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
d2d_hiosf_sb_link (Hub) [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
hbsb_chicken_bits_1     [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
JEM tracker (d2d_iiosf) [present/missing]                             [PASS/FAIL]

GROUP C — CROSS-DIE CLOCK REQUESTS
Signal                  RTL Source    Elab Verify    Force/Tieoff    Status
─────────────────────────────────────────────────────────────────────────────
XTAL_CLK_req_h2i        [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
XTAL_CLK_ack_i2h        [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
CRO_CLK_req_h2i         [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
CRO_CLK_ack_i2h         [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
OCB_CLK_req_h2i         [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
pmc_wake_clk_req        [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
pmc_wake_clk_ack        [✓/✗]         [✓/✗]          [SAFE/DANGER]   [PASS/FAIL]
═══════════════════════════════════════════════════════════════════════════════
```

### Result interpretation:
- **RTL Source**: Signal name found in RTL files with proper assign/connection
- **Elab Verify**: No unconnected/floating warnings; signal present in analyzed_libs
- **Force/Tieoff**: No active force assign/tieoff that would kill the signal (expected forces like pcd_tb.v clkreq marked SAFE)
- **PASS**: All three columns are clean
- **FAIL**: Any column has an issue → alert user with details
- **JEM tracker**: If `pch_d2d_iiosf_jem_tracker` elaborated without errors, all Group B/C signals on PCD d2d_iiosf are structurally connected

### If any signal FAILs:
1. Report the specific file and line where the problem is
2. Cross-reference with sle_dut.utf to understand the expected signal path
3. Check if a recent rtlchange or force assign modification caused the break
4. Suggest the fix (e.g., remove errant tieoff, add missing connection)

### Note on IOSF SB Message Tracing:
Individual IOSF sideband *messages* (doorbell writes, power management commands, etc.) cannot be verified at build/elab time — they are runtime protocol transactions. This check verifies only that the **hardware path** (d2d_iiosf_sb_link, d2d_hiosf_sb_link modules) is structurally connected. Runtime SB message flow debugging uses the JEM tracker and IOSF SB tracker at emulation time (see `emu-ipc-doorbell-debug` and `emu-hung-transaction-debug` skills).

---

## Summary Checklist

| Step | Action | When |
|------|--------|------|
| 1a | RTL source grep for Group A reset/power signals + force check | Any time (pre-elab OK) |
| 1b | RTL source grep for Group B IOSF SB structural path | Any time (pre-elab OK) |
| 1c | RTL source grep for Group C cross-die clock requests | Any time (pre-elab OK) |
| 1d | Force assign / tieoff safety check (all groups) | Any time (pre-elab OK) |
| 2a | Elab output — unconnected ports check (all groups) | After analyze stage |
| 2b | Elab output — analyzed_libs signal presence | After analyze stage |
| 2c | Probes.py cross-reference | After analyze stage |
| 2d | JEM tracker elab check (confirms Group B+C structurally) | After analyze stage |
| 3 | Report results table to user | After Steps 1-2 complete |
