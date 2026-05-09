---
name: sle-build-zebu-driverclock-debug
description: "Debug ZeBu emulation driverClk slowness on ZSE5 builds. USE WHEN: driverClk is slow, analyzing zTime.log or zTime_fpga.log, identifying timing bottlenecks, recommending zforce/zgate/clock_boundary_marker fixes for emulation speed. Covers: timing path analysis, signal-to-RTL mapping, compositeClk zgates, zforce -type global, clock_boundary_marker for FASTCLOCK suppression (blocked in ZFAST V-2024.03-1.7), force assign tieoff DEPRECATED for PCD IO pads, DPO fan-out issues, FASTCLOCK_GENERIC auto-detected clock DPO, SCC reduction, SCC loop breaking (-safe_break_pp, -explore_latches), ts_clkbus infrastructure paths, thermtrip wildcards, ISCLK clock handling, PCD IO probe pad clock misdetection, verifying previous driverClk fixes, temporary workarounds (EDIF name force assign, zPar seed randomization). Also covers: driverClk optimization analysis (IP stubbing assessment, clustering constraint analysis, SCC rejected loop diagnosis, DDR PHY analog mux tieoff, post-DPO-fix ceiling estimation). Also covers: non-deterministic placement risk (same workspace producing 612 kHz and 10 kHz from identical FASTCLOCK DPO). Also covers: ProbesLib assign() bypass Option D for GPIO V pads — TX direction (output: txdata→port) and RX direction (input: port→rxdata), DVP probe prevention at VCS compile time, pwrbtn_b/batlow_b input signal bypass, ttlhm_n2p DUT variant probe naming differences."
argument-hint: "Describe the driverClk issue: current speed, model name, and build path"
---

# ZeBu driverClk Debug Skill

## When to Use
- driverClk is unexpectedly slow (< expected kHz) on a ZeBu ZSE5 emulation build
- Need to analyze `zTime.log` (pre-FPGA) or `zTime_fpga.log` (post-FPGA) timing reports
- Need to identify root cause signals and recommend fixes (zforce/zgate)
- Comparing timing across model variants (e.g., with/without PCD, with/without cfgr)
- Estimating speed improvement from proposed fixes

## Key Concepts

See [reference guide](./references/driverclock-analysis-guide.md) for the full methodology with worked examples.

## Quick Procedure

### Step 1: Locate Timing Logs
```
# Pre-FPGA timing (from zTopBuild/zPar):
<build>/zse5/zcui.work/zebu.work/zTime.log
<build>/zse5/zcui.work/zebu.work/zPar.log

# Post-FPGA timing (from Vivado backend):
<build>/zse5/zcui.work/backend_default/zTime_fpga.log
<build>/zse5/zcui.work/backend_default/zPar.log
```

### Step 2: Extract Summary Metrics
```bash
grep -E "driverClk|kHz|Critical|Constant|Multiplexed|pathUndefined|theoretical" zTime_fpga.log
```
Key metrics: driverClk frequency, critical path delay (ns), constant vs multiplexed parts, pathUndefined count.

### Step 3: Identify Source Diversity
```bash
# Count unique sources in timing paths
grep "dvrCk" zTime.log | awk -F'|' '{print $8}' | sort -u | wc -l
# If all 100 paths share ONE source → single signal bottleneck (fixable)
# If paths have diverse sources → systemic/infrastructure issue (harder)
```

### Step 4: Trace Source to RTL
- **zcbsplt_* signals**: Look up in HTML timing reports (`ztime_out_paths*.html`) for gate-level trace
- **zext_p_* signals**: External ports — check `zTime_fpga.log` for "VIVADO DELAY : max delay fall back on zext_p_NNNNN" for RTL path
- Cross-reference with `zTopBuild_report.log` and `zRtlToEqui.log`

### Step 5: Classify and Fix
See the [fix patterns reference](./references/fix-patterns.md) for detailed fix recipes.

| Root Cause | Fix | Expected Improvement |
|---|---|---|
| Wildcard zgate creating DPO fan-out | `zforce -type global` on the signal | 25-50x (e.g., 19 kHz → 800+ kHz) |
| FASTCLOCK_GENERIC auto-detected clock DPO | **Option D: ProbesLib `assign()` bypass** (preferred, proven ww18 2026). `clock_boundary_marker -module {<mod>} -signal {<rtl_wire>}` is the permanent fix but **BLOCKED** in ZFAST V-2024.03-1.7. `zforce -type global` does **NOT** work. `force assign -value 0` is **DEPRECATED** (ww17 2026 EPD_ON boot failure). | **95x confirmed** (10 kHz → 952 kHz with EPD_ON bypass alone) |
| Missing compositeClk on async clock | `zgate fd -clock_name compositeClk` | 2-5x |
| ts_clkbus infrastructure paths | None (ZeBu system limit) | N/A |
| SCC/combinational loop | SCC reduction or `zforce` to break loop | Variable |

- **Note:** For `FASTCLOCK_GENERIC` auto-detected clock DPO, cover all analog probe signals proactively. Even "healthy" models may have the same DPO and only appear unaffected due to lucky placement.
- **CRITICAL — Pad Tieoff Safety (ww17 2026 lesson)**: PCD IO pad modules (`io1p2`, `io1p8weak_ll_ls`, `io1p8ll`, `gpio1p0ff`) carry BOTH probe pads AND functional signals. A `force assign -value 0` on a functional pad will SILENTLY KILL the signal — verified to cause boot failure when `xxpcd_epd_on.io1p2_inst.xio_pad_1p2` was tied to 0 (broke EPD_ON propagation from PCD→BDIE→HUB, hub bootfsm stuck in IDLE). **NEVER use broad wildcard patterns** like `*.*.*.*.io1p2_inst.xio_pad_1p2` — this matches ALL io1p2 instances. Instead, target ONLY known non-functional instances by wrapper name (e.g., `xxdbg_pmode`, `xxjtagx`, `xxprdy_b`, `xxpreq_b`). Similarly, `*.*.*.*.io1p8weak_ll_ls_inst.xio_pad_1p8` would kill power sequencing signals (`slp_s3_b`, `slp_s5_b`, `pwrbtn_b`, `batlow_b`, `thermtrip_b`). Always check what signal the wrapper instance carries before applying a tieoff.
- **CRITICAL: RTL vs Synthesis Names**: The signal names in FASTCLOCK detection logs (e.g., `probe_xio_pad_1p2_NNN.unnamed_NN`) are **synthesis-generated names**, NOT RTL names. `force assign -rtlname` CANNOT match them — no wildcard pattern will work. You must look up the actual RTL name in `RTLDB/NameDir/<module>.namemap.gz` (e.g., `io1p2.namemap.gz` → `xio_pad_1p2`). The wrapper module may use a different name (e.g., `pad`), but `pad` is on the **wrapper instance** (e.g., `xxpcd_epd_on`), NOT on the inner module instance (`io1p2_inst`). Target the inner module's RTL wire: `io1p2_inst.xio_pad_1p2`, not `io1p2_inst.pad`.
- **CRITICAL: fnmatch '.' behavior**: ZeBu fnmatch treats `.` as a hierarchy separator — `*` does NOT match across `.` boundaries. To reach a signal 5 levels deep, you need `*.*.*.*.*` (one `*` per level), not a single `*`. Example: `pcd.*signal*` only matches direct children of `pcd`, not grandchildren.
### Step 6: Validate Fix Estimate
Compare with reference models that don't have the bottleneck. The reference model's driverClk is the ceiling for your fix.

### Step 7: Verify Previous Fixes Still Active
When analyzing a new build, always confirm prior driverClk fixes are working:
1. Check that previously-fixed signals (e.g., thermtrip) do NOT appear in the 100 worst paths
2. Verify `zforce -type global` entries in `zTopBuild.log` by grepping for the forced signal names
3. Verify `force assign -value 0` tieoffs were consumed (grep for the signal name in zTopBuild.log)
4. Verify `zgate fd -clock_name compositeClk` entries were consumed (grep for the module/signal in zTopBuild.log)
5. If a previously-fixed bottleneck reappears, the fix was not loaded — check UTF/TCL sourcing order
6. **CRITICAL**: If `zforce -type global` is present for a FASTCLOCK signal but timing is still bad, the fix is wrong — `zforce` does NOT suppress FASTCLOCK auto-detection. Replace with `force assign -value 0` (tieoff) **BUT ONLY after verifying the signal is non-functional** (see item 7b).
7. **LATENT RISK — RESOLVED by Option D**: A model with healthy driverClk (e.g., 1029 kHz or even 612 kHz) may still have the same FASTCLOCK DPO — cross-model analysis shows all PCD models detect `probe_xio_pad` as FASTCLOCK, but "healthy" models got lucky with zPar placement (8-13 hops vs 290-1050 hops). **Confirmed**: Build 2 (612 kHz) and Build 4 (10 kHz) from the same c15a workspace, same model config, same FASTCLOCK DPO instance (`_762434205.unnamed_28`) — only differed in zPar placement randomness. Any rebuild can crater driverClk. **RESOLVED (ww18 2026)**: Option D ProbesLib bypass eliminates the DPO's timing impact regardless of placement. Build with EPD_ON bypass achieved 952 kHz even with the same FASTCLOCK_GENERIC_29 still detected. Apply Option D proactively to all new builds.
7b. **CRITICAL (ww17 2026): NEVER apply `force assign -value 0` without verifying signal functionality**. The `xxpcd_epd_on.io1p2_inst.xio_pad_1p2` tieoff broke all cfgr model boots by killing functional EPD_ON. PCD IO pad modules (`io1p2`, `io1p8weak_ll_ls`, `io1p8ll`, `gpio1p0ff`) carry both probe pads AND functional signals (power sequencing, JTAG, power good). Always identify the wrapper instance name and map it to its signal before tieoff. Also verify the fnmatch pattern actually reaches the target — `pcd.*aprobe*` matches NOTHING because aprobe modules are 4-6 levels deep (fnmatch `*` doesn't cross `.`).
8. **CRITICAL: Check for HFA001 warnings AND verify match**: After every build, grep `zTopBuild.log` for `HFA001` ("No object is matching"). A `force assign` that silently fails means the fix isn't active. **BUT absence of HFA001 doesn't guarantee correctness** — with `-object_not_found warning`, a pattern that matches nothing will also produce no HFA001. Verify that the pattern actually matched the intended signal by checking if the FASTCLOCK entry disappeared from `zTopBuild_SDC_clock_report.log`. Common causes of dead patterns:
   - **Synthesis vs RTL name mismatch**: The signal name from FASTCLOCK detection (e.g., `probe_xio_pad`) is a SYNTHESIS name that doesn't exist in the RTL namespace. Look up the actual RTL name in `RTLDB/NameDir/<module>.namemap.gz`.
   - **fnmatch `*` can't cross `.` boundaries**: `pcd.*signal*` only matches ONE level deep under `pcd`. Use multi-level wildcards (`pcd.*.*.*.*.*signal`) for deeper signals.
   ```bash
   grep "HFA001" <build>/zse5/zcui.work/zebu.work/zTopBuild.log
   # Any matches → that force assign is DEAD, investigate RTL name vs synthesis name
   ```
9. **`clock_boundary_marker` — CORRECT FIX but BLOCKED in ZFAST V-2024.03-1.7**:
   ```tcl
   # Correct permanent fix — suppresses FASTCLOCK detection without tieoff.
   # Commented out in sle_dut.utf — uncomment after tool upgrade.
   #clock_boundary_marker -module {io1p2} -signal {xio_pad_1p2}
   #clock_boundary_marker -module {io1p8weak_ll_ls} -signal {xio_pad_1p8}
   #clock_boundary_marker -module {io1p8ll} -signal {xio_pad_1p8}
   #clock_boundary_marker -module {gpio1p0ff} -signal {xio_pad_1p0}
   ```
   **Status**: ZFAST translates `clock_boundary_marker` into a `$clock_boundary_marker_task` system task embedded in the VCS simulation model. During Bundle synthesis, ZFAST encounters the system task and crashes: `fatal error in ZFAST: Unsupported System Task $clock_boundary_marker_task (<internal>, line 0)`. Additionally, the UTF-to-TCL generation drops the `-signal` argument (utf_db.xml preserves it, but new_zTopBuild_config.tcl only emits `-module`).
   **Confirmed**: Build `pkg_chpr_cfgr_p2e0_816_fast` (c15a, 24-Apr-2026) failed at Bundle 990 synthesis on module `io1p2` due to this.
   **Why not `force assign -value 0`**: DEPRECATED (ww17 2026). PCD IO pad modules carry both probe AND functional signals. Broad wildcard tieoffs silently kill functional signals (e.g., EPD_ON → boot failure). Instance-specific tieoffs are fragile and require auditing every wrapper instance. `clock_boundary_marker` is the only solution that suppresses FASTCLOCK without affecting signal value.
   **Why not `zforce -type global`**: Does NOT work. `zforce` only changes routing strategy; it does NOT suppress FASTCLOCK auto-detection. The clock filter DPO is still created and still fans out to all FPGAs.
   **Action**: All four `clock_boundary_marker` directives are pre-staged (commented out) in `sle_dut.utf`. Uncomment after ZeBu tool upgrade that fixes `$clock_boundary_marker_task` support.

### Step 7a: Debug RTL-vs-Synthesis Name Mismatches
When `force assign -rtlname` gets HFA001 but the FASTCLOCK clearly exists:
1. **Identify the module containing the signal**: Extract the module name from the FASTCLOCK path (e.g., `io1p2_inst` → module `io1p2`)
2. **Look up RTL names**: `zcat RTLDB/NameDir/<module>.namemap.gz | grep <signal_fragment>`
3. **Check wrapper modules**: The module may be instantiated through a buffer wrapper (visible in `edifListScript.tcl`) with different port names. **CRITICAL**: wrapper ports (e.g., `pad`) live on the *wrapper instance* (e.g., `xxpcd_epd_on`), NOT on the inner module instance (`io1p2_inst`). 
4. **Use `force assign`** targeting the **inner module's RTL wire** at the inner instance level, NOT the wrapper port:
   - CORRECT: `...xxpcd_epd_on.io1p2_inst.xio_pad_1p2` (wire 27 on `io1p2` module)
   - WRONG: `...xxpcd_epd_on.io1p2_inst.pad` (wire 29 is on wrapper `xxpcd_epd_on`, not on `io1p2_inst`)
   - WRONG: `...xxpcd_epd_on.io1p2_inst.*probe_xio_pad*` (synthesis name, not in RTL namespace)
5. **Prefer `clock_boundary_marker`** over `force assign -value 0` — it suppresses FASTCLOCK detection without tying off the signal. Currently blocked in ZFAST V-2024.03-1.7 (see Step 7, item 9). All four directives are pre-staged (commented out) in `sle_dut.utf` — uncomment after tool upgrade.
6. **Do NOT use `force assign -value 0` on PCD IO pads** (DEPRECATED ww17 2026). The `xxpcd_epd_on.io1p2_inst.xio_pad_1p2` tieoff killed the functional EPD_ON signal (PCD→HUB power sequencing), breaking all cfgr model boots. PCD IO pad modules carry both probe AND functional signals. Broad wildcards are unsafe, and instance-specific tieoffs are fragile. Wait for `clock_boundary_marker` tool fix.
7. **Do NOT use `zforce -type global` for FASTCLOCK DPO** — it only changes routing strategy, does NOT suppress FASTCLOCK auto-detection. The clock filter DPO is still created.

## Advanced: driverClk Optimization (Beyond Bug Fixes)

After fixing known bottlenecks (probe DPO, thermtrip, compositeClk), use this
section to assess whether IP stubbing or clustering can further improve driverClk.

See the [full optimization analysis report](./references/driverclock-optimization-report.md) for detailed data from c09e and ww09e models.

### Step 8: Analyze Rejected SCCs
Rejected SCCs (combinational loops the tool couldn't break) constrain the partitioner:
```bash
# Get SCC summary
gunzip -k -f <build>/zse5/zcui.work/backend_default/zTopBuild_report_log_large_sections.dir/_SEC_33_SCC_Reduct.log.gz
head -15 _SEC_33_SCC_Reduct.log  # See total SCCs, rejected count

# Count rejected SCCs by IP
awk '/SCC Id.*Size/{id=$0} /Reject Reason/{print id}' _SEC_33_SCC_Reduct.log | head -20
grep -B0 -A10 "Reject.*Reason" _SEC_33_SCC_Reduct.log | grep "EDIF driver" | \
  sed 's/.*tb_top\.pkg\.\([^.]*\)\..*/\1/' | sort | uniq -c | sort -rn

# Alternatively, get SCC summary directly from zTopBuild.log:
grep -A10 "SCC_REDUCTION" <build>/zse5/zcui.work/zebu.work/zTopBuild.log
```

**Example SCC reduction report (Build 4, c15a pkg_chpr_cfgr_p2e0_816_fast)**:
```
SCC_REDUCTION : Number of SCCs detected   : 37788
SCC_REDUCTION : Number of SCCs broken      : 37671
SCC_REDUCTION : Safe-Break (Replication)   : 37671 (Deterministic: 99, State-Holding: 37510, Oscillatory: 57, Unknown: 5)
SCC_REDUCTION : Rejected                   : 117   (Deterministic: 0, State-Holding: 0, Oscillatory: 0, Unknown: 117)
SCC_REDUCTION : Design size                : (LUT: 142,782,466, REG: 58,858,740)
SCC_REDUCTION : Resources used for SCC reduction: (LUT: 2,239,453, REG: 0, Break-Registers: 362,457)
```

**Pre-reduction SCC analysis** (from SCCAnalysis step in zTopBuild.log):
```
SCCAnalysis : Total number of SCCs : 1221
SCCAnalysis : SCC gates statistics : Min: 1 | Max: 11850 | Average: 102 | Median: 2181
```
Note: The pre-reduction count (1,221) is much lower than the post-reduction count (37,788) because the loop break algorithm decomposes large SCCs into smaller ones before breaking.

### Step 8a: Understanding `-safe_break_pp` and `-explore_latches`

These are **SCC loop breaking** directives, NOT related to FASTCLOCK DPO. They address combinational feedback loops in the design.

**Three loop break passes in the generated dut.utf** (executed sequentially):
1. `loop break -safe_break ...` — Standard safe loop breaking (first pass, from base config)
2. `loop break -safe_break_pp -explore_latches ...` — Enhanced post-processing (Issue #85, DDG-SNPS OualidX)
3. `loop break -safe_break ... -format=all -generate_zvdb` — Final pass for Verdi visualization

**`-safe_break` vs `-safe_break_pp`**:
- **`-safe_break`**: ZeBu's standard algorithm for breaking combinational loops. Inserts pipeline registers (break registers) at logic points where breaking is functionally safe. Classifies each SCC as: deterministic (always converges), state-holding (emulates a latch), oscillatory (rings), or unknown.
- **`-safe_break_pp`**: "Post-Processing" enhanced variant. After initial break-point selection, runs additional optimization passes that re-examine break points to minimize area overhead (LUT/register usage). Upgraded from `-safe_break` per Issue #85.

**`-explore_latches`**: Tells the loop breaker to model **latch transparency**. Without it, only pure combinational loops are analyzed. With it:
- Transparent latches that create combinational feedback during their active phase are detected
- Latch boundaries become candidate break points
- Can reduce total SCC count by finding natural break points at latch edges

This pairs with the `ZFILTER_LATCH_PATH` timing analysis later in the build:
```tcl
ztopbuild -advanced_command {zcorebuild_command * {timing -analyze ZFILTER_LATCH_PATH}}
ztopbuild -advanced_command {clock_localization -stop_at_latch_input = no}
```

**Key flags in the loop break command**:
| Flag | Purpose |
|---|---|
| `-max_lut_overflow=5` | Max LUT overhead per break point (5%) |
| `-max_reg_overflow=5` | Max register overhead per break point (5%) |
| `-rtl=yes` | Report break points using RTL names (for Verdi debug) |
| `-consider_oscillatory_sccs=safe_break` | Also break oscillatory SCCs safely |
| `-override_unknown_behavior_scc=yes` | Force-break SCCs with unknown behavior |
| `-localize_copies_to_data_loads` | Place break-register copies near data consumers (reduces routing pressure) |

**Relationship to driverClk**: SCC loop breaking is **orthogonal** to FASTCLOCK DPO. Breaking more SCCs improves partition quality (fewer constraints on zPar), which can indirectly improve timing by 50-100 ns, but the primary driverClk bottleneck is typically the FASTCLOCK DPO (91,331 ns in Build 4) — SCC improvements are negligible in comparison.

**Key finding from cross-model analysis**: DDR PHY TX analog (`pitxana.pimux`) generates the majority of rejected SCCs in some RTL snaps (117 in c09e vs 5 in ww09e). These are analog feedback loops that don't affect timing paths but constrain partitioning. The fix:
```tcl
force assign -value 0 {*pitxana*pimux*}
```

### Step 9: Assess IP Stubbing
IP stubbing is **rarely beneficial** for driverClk:
- It reduces area (fewer FPGAs) but doesn't shorten critical paths
- After the probe DPO fix, remaining paths are typically 3-4 hops within a single board
- Stubbing an IP disconnects functional paths — only viable for unused IPs
- **Exception**: If a specific IP generates massive rejected SCCs AND those SCCs appear in timing paths, targeted tieoffs (not full stubbing) of the analog feedback signals are preferred

### Step 10: Assess Clustering Constraints
Clustering constraints are **rarely beneficial** for these models:
- The partitioner already uses `system_level_reg_weighting_cost` and `ctrl_set_reg_weighting`
- Cross-model analysis shows all FPGAs have `PLACE_NO_CONSTRAINT` and non-DPO timing paths are already within single boards (3-4 hops)
- Adding constraints reduces partitioner freedom and can **worsen** timing
- Only consider clustering if non-DPO paths cross multiple boards (>6 hops)

### Step 11: Estimate Post-Fix Ceiling
```bash
# Check non-DPO paths (if visible in top 100):
grep "^# |" zTime_fpga.log | grep -E '^\# \|[[:space:]]+[0-9]' | \
  awk -F'|' '{print $8}' | sort | uniq -c | sort -rn
# If ALL 100 are from one source → DPO dominates, use zPar theoretical as ceiling
# If some paths from different sources → those delays are the post-fix ceiling

# zPar theoretical (pre-FPGA, ignoring clock skew):
grep "theoretical.*ignoring" <build>/zse5/zcui.work/backend_default/zPar.log
```

### Step 12: Temporary Workarounds While `clock_boundary_marker` is Blocked

When `clock_boundary_marker` is unavailable (ZFAST V-2024.03-1.7 bug) and `force assign -value 0` is unsafe (functional IO pad signals), consider these temporary workarounds in order of preference:

#### Option A: Target synthesis-generated probe cell via EDIF name (Experimental)

Since `probe_xio_pad_1p2` only exists in the synthesis namespace, `force assign` **without** `-rtlname` might resolve it directly:
```tcl
# EXPERIMENTAL: Target synthesis probe cell output directly
# probe_xio_pad_1p2 is non-functional (analog observability only)
# Functional xio_pad_1p2 pad signal (EPD_ON) is NOT affected
force assign -fnmatch -object_not_found warning \
  tb_top.pkg.pcdpkg.pcd.pargpcom35.pargpcom35_pwell_wrapper.c76pxecfiottlpcdhcpujtag1family1.xxpcd_epd_on.io1p2_inst.probe_xio_pad_1p2_*.unnamed_* \
  -value 0
```
**Risks**:
- Unknown whether `force assign` without `-rtlname` resolves synthesis cell names in this tool version. All existing force assigns in this project use `-rtlname`.
- The `_762434205` hash suffix changes between synthesis runs — wildcard `_*` should handle this.
- Needs validation on a test build before production use.

#### Option B: zPar seed randomization
Add to the UTF to try different FPGA placement:
```tcl
zpar -advanced_command {System Global rng_seed 42}
```
**Risks**: Non-deterministic. May or may not improve placement. Build iteration cost is 12+ hours per attempt. Build 2 got 612 kHz with lucky placement; Build 4 got 10 kHz with unlucky placement from the same workspace and FASTCLOCK DPO.

#### Option C: Accept degraded driverClk until tool upgrade
The `clock_boundary_marker` lines are pre-staged (commented out) in `sle_dut.utf` (lines 99-102). Uncomment when the ZFAST version supporting `$clock_boundary_marker_task` is available. This is the only clean, permanent fix.

**Decision matrix**:
| Scenario | Recommendation |
|---|---|
| Build achieved >200 kHz (lucky placement) | Accept; but apply Option D proactively to prevent future regression |
| Build at 10-50 kHz, critical milestone | Apply Option D (bypass) — **proven 95x improvement** (10 kHz → 952 kHz) |
| Build at 10-50 kHz, non-critical | Apply Option D; wait for tool upgrade for permanent clock_boundary_marker fix (Option C) |
| Build at <10 kHz, blocking tests | Apply Option D immediately; if still slow, check for additional FASTCLOCK signals beyond xxgpp_v_9; escalate to Synopsys |
| **New builds (proactive)** | **Always include Option D bypasses** for all GPIO V io1p8weak_ll_ls pads — TX direction (slp_s*, thermtrip) AND RX direction (pwrbtn_b, batlow_b, ac_present, wake_b) — prevents non-deterministic driverClk regression |

#### Option D: ProbesLib assign() bypass of PCD IO pad signals (ww18 2026)

**Concept**: Instead of tying the io1p2/io1p8weak_ll_ls pad to 0 (which kills functional signals) or using `clock_boundary_marker` (blocked), bypass the analog pad entirely by connecting the digital `txdata` inside the buffer wrapper to the PCD-level inout port using ProbesLib `assign()`. This preserves signal functionality while eliminating the inout pad's analog logic from ZeBu's FASTCLOCK detection path.

**Key insight**: The bypass must connect `txdata` (digital TX before analog pad) to the PCD module's inout port — NOT to the `tb_top.pkg` level wire. Connecting the PCD inout port to pkg-level wire does nothing because it's the same signal (the port IS the wire). The bypass must cut out the `io1p8weak_ll_ls` analog logic that sits BETWEEN `txdata` and the inout port.

**Implementation** (in `sle_workarounds.py`):
```python
# EPD_ON bypass — proven working (ww17 2026, HSD 22022398478)
# src: txdata inside buffer wrapper (digital TX before io1p2 analog pad)
# dst: PCD module inout port (which connects through to pkg level)
assign(src=f"tb_top.pkg.pcdpkg.pcd.pargpcom35.pargpcom35_pwell_wrapper.c76pxecfiottlpcdhcpujtag1family1.xxpcd_epd_on.txdata",
       dst=f"tb_top.pkg.pcd_epd_on")

# GPP_V Family io1p8weak_ll_ls bypasses — slp_s*/thermtrip (ww18 2026)
# src: txdata inside gppvfamily1 buffer wrapper (digital TX before io1p8weak_ll_ls analog pad)
# dst: PCD module inout port
assign(src=f"tb_top.pkg.pcdpkg.pcd.pargpcom35.pargpcom35_pwell_wrapper.c76pxecfiottlpcdhgppvfamily1.xxgpp_v_4.txdata",
       dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_4_slp_s3_b")
assign(src=f"tb_top.pkg.pcdpkg.pcd.pargpcom35.pargpcom35_pwell_wrapper.c76pxecfiottlpcdhgppvfamily1.xxgpp_v_5.txdata",
       dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_5_slp_s4_b")
assign(src=f"tb_top.pkg.pcdpkg.pcd.pargpcom35.pargpcom35_pwell_wrapper.c76pxecfiottlpcdhgppvfamily1.xxgpp_v_9.txdata",
       dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_9_slp_s5_b")
assign(src=f"tb_top.pkg.pcdpkg.pcd.pargpcom35.pargpcom35_pwell_wrapper.c76pxecfiottlpcdhgppvfamily1.xxgpp_v_15.txdata",
       dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_15_thermtrip_b")
```
The `assign()` API (ProbesLib) probes both signals and emits:
`force assign -rtlname {dst} -source_rtlname {src} -disconnect`

This cuts out the io1p8weak_ll_ls analog pad logic (`xio_pad_1p8 = ipowergood ? (tx_mode ? itxin : 1'bz) : 1'bz`) and directly connects the PCD PMC's digital TX output to the PCD inout port, which then propagates to the package level and HUB.

**Hierarchy for GPP_V family pads** (from FASTCLOCK log and RTLDB):
```
tb_top.pkg.pcdpkg.pcd                                    ← PCD module (ttlpcdhpkg)
  .pargpcom35.pargpcom35_pwell_wrapper
    .c76pxecfiottlpcdhgppvfamily1                        ← GPP_V family module
      .xxgpp_v_N                                         ← buffer wrapper instance (c76pxecfiottlpcdhgppvfamily_buffer_wrapper_io1p8weak_ll_ls)
        .txdata                                          ← digital TX signal (wire 19) ← BYPASS SOURCE
        .pad                                             ← inout port to wrapper
        .io1p8weak_ll_ls_inst                            ← inner analog pad module
          .itxin                                         ← TX input (wire 5, driven from txdata)
          .xio_pad_1p8                                   ← inout pad (FASTCLOCK detected here)
          .probe_xio_pad_1p8_NNNNN.unnamed_NN           ← synthesis probe cell (FASTCLOCK_GENERIC source)
```

**WRONG approach** (does NOT bypass analog logic):
```python
# WRONG: PCD inout port → pkg wire. These are the SAME signal (port=wire).
# No analog logic is cut out.
assign(src=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_4_slp_s3_b", dst=f"tb_top.pkg.gpp_v_4_slp_s3_b")
```

**CORRECT approach** (bypasses analog pad):
```python
# CORRECT: txdata inside buffer wrapper → PCD inout port.
# Cuts out io1p8weak_ll_ls analog logic (xio_pad_1p8 assignment).
assign(src=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_4.txdata", dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_4_slp_s3_b")
```

**Architectural safety analysis for additional bypass candidates on io1p8weak_ll_ls pads**:

Per architectural specs (Power Delivery HAS, PCD-PCH Interface HAS, Reset HAS — queried via co-design ww18 2026):

| Signal (wrapper instance) | Pad Type | Direction | Driver During Reset | Safe to Bypass? |
|---|---|---|---|---|
| xxgpp_v_4_slp_s3_b | io1p8weak_ll_ls | SOC → Platform (unidirectional) | PCD PMC sole driver | YES — PCD output only |
| xxgpp_v_5_slp_s4_b | io1p8weak_ll_ls | SOC → Platform (unidirectional) | PCD PMC sole driver | YES — PCD output only |
| xxgpp_v_9_slp_s5_b | io1p8weak_ll_ls | SOC → Platform (unidirectional) | PCD PMC sole driver | YES — PCD output only |
| xxgpp_v_15_thermtrip_b | io1p8weak_ll_ls | SOC → Platform (unidirectional) | PCD PMC sole driver | YES — PCD output only |
| xxgpp_v_3_pwrbtn_b | io1p8weak_ll_ls | Platform → SOC (input) | Platform sole driver | YES — use RX bypass (port→rxdata) |
| xxgpp_v_0_batlow_b | io1p8weak_ll_ls | Platform → SOC (input) | Platform sole driver | YES — use RX bypass (port→rxdata) |

**Key architectural findings**:
- **SLP_S3#/S4#/S5#**: Architecturally **unidirectional outputs** from PCD (SOC → Platform). Listed in Power Delivery HAS interface table with `→` direction. The only bidirectional signal in the PD interface is SVID (`↔`). These are dedicated power sequencing outputs, NOT general-purpose bidirectional GPIOs, despite being on GPIO Family V pads.
- **EPD_ON ≡ SLP_S3#**: The Reset HAS explicitly states "epd_on wire is effectively SLP_S3#. PCD[0][PMC] uses SLP_S3# as their output wire name. It gets renamed at the HUB Die interface."
- **SLP_S4 controls Vdd2 rail**: Functional during S4/S5 entry — bypass must preserve the toggle.
- **Cross-die transport**: SLP_S3_B/S4_B/S5_B are also carried as PMC Virtual Wire messages (VW Index 0x10, bits 0/1/2) via eSPI from PCD.PMC to PCH.PMC. The GPIO pad path is the primary physical interface to the HUB.
- **pwrbtn_b / batlow_b**: These are platform **inputs** to the PCD — they come from the platform INTO the SOC. Bypassing them would disconnect the platform input. Do NOT apply the same txdata→pcd_port bypass pattern.

**Status (ww18 2026)**:
- EPD_ON bypass **confirmed effective**: Build `pkg_chpr_cfgr_p2e0_816_fast` (c15a, 28-Apr-2026) achieved **952 kHz** driverClk (pre-PnR zTime.log estimate) — up from 10 kHz regression (same workspace, previous build). Also exceeds the "lucky placement" baseline of 612 kHz.
- **FASTCLOCK_GENERIC_29 still detected** in zTopBuild.log (48.4M + 560K sequential fanout on `xxgpp_v_9.io1p8weak_ll_ls_inst.probe_xio_pad_1p8_780734406.unnamed_28`) — but it is **no longer on the critical timing path**.
- **New critical path**: ROB data memory in cdie core (`sfc_bcslice0.par_bsl.corel_wrap.corel.icore0.par_ooo_vec.rob.roalc.roald.RobDataMnnnL_inst_Inst`) — 1046 ns (378 ns constant + 669 ns multiplexed). This is a standard design-limited path unrelated to FASTCLOCK.
- **Conclusion**: The ProbesLib `assign()` bypass of `txdata→pcd_epd_on` effectively eliminates the FASTCLOCK DPO's impact on driverClk, even though the DPO is still detected. The bypass appears to disconnect the inout pad from the routing fabric so the DPO fan-out no longer propagates through timing paths.
- slp_s3_b/s4_b/s5_b/thermtrip_b bypasses staged in `sle_workarounds.py` for next rebuild (expected to eliminate the remaining FASTCLOCK_GENERIC_29 entry entirely since `xxgpp_v_9` is `slp_s5_b`).
- PnR (IsePar) in progress — final `zTime_fpga.log` post-route driverClk pending.

**Limitations**:
- For PCD→Platform (output) signals: use `txdata→pcd_port` direction.
- For Platform→PCD (input) signals: use `pcd_port→rxdata` direction (see RX bypass pattern below).
- Must identify the exact hierarchical path to the buffer wrapper's `txdata`/`rxdata` port and the PCD-level inout port name.
- Only eliminates FASTCLOCK if the specific pad instance was the one detected as clock. If ALL io1p8weak_ll_ls instances share the same synthesis probe cell, individual bypasses may not eliminate the DPO — `clock_boundary_marker` at the module level remains the proper fix.

**Why bypasses work to eliminate FASTCLOCK**: DVP (Design Visibility Probe) cells are generated during **VCS compilation** (analysis/elaboration/synthesis). When an `assign()` bypass with `-disconnect` is applied to a signal, VCS eliminates the analog pad from the signal path during synthesis. Without the analog pad in the signal path, ZeBu's auto-detection never sees the signal as a FASTCLOCK candidate, no DVP probe is generated, and no DPO is created. This is why **the fix requires a full rebuild** — in the current build, the DVP probe is already baked into the EDIF netlist.

#### Option D-RX: ProbesLib assign() bypass for INPUT signals (ww18 2026)

**Concept**: For Platform→PCD input signals (e.g., `pwrbtn_b`, `batlow_b`), the bypass direction is reversed: connect the PCD-level inout port to the buffer wrapper's `rxdata` input. This preserves the signal path (platform drives PCD receiver) while eliminating the analog pad's DVP probe from the FASTCLOCK detection path at VCS compile time.

**TX vs RX bypass direction**:
| Signal Direction | Bypass Pattern | Example |
|---|---|---|
| PCD→Platform (output) | `src=txdata, dst=pcd_port` | slp_s3_b, thermtrip_b |
| Platform→PCD (input) | `src=pcd_port, dst=rxdata` | pwrbtn_b, batlow_b |

**Implementation** (in `sle_workarounds.py`):
```python
# RX-direction bypass for Platform→PCD input signals (GPIO V family)
# src: PCD module inout port (driven by platform)
# dst: rxdata inside gppvfamily1 buffer wrapper (digital RX input)
assign(src=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_3_pwrbtn_b",
       dst=f"tb_top.pkg.pcdpkg.pcd.pargpcom35.pargpcom35_pwell_wrapper.c76pxecfiottlpcdhgppvfamily1.xxgpp_v_3.rxdata")
```

**Hierarchy for RX bypass**:
```
tb_top.pkg.pcdpkg.pcd.xxgpp_v_3_pwrbtn_b          ← PCD inout port (bypass SRC — driven by platform)
tb_top.pkg.pcdpkg.pcd
  .pargpcom35.pargpcom35_pwell_wrapper
    .c76pxecfiottlpcdhgppvfamily1
      .xxgpp_v_3                                    ← buffer wrapper instance
        .rxdata                                     ← digital RX signal (bypass DST — feeds PCD PMC)
        .io1p8weak_ll_ls_inst                       ← inner analog pad module (BYPASSED)
          .xio_pad_1p8                              ← inout pad (FASTCLOCK detected here)
```

**Architectural safety for RX bypass**: The bypass connects the PCD-level inout port directly to the digital `rxdata` wire inside the buffer wrapper, cutting out the analog `io1p8weak_ll_ls` pad logic. Since the pad's RX path is simply `xio_pad_1p8 → rxdata` (no analog gain stages in the model), this bypass preserves functional equivalence while eliminating the DVP probe opportunity.

#### Worked Example: pkg_chpr_p2e4_816_fast (ttlhm_n2p DUT, ww18 2026)

**Build path**: `$WORKAREA/output/ttlhm_n2p/emu/zebu_zebu/pkg_chpr_p2e4_816_fast/zse5/`
*(Historical reference: `/nfs/site/disks/issp_ttl_emu_compile_005/pkg-ttlpkg-a0-cdie_ww13e_hub_ww13h_pcd_ww15a_github/`)*

**Symptom**: driverClk at ~27 kHz. All 100 timing paths from single source `U0_M0_F9.zext_p_11038`, 36,677 ns delay, 285 FPGA hops.

**FASTCLOCK identified**: `FASTCLOCK_GENERIC_47_tb_top.pkg.probe_bdiepkg_pcdpkg_xxgpp_v_3_pwrbtn_b_768069167.unnamed_46` — 47.7M sequentials.

**Existing bypasses in `sle_workarounds.py`**: xxgpp_v_4 (slp_s3_b), xxgpp_v_5 (slp_s4_b), xxgpp_v_9 (slp_s5_b), xxgpp_v_15 (thermtrip_b) — all using TX-direction pattern (`src=txdata, dst=port`). These are OUTPUT signals.

**Missing**: xxgpp_v_3 (pwrbtn_b) — this is an INPUT signal, was not bypassed, and is the sole FASTCLOCK cause.

**Root cause**: `pwrbtn_b` is a unidirectional **input** signal (Platform → PCD PMC). It was missed from the bypass list because: (1) it's an input direction unlike the others, and (2) it happens to be on the same GPIO V family pad. The existing output-direction bypasses prevented DVP probe generation for those other signals during VCS compilation. Only xxgpp_v_3 still had its analog pad in the routing path, so VCS generated a DVP probe → ZeBu detected it as FASTCLOCK.

**Why `zforce -type global` failed**: Applied to `xxgpp_v_3_pwrbtn_b` — confirmed does NOT suppress FASTCLOCK auto-detection (as expected from previous findings). The DPO remains.

**Fix**: Add RX-direction bypass line to `sle_workarounds.py`:
```python
assign(src=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_3_pwrbtn_b",
       dst=f"tb_top.pkg.pcdpkg.pcd.pargpcom35.pargpcom35_pwell_wrapper.c76pxecfiottlpcdhgppvfamily1.xxgpp_v_3.rxdata")
```

**Expected result**: 27 kHz → ~632 kHz (next worst critical path is ts_clkbus at 1,582 ns / 15 hops).

**Lesson**: When auditing GPIO V pad bypasses, include ALL signal directions — input signals need RX-direction bypass, not TX. The complete list of GPIO V signals that may need bypasses:

| Wrapper | Signal | Direction | Bypass Type | In Coworker Build |
|---|---|---|---|---|
| xxgpp_v_3 | pwrbtn_b | INPUT (Platform→PCD) | RX (port→rxdata) | **MISSING** ← root cause |
| xxgpp_v_4 | slp_s3_b | OUTPUT (PCD→Platform) | TX (txdata→port) | Present |
| xxgpp_v_5 | slp_s4_b | OUTPUT (PCD→Platform) | TX (txdata→port) | Present |
| xxgpp_v_9 | slp_s5_b | OUTPUT (PCD→Platform) | TX (txdata→port) | Present |
| xxgpp_v_15 | thermtrip_b | OUTPUT (PCD→Platform) | TX (txdata→port) | Present |
| xxgpp_v_0 | batlow_b | INPUT (Platform→PCD) | RX (port→rxdata) | Not present (latent risk) |
| xxgpp_v_1 | ac_present | INPUT (Platform→PCD) | RX (port→rxdata) | Not present (latent risk) |
| xxgpp_v_2 | wake_b | INPUT (Platform→PCD) | RX (port→rxdata) | Not present (latent risk) |

**Complete GPIO V bypass list for new builds** (include ALL to prevent non-deterministic regression):
```python
# OUTPUT signals (TX direction: txdata → pcd_port)
assign(src=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_4.txdata",  dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_4_slp_s3_b")
assign(src=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_5.txdata",  dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_5_slp_s4_b")
assign(src=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_9.txdata",  dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_9_slp_s5_b")
assign(src=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_15.txdata", dst=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_15_thermtrip_b")

# INPUT signals (RX direction: pcd_port → rxdata)
assign(src=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_3_pwrbtn_b",  dst=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_3.rxdata")
assign(src=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_0_batlow_b",  dst=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_0.rxdata")
assign(src=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_1_ac_present", dst=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_1.rxdata")
assign(src=f"tb_top.pkg.pcdpkg.pcd.xxgpp_v_2_wake_b",    dst=f"...c76pxecfiottlpcdhgppvfamily1.xxgpp_v_2.rxdata")
```

**IMPORTANT**: DVP probe name differs across DUT variants:
- `ttlbx_n2p` DUT: `probe_xio_pad_1p8_NNNNNN.unnamed_NN` (probe at pad level)
- `ttlhm_n2p` DUT: `probe_bdiepkg_pcdpkg_xxgpp_v_N_SIGNAL_NNNNNN.unnamed_NN` (probe at pkg level)

The probe name in `zTopBuild_SDC_clock_report.log` varies by DUT configuration, but the root cause and fix are the same — bypass the analog pad at VCS compile time to prevent DVP probe generation.
