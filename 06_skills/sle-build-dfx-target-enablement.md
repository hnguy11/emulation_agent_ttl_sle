---
name: sle-build-dfx-target-enablement
description: 'Enable a DFX emulation build target for PKG CHPr models. USE WHEN: creating a new DFX build target from existing CHPr model, enabling HVM/JTAG/STF DFX transactors on PKG, porting DFX target to new stepping, need security policy unlocked for TAP access, DFX fuse overrides (dfx_agg, MEMSS PMA), hub_emu_dfx_xtors.sv HUB_PCD_CONNECTED guard, DFX nobios/minibios/pegoste test lists, run_simregress.dfx script, DFX compute.cth. Covers: grdlbuild task, model.cfg.mako, change.cfg, rtlchange for DFX xtors, fuse overrides, test lists, run scripts, compute config, pmsync_down_tracker robustness fix.'
argument-hint: 'Describe the DFX target you want to create or the error you are seeing'
---

# SLE Build: DFX Target Enablement

## Purpose
Enable a new DFX (Design-For-Test/Debug) emulation build target for PKG CHPr models on ZeBu (ZSE5). This skill covers all build-time and runtime changes needed to create a DFX target variant from an existing non-DFX CHPr model and get it successfully out of reset with a nobios test.

## When To Use
- Creating a new DFX build target for an existing PKG CHPr emulation model
- Enabling HVM/JTAG/STF DFX transactors on a PKG model
- Porting DFX target from one model/stepping to another
- Debugging DFX target build or runtime failures
- Need a model with DFX security policy unlocked for TAP access

## Reference Implementation
- **Model**: `pkg-ttlpkg-a0-ttlbxpkg-c09e_h11a_p13a.1_DFX`
- **Commit**: `66b2d8378` (tag: `DFXnonbios`) — "Set of changes for DFX target with non bios test passing"
- **Parent commit**: `c182482b4` (baseline non-DFX model)
- **Test**: `reset_fetch_CXM_DISABLE_HUB_SVA_mobile_nobios_non_BKC_reduced_p2e4e4` — Model Run PASS (27 min)
- **Post-processing**: FAIL in griffin checkers (unrelated to DFX, known issue)

---

## Overview of Changes (21 files, ~1400 lines)

The DFX target is created by cloning an existing CHPr model configuration (e.g., `pkg_chpr_p2e4_816_fast`) and adding:
1. Build infrastructure (grdlbuild task, model.cfg.mako, change.cfg, compute.cth)
2. DFX-specific RTL changes (hub_emu_dfx_xtors.sv with HVM/TAP/STF transactors)
3. DFX fuse overrides (security policy unlock, MEMSS PMA enable, etc.)
4. Runtime test lists and run scripts

---

## Step-by-Step Procedure

### STEP 1: Add grdlbuild Build Task

**File**: `flows/grdlbuild/.recipe/emu/sle/build.gradle.kts`

Add a new `BuildTask` for the DFX ZSE target. Clone from an existing CHPr task and change the MODEL name to include `_dfx`:

```kotlin
task<BuildTask>("pkg_chpr_p2e4_${cdie_cfg}_dfx_zse") {
    commandLine("make cleanall flowgen -C \$WORKAREA/verif/emu && flock \$WORKAREA/output/${dut}/emu/.emu_zebu.gen_dv_flist.lock make gendvflist -C \$WORKAREA/verif/emu && make runelab -C \$WORKAREA/verif/emu")
    environment("MODEL","pkg_chpr_p2e4_${cdie_cfg}_dfx")
    environment("TECH","zse5")
    environment("DUT","${dut}")
    environment("PROCESS","$process")
    environment("EMU_ZEBU_BE","1")
    environment("EMU_COMPRESS","0")
    environment("EMU_SIZE_REDUCE","0")

    dependsOn(":${dut}:emu:common:pkg_tls_compile_ready")
    dut("${dut}")
    runModes("zebu_release")
}
```

**Key**: The MODEL name `pkg_chpr_p2e4_${cdie_cfg}_dfx` must match the model name used in `.model.cfg.mako` and `change.cfg`.

### STEP 2: Add Model Definition in .model.cfg.mako

**File**: `verif/emu/.model.cfg.mako`

Add a new model block. Clone from the existing CHPr fast model and change:
- Model name to `pkg_chpr_p2e4_816_dfx`
- `change_cfg_conf` to `pkg_chpr_dfx_model_cfg` (defined in Step 3)

```yaml
    pkg_chpr_p2e4_816_dfx:
        top_module_names:
             - pkg_chpr_tls_tb_lib.tb_top_config
        analysis_opts : global_emu_pkg_chpr_vlog_opts.f
        elab_opts: global_emu_pkg_chpr_fast_elab_opts.f
        elab_liblist_autogen: 1
        elab_opts_string: -LDFLAGS -L$(SIMICS_HOME)/linux64/bin/py3 -LDFLAGS -L$SIMICS_HOME/linux64/bin
        change_cfg_conf: pkg_chpr_dfx_model_cfg
        allow_missing_val_vip_dep_list: 1
        test_modes:
             - tim
        vip_include_ips:
             - '*common_shared_vips'
             - '*common_pcd_vips'
        val_include_ips:
             - pkg:chpr_tls_tb_lib
             - pkg:cdie0_rtl_configs_lib
             - pkg:cdie0_reg_mon_lib
             - pkg:hub_rtl_configs_lib
        model_analysis_opts:
            - pkg:cdie0_rtl_configs_lib:../../../soc/$DUT/cdie0/src/codegen/${CDIE0_DUT}/emu/emuvcs_emuvcs/${CDIE0_DUT}_p2e4/vcs/gen_stage/IP_SS_ENABLES.opts.f
            - pkg:hub_rtl_configs_lib:../../../soc/$DUT/${HUB_DUT}/src/codegen/${HUB_DUT}/emu/emuvcs_emuvcs/hub/vcs/gen_stage/IP_SS_ENABLES.opts.f
        soc_include_json:
            - ${CDIE0_DUT}:${CDIE0_DUT}_p8e16_fast
            - ${HUB_DUT}:hub
            - pcd:pcd_zse5_upf
```

**Key differences from non-DFX**: The `change_cfg_conf` points to `pkg_chpr_dfx_model_cfg` instead of `pkg_chpr_fast_model_cfg`. This controls which RTL change sets are applied.

### STEP 3: Add Change Config for DFX Model

**File**: `verif/emu/change.cfg`

Add a new change config that inherits from the standard PKG CH configs:

```yaml
pkg_chpr_dfx_model_cfg:
    inherits:
        - pkg_ch_fast_model_cfg
        - sle_common_setup      ## SLE_CHANGES.cfg
        - pcd_common_setup      ## SLE_CHANGES.cfg
        - sle_pkg_ch_changes    ## SLE_CH_CHANGES.cfg
        - pkg_${TECH}_override  ## SLE_CHANGES.cfg
```

**Note**: This is identical to `pkg_chpr_fast_model_cfg`. The separate config allows DFX-specific rtlchange sets to be added later without affecting the functional model.

### STEP 4: Add DFX Transactors RTL Change

**File (new)**: `src/val/emu/rtlchanges/hubbx/src/val/emu/testbench/rtl/hub_emu_dfx_xtors.sv`
**File (new)**: `src/val/emu/rtlchanges/hubbx/src/val/emu/testbench/rtl/hub_emu_dfx_xtors.sv.ref`

This is a ~308-line SystemVerilog file that instantiates DFX transactors (HVM, JTAG TAP, STF) for the HUB die. It contains three conditional sections:

1. **`HUB_DUT_CONFIG_XTOR_VTPSIM_EN`**: HVM transactor with pin connections (TAP, HPTP, viewdig/viewana). **Critical SLE change**: signals like `yy_hub_dfx_policy_in_dam_p2h`, `yy_hub_dfx_pri_powergood_p2h`, `yy_pcd_pm_vnnaon_reset_b`, and `yy_pcd_dfx_a0_debug_en_core_p2h` are guarded with:
   ```verilog
   `ifndef HUB_DUT_CONFIG_HUB_PCD_CONNECTED
       `HUB_HVM_XTOR_CONNECT(`D2D_IIOSF_TI.yy_pcd_dfx_policy_in_dam_p2h, 37)
       ...
   `endif // HUB_DUT_CONFIG_HUB_PCD_CONNECTED
   ```
   This guard is needed because in PKG models where PCD RTL is present, these signals are driven by PCD directly, not the D2D BFM.

2. **`HUB_DUT_CONFIG_XTOR_TAP_EN`**: JTAG TAP transactor with primary/AUX interface mux and PSCAND GPIO xactor.

3. **`HUB_DUT_CONFIG_XTOR_STF_EN`**: STF (Scan Test Framework) GPIO xactor.

**The `.ref` file is a copy of the original source** (from the HUB IP simulation collateral). The replacement file adds `HUB_DUT_CONFIG_HUB_PCD_CONNECTED` guards around signals that are driven differently in PKG scope.

#### Register the rtlchange

**File**: `src/val/emu/rtlchanges/hubbx/HSDs.toml` — Add entry:
```toml
["src/val/emu/testbench/rtl/hub_emu_dfx_xtors.sv"]
hsd = 0
description = "Add HUB defines to gaurd non-hvm signals to connect to IOSF D2D bfm IF only when PCD RTL is not present"
```

**File**: `verif/emu/rtl_cfg/PKG_IP_CHANGES.cfg` — Add to `pkg_ip_changes` replace list:
```yaml
- ${PKG_MODEL_ROOT}/src/val/emu/rtlchanges/${HUB_DUT}/src/val/emu/testbench/rtl/hub_emu_dfx_xtors.sv
```

### STEP 5: Add DFX Fuse Overrides to Common Defaults

**File**: `reglist/common/emu/common_defaults.list`

Add these fuse overrides that are required for DFX operation:

```
# BIOS config for PKG model identification
+defaults -bios_cfg project.RUNNING_ON_PKG_MODEL=true -bios_cfg-

# Valid HBOS configuration
+defaults -si_cfg VALID_HBOS=0xf -si_cfg-

# Bypass fuse sense
+defaults EAR1_BYPASS_FUSE_SENSE=1

# WA to power up lpatom vccramgt - https://hsdes.intel.com/appstore/article/#/22019566117
+defaults -hub_fuse_ovrd lpatom_fuse/FB_PMA_L2_VOLTAGE_THRESHOLD_FUSE=0x0 -hub_fuse_ovrd-

# CSAF PLL ratio alignment
+defaults -hub_fuse_ovrd csaf_pma_fuse/PLL_RATIO=0xa punit/punit_fw_fuses_CSAF_BOOT_RATIO=0xa punit/punit_fw_fuses_CSAF_MIN_RATIO=0xa punit_fw_fuses_CSAF_VF_RATIO_0=0xa punit_fw_fuses_CSAF_VF_RATIO_4=0xa -hub_fuse_ovrd-

# Align SNCU and atom iceland clocks
+defaults -hub_fuse_ovrd punit/punit_fw_fuses_IOSAF_BOOT_RATIO=0x8 punit/punit_fw_fuses_IOSAF_MIN_RATIO=0x8 punit_fw_fuses_IOSAF_VF_RATIO_0=0x8 punit_fw_fuses_IOSAF_VF_RATIO_4=0x8 -hub_fuse_ovrd-

# Security Policy UNLOCKED(0x2e) to enable Patch23 — CRITICAL FOR DFX
+defaults -hub_fuse_ovrd dfx_agg/default_personality_fuse_enable=10 dfx_agg/default_personality_fuse_value=0 -hub_fuse_ovrd-

# Enable MEMSS PMAs (disabled by default, HSD 22021883446)
+defaults -hub_fuse_ovrd memss_pma_fuse0/MEMSS_PMA_DIS_MEMSS_DIS=0x0 memss_pma_fuse1/MEMSS_PMA_DIS_MEMSS_DIS=0x0 -hub_fuse_ovrd-
```

**Critical for DFX**: The `dfx_agg/default_personality_fuse_enable=10` and `dfx_agg/default_personality_fuse_value=0` fuses unlock the security policy, enabling TAP access.

### STEP 6: Move pmsync_down_tracker to Common PKG CHPr

**File**: `reglist/common/emu/common_pefw.list` — Remove:
```
+options -ms -simics_post_setup_script $WORKAREA/src/val/emu/testbench/sle_workarounds/pmsync_down_tracker.simics -ms-
```

**File**: `reglist/common/emu/common_pkg_chpr.list` — Add:
```
+defaults -ms -simics_post_setup_script $WORKAREA/src/val/emu/testbench/sle_workarounds/pmsync_down_tracker.simics -ms-
```

**Rationale**: The pmsync/pmdown tracker is needed for all CHPr tests (not just PEFW), so it belongs in common_pkg_chpr.

### STEP 7: Fix pmsync_down_tracker.simics for Robustness

**File**: `src/val/emu/testbench/sle_workarounds/pmsync_down_tracker.simics`

Wrap the SIM_create_object in try/except to prevent crashes if the monitor already exists:

```python
echo "Instantiating simics hub pmsync pmdown monitor"
@try:
    pmsync_down_monitor = SIM_create_object("sblink_monitor_xtor","emu.devices.pmsync_down_monitor",
                                              [["scope","tb_top.pkg_emu_tb.sblink_monitor.sblink_monitor_hub"]])
    pmsync_down_monitor.log_level = 2
except Exception as e:
    print("pmsync_down_monitor already exists or failed: %s" % str(e))
```

**Key change**: Removed `["tracker_enable",True]` parameter (not supported in all versions) and added exception handling.

### STEP 8: Create Test List Files

Create these reglist files under `reglist/<DUT>/emu/`:

#### a) Level0 Wrapper (triggers _zse5 suffix)
**File**: `reglist/ttlbx_n2p/emu/level0_pkg_chpr_p2e4_816_dfx_zse5.list`
```
.include $WORKAREA/reglist/common/emu/level0_pkg_chpr_common.list
```

#### b) Nobios Test
**File**: `reglist/ttlbx_n2p/emu/pkg_chpr_p2e4_816_dfx_nobios.list`
```
-defaults -ms -tracker_disable ALL -ms- DISABLE_TRACKER_GEN=1

.options -seed 11526105 -ms -c 1700us -ms-

+options -ms -tracker_enable IOSF_SB,CDIE_DMU_BOOT_FSM,CDIE_PWR,CDIE_DCODE,CDIE_MCA,HUB_PUNIT_BOOT_FSM,HUB_PWR,HUB_MCA,HUB_IOSF_P -ms- GEN_TRACKERS=1

+options -nobios -dirtag nobios

+options -cdie0_fuse_ovrd dmu_fuse/fw_fuses_IA_PHYSICAL_CORE_DISABLE_MASK=0xffff0c -cdie0_fuse_ovrd-

+options -ms -spi_xtor_load $WORKAREA/src/val/emu/tests/reset_fetch/reset_fetch.64mb.mem -ms-

$WORKAREA/src/val/emu/tests/reset_fetch/reset_fetch.asm -b wmtbuild -dirtag reduced_p2e4e4
```

#### c) MiniBIOS Test
**File**: `reglist/ttlbx_n2p/emu/pkg_chpr_p2e4_816_dfx_minibios.list`
```
-defaults -ms -tracker_disable ALL -ms- DISABLE_TRACKER_GEN=1

.options -seed 11526105 -ms -c 20ms -ms-

+options -ms -tracker_enable IOSF_SB,CDIE_DMU_BOOT_FSM,CDIE_PWR,CDIE_DCODE,CDIE_MCA,HUB_PUNIT_BOOT_FSM,HUB_PWR,HUB_MCA,HUB_IOSF_P -ms- GEN_TRACKERS=1
.include $WORKAREA/reglist/common/emu/common_pefw.list

+options -cdie0_fuse_ovrd dmu_fuse/fw_fuses_IA_PHYSICAL_CORE_DISABLE_MASK=0xffff0c -cdie0_fuse_ovrd-

+options -ms -spi_xtor_load ./MiniBios.64mb.mem -ms-

$WORKAREA/src/val/emu/tests/hlt_after_pefw/nop_hlt.asm -b wmtbuild -dirtag reduced_p2e4e4
```

#### d) PeGoSte Test
**File**: `reglist/ttlbx_n2p/emu/pkg_chpr_p2e4_816_dfx_pegoste.list`
```
-defaults -ms -tracker_disable ALL -ms- DISABLE_TRACKER_GEN=1

.options -seed 11526105 -ms -c 30ms -ms-

+options -ms -tracker_enable IOSF_SB,CDIE_DMU_BOOT_FSM,CDIE_PWR,CDIE_DCODE,CDIE_MCA,HUB_PUNIT_BOOT_FSM,HUB_PWR,HUB_MCA,HUB_IOSF_P -ms- GEN_TRACKERS=1
.include $WORKAREA/reglist/common/emu/common_pefw.list
.include $WORKAREA/reglist/common/emu/common_pegoste.list

+options -cdie0_fuse_ovrd dmu_fuse/fw_fuses_IA_PHYSICAL_CORE_DISABLE_MASK=0xffff0c -cdie0_fuse_ovrd-

+options -ms -spi_xtor_load ./MiniBios.64mb.mem -ms-

$WORKAREA/src/val/emu/tests/hlt_after_pefw/nop_hlt.asm -b wmtbuild -dirtag reduced_p2e4e4
```

#### e) Specific Tests Selector
**File**: `reglist/ttlbx_n2p/emu/pkg_chpr_p2e4_816_dfx_specific_tests_zse5.list`

Uses Python env-var gating to select tests:
```python
<python>
import os

if (os.environ.get("SLE_RESET_FETCH_NOBIOS_TEST", "") == "1") or (os.environ.get("SLE_L0_ALL", "") == "1"):
    print("# Include reset_fetch_nobios test")
    print(".include $WORKAREA/reglist/${DUT}/emu/${EMU_MODEL}_nobios.list")

if (os.environ.get("SLE_MINIBIOS_PEFW_TEST", "") == "1") or (os.environ.get("SLE_L0_ALL", "") == "1"):
    print("# Include Reset test")
    print(".include $WORKAREA/reglist/${DUT}/emu/${EMU_MODEL}_minibios.list")

if (os.environ.get("SLE_PEGOSTE_TEST", "") == "1") or (os.environ.get("SLE_L0_ALL", "") == "1"):
    print("# Include Reset test")
    print(".include $WORKAREA/reglist/${DUT}/emu/${EMU_MODEL}_pegoste.list")
</python>
```

### STEP 9: Create DFX Run Script

**File (new)**: `src/val/emu/scripts/sle_run_scripts/run_simregress.dfx.nobios.csh`

```csh
simregress \
-setenv DDG_FAMILY=ttlpkg \
-setenv PROCESS=n2p \
-setenv DUT=ttlbx_n2p \
-setenv EMU_MODEL=pkg_chpr_p2e4_816_dfx \
-setenv EMU_TECH=zse5 \
-setenv SLE_BKC_FLOW=0 \
-setenv EMU_SOC_MODEL=1 \
-setenv SLE_RESET_FETCH_NOBIOS_TEST=1 \
-dut ttlbx_n2p \
-save \
-no_xs \
-local \
-trex \
EMUL_QSLOT=/prj/sv/ttl/emu/standard \
-emu_model pkg_chpr_p2e4_816_dfx \
-emu_tech zse5 \
-ms \
-c 20ms \
-site_restrict 'fm' \
-tracker_enable ALL \
-pcd.smip_ovrd $WORKAREA/src/val/emu/testbench/fuse_overrides/pcd_clink_dis_smip_override.pl \
-pcd.ss_ovrd $WORKAREA/src/val/emu/testbench/fuse_overrides/pcd_clink_dis_softstrap_override.pl \
-pcd.fuse_ovrd $WORKAREA/src/val/emu/testbench/fuse_overrides/pcd_pmc_clink_dis_fuse_override.txt \
-simics_post_setup_script $WORKAREA/src/val/emu/testbench/sle_workarounds/run_busy_bit_force.simics \
-ms- \
-trex- \
-trex -no_compress -trex- \
-trex -hub_fuse_ovrd ioc_fuse/PCD_SELECT=0x1 -hub_fuse_ovrd- -trex- \
-l $WORKAREA/reglist/ttlbx_n2p/emu/level0_pkg_chpr_p2e4_816_dfx_zse5.list \
-notify
```

**Key runtime settings**:
- `EMU_MODEL=pkg_chpr_p2e4_816_dfx` — must match model name in .model.cfg.mako
- `SLE_RESET_FETCH_NOBIOS_TEST=1` — selects the nobios test from the specific_tests list
- `ioc_fuse/PCD_SELECT=0x1` — enables PCD in the fuse configuration
- `run_busy_bit_force.simics` — workaround for run_busy bit polling hang
- PCD fuse/smip/softstrap overrides for clink disable

### STEP 10: ZeBu UTF Build Config Changes

**File**: `src/val/emu/build_cfg/dut.utf`

Two changes for DFX target optimization:

1. **Remove clock_localization command** (per SNPS recommendation):
```tcl
## Remove these UTF commands that override Blue Lane settings
## ztopbuild -advanced_command {clock_localization -core_strategy=AUTO -fpga_strategy=AUTO -core_max_io_cut=40000 -core_overflow_io_cut=20000}
```

2. **Add `-format=all -generate_zvdb` to loop break command**:
```tcl
ztopbuild -advanced_command {loop break -format=all -generate_zvdb -safe_break_pp -explore_latches -max_lut_overflow=5 -max_reg_overflow=5 -rtl=yes -consider_oscillatory_sccs=safe_break -override_unknown_behavior_scc=yes -localize_copies_to_data_loads}
```

3. **Reorder FRB and latch protection commands** — move `set_fast_waveform_capture` after `zcorebuild_command` latch analysis commands.

### STEP 11: Create Compute Config (.cth)

**File (new)**: `verif/emu/zebu/compute/<DUT>.pkg_chpr_p2e4_816_dfx.compute.cth`

Clone from an existing compute.cth (e.g., `pkg_chpr_p2e4_816_fast.compute.cth`). This defines NB compute resources for all ZeBu build phases (analysis, synthesis, coreBuild, topBuild, zPar, etc.).

Key resource allocations:
- `ZebuVcs`: 800GB RAM, 16 CPU
- `ZebuTopBuild`: 600GB RAM, 16 CPU
- `ZebuRtl2Equi`: 400GB RAM, 4 CPU
- `ZebuSimzilla`: 320GB RAM, 4 CPU

### STEP 12: Add hlt_after_pefw Test Environment

**File (new)**: `src/val/emu/tests/hlt_after_pefw/.wmtbuild.env`

This is the wmtbuild environment file for the `nop_hlt.asm` test used with minibios/pegoste DFX tests. It provides the build configuration needed by wmtbuild to compile the test.

---

## Naming Convention

DFX model names follow the pattern:
```
pkg_chpr_p<pcore>e<ecore>_<cdie_cfg>_dfx
```
Example: `pkg_chpr_p2e4_816_dfx`

The `_dfx` suffix distinguishes it from the functional `_fast` variant.

---

## Common Pitfalls

1. **Missing `HUB_DUT_CONFIG_HUB_PCD_CONNECTED` guards**: In PKG scope, signals like `yy_hub_dfx_policy_in_dam_p2h` are driven by PCD RTL. The DFX xtor file must guard these with `ifndef HUB_DUT_CONFIG_HUB_PCD_CONNECTED` to avoid multiple drivers.

2. **Security policy fuse not set**: Without `dfx_agg/default_personality_fuse_enable=10` and `dfx_agg/default_personality_fuse_value=0`, TAP access will be blocked and DFX tests will hang.

3. **pmsync_down_tracker crash**: The simics monitor creation can fail if called multiple times. Always use try/except pattern.

4. **tracker_enable parameter in SIM_create_object**: Some versions of sblink_monitor_xtor don't support `["tracker_enable",True]`. Remove it and rely on default behavior.

5. **Forgot to add rtlchange to PKG_IP_CHANGES.cfg**: The new `hub_emu_dfx_xtors.sv` must be listed in the replace section of `PKG_IP_CHANGES.cfg` or it won't be compiled.

6. **Model name mismatch**: The model name must be consistent across `build.gradle.kts`, `.model.cfg.mako`, `change.cfg`, reglist files, run scripts, and compute.cth.

7. **Missing compute.cth**: Without a `<DUT>.<MODEL>.compute.cth` file, the ZeBu build will fail to dispatch NB jobs.

---

## Verification Checklist

- [ ] grdlbuild task added with correct MODEL env var
- [ ] .model.cfg.mako has new model block with correct change_cfg_conf
- [ ] change.cfg has new config inheriting from correct bases
- [ ] hub_emu_dfx_xtors.sv + .ref created with HUB_PCD_CONNECTED guards
- [ ] HSDs.toml entry added for new rtlchange
- [ ] PKG_IP_CHANGES.cfg updated with new rtlchange path
- [ ] DFX fuse overrides added to common_defaults.list (especially dfx_agg)
- [ ] pmsync_down_tracker moved to common_pkg_chpr.list
- [ ] pmsync_down_tracker.simics uses try/except
- [ ] Test list files created (nobios, minibios, pegoste, level0, specific_tests)
- [ ] Run script created with correct -emu_model and PCD overrides
- [ ] compute.cth created for new model
- [ ] Build completes successfully (VCS analysis + elab + ZeBu backend)
- [ ] Nobios test runs and model run stage PASSES
