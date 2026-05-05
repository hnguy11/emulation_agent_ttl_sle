---
name: sle-build-fpga-elab-missing-cell-fix
description: "Fix VCS elaboration Error-[CFCILFBI] 'Cannot find cell in liblist' failures in FPGA VCS builds. USE WHEN: FPGA VCS elab fails with CFCILFBI error, bind instance references a module not compiled into any library, testbench transactor/monitor module missing from FPGA build, need to guard bind with FPGA_EMU_BUILD define. Covers: CFCILFBI diagnosis, FPGA_EMU_BUILD preprocessor define convention, FPGA_CHANGES.cfg define propagation, testbench bind guard patterns."
argument-hint: "Provide the WORKAREA path and the elab error message showing the missing cell name and binding instance path."
---

# Fix VCS Elaboration CFCILFBI Errors in FPGA Builds

## When to Use
- `grdlbuild` FPGA VCS build passes analysis and post_analyze but fails at **elab** phase
- VCS elaboration log shows `Error-[CFCILFBI] Cannot find cell in liblist`
- A `bind` instance in a testbench file references a transactor/monitor module that was never compiled into any FPGA library
- The module exists in ZSE/standard VCS builds but not in the FPGA build (because the IP's library was excluded or the transactor isn't needed)

## Background: Build Phase Ordering (Post-Analysis)

After VCS analysis passes, the build proceeds through:
1. `c_compile` — testbench C++ compile (~1-2 min)
2. `post_analyze` — rtlchanges_postcheck (~1-2 min)
3. `gen_vcs_cmd` — generates VCS elaboration command (~1-2 min)
4. **`elab`** — VCS elaboration (~10-30 min) — **fails here with CFCILFBI**

## Symptom

In the elab log (`$OUTDIR/log/<TIMESTAMP>/elab.log`):
```
Error-[CFCILFBI] Cannot find cell in liblist
  Cell 'sblink_monitor_xtor' is not found for binding instance
  'tb_top.pkg_emu_tb.sblink_monitor.sblink_monitor_hub'.
  Please make sure the cell exists in one of the libraries or add the
  cell library to the liblist.
```

In the grdlbuild task log:
```
Target:    elab                                     FAILED
```

## Diagnosis

### CRITICAL: Collect ALL Elab Errors Before Fixing

Elab takes 10-30+ minutes per iteration. **Do NOT fix one error and relaunch** — collect all `Error-[CFCILFBI]` instances from the elab log and fix them all in one pass.

```bash
OUTDIR=$WORKAREA/output/ttlbx_n2p/emu/fpgasim_emuvcs/$MODEL/vcs
# Find the elab log (use the latest timestamp directory)
ELAB_LOG=$(ls -td $OUTDIR/log/*/elab.log 2>/dev/null | head -1)

# List ALL CFCILFBI errors — each is a separate missing cell
grep "Error-\[CFCILFBI\]" -A3 "$ELAB_LOG" | grep "Cell '"

# Also check for other elab error types that may co-exist
grep "Error-\[" "$ELAB_LOG" | sort -u | head -20
```

This may reveal multiple missing cells (e.g., `sblink_monitor_xtor`, `some_other_checker`, etc.), each needing a separate guard. Fix them **all** before relaunching.

### Step 1: Identify ALL missing modules
From the elab error:
- **Cell**: The module name that VCS can't find (e.g., `sblink_monitor_xtor`)
- **Binding instance**: The full hierarchical path showing where the `bind` was attempted

### Step 2: Find ALL source files containing the binds
For each missing cell, find the testbench file that instantiates it:
```bash
# Search for all missing cells at once (pipe-separated)
grep -r "sblink_monitor_xtor\|other_missing_cell" $WORKAREA/src/val/emu/testbench/rtl/ | grep -v ".ref"
```
This may reveal that multiple binds are in the same file (fix with one guard) or in different files (fix each).

### Step 3: Check if each module was intentionally excluded
The module source may exist in an IP library that was removed from FPGA builds (e.g., via `fpga_remove_libs` or by not being in the FPGA model's compilation scope). If the transactor/monitor is not needed for FPGA emulation, the correct fix is to guard the instantiation.

## Fix: Guard with `FPGA_EMU_BUILD` Define

### The `FPGA_EMU_BUILD` Preprocessor Convention

`FPGA_EMU_BUILD` is a **generic** preprocessor define that is active only in FPGA builds. It is defined in `FPGA_CHANGES.cfg` via `+define+FPGA_EMU_BUILD` in **both** `.*:` prepend blocks.

**Key principles:**
- Use `FPGA_EMU_BUILD` for **generic** testbench exclusions that aren't tied to a specific IP
- Do NOT use CDIE-specific defines (e.g., `FPGA_JER_TEAM_NVL_CDIE`) for generic exclusions — semantically misleading
- Do NOT use `EMULATION_VCS` — it's also active for non-FPGA VCS builds
- Prefer `ifndef FPGA_EMU_BUILD` (negative guard) so code is **included by default** in all builds except FPGA
- Only active in FPGA builds — ZSE and standard VCS builds don't define it

### Applying the Guard

Edit the testbench file to wrap the bind instantiation:

**Before:**
```systemverilog
module pkg_emu_sblink();

sblink_monitor_xtor sblink_monitor_hub(
    .clk         (tb_top.fast_clk_drv.fast_clk),
    .rst_n       (tb_top.pkg.hubpkg.hub.xx_hub_epd_on),
    .xxCLK24MHzp (tb_top.pkg.hubpkg.hub.yy_hub_pm_xtal_clk),
    .xxPMSYNC    (tb_top.pkg.hubpkg.hub.yy_hub_pm_pmsync),
    .xxPMDown    (tb_top.pkg.hubpkg.hub.yy_hub_pm_pmdown)
);

endmodule
```

**After:**
```systemverilog
module pkg_emu_sblink();

`ifndef FPGA_EMU_BUILD
sblink_monitor_xtor sblink_monitor_hub(
    .clk         (tb_top.fast_clk_drv.fast_clk),
    .rst_n       (tb_top.pkg.hubpkg.hub.xx_hub_epd_on),
    .xxCLK24MHzp (tb_top.pkg.hubpkg.hub.yy_hub_pm_xtal_clk),
    .xxPMSYNC    (tb_top.pkg.hubpkg.hub.yy_hub_pm_pmsync),
    .xxPMDown    (tb_top.pkg.hubpkg.hub.yy_hub_pm_pmdown)
);
`endif

endmodule
```

### Where `FPGA_EMU_BUILD` is Defined

In `$WORKAREA/verif/emu/rtl_cfg/FPGA_CHANGES.cfg`, the define appears in both `.*:` wildcard sections:

**First `.*:` section** (add/prepend block, ~line 39):
```yaml
    prepend:
        vlog_opts:
            ...
            - +define+FPGA_EMU_BUILD
            - +define+FPGA_JER_TEAM_NVL_CDIE
```

**Second `.*:` section** (remove/prepend block, ~line 96):
```yaml
    prepend:
        vlog_opts:
            - -sverilog
            - +define+FPGA_EMU_BUILD
            - +define+EMULATION_LJPLL_USE_EFFM_CLKGEN
```

Both sections must have the define to ensure all libraries see it, regardless of which `.*:` block takes effect for a given library.

## When NOT to Use This Fix

- If the missing module IS needed for FPGA emulation functionality — then the fix is to ensure the module's library is compiled (add it to the FPGA model's library list)
- If the module is already guarded by another define (e.g., `PKG_DUT_CONFIG_SOCS_ENABLE`) that simply isn't working — investigate why the existing guard is ineffective before adding a new one
- If the error is `Error-[URMI]` (undefined module) instead of `Error-[CFCILFBI]` — that's a different issue (library not compiled at all), see the `sle-build-grdlbuild-monitor` skill

## Real Example

**Build 13** (FPGA VCS `pkg_chpr_cfgr_p2e0_816_fast_fpga_slimsim`):
- Analysis: 2065 PASSED / 0 FAILED
- c_compile: PASSED
- gen_vcs_cmd: PASSED
- **elab: FAILED** — `Error-[CFCILFBI] Cannot find cell 'sblink_monitor_xtor'`
- Source: `$WORKAREA/src/val/emu/testbench/rtl/pkg_emu_sblink.sv` line 10
- Had a commented-out `ifdef PKG_DUT_CONFIG_SOCS_ENABLE` guard that was ineffective
- Fix: Added `ifndef FPGA_EMU_BUILD` guard
- Build 14: Relaunched with fix applied

## Risk Assessment

**Low risk** — the fix only excludes non-functional testbench monitors from FPGA builds. These monitors typically depend on signals/IPs that don't exist in the FPGA model's hierarchy anyway, so they would cause simulation issues even if they compiled.
