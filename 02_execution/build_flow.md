---
title: "Build Flow — Compilation & Resume Instructions"
module: 02_execution
tags: [build, compilation, grdlbuild, zebu, resume, stages]
---

# Build Flow — Compilation & Resume Instructions

## Document Structure

> **This document covers both TTL (active) and NVL (legacy) build flows.**
> - **[TTL]** sections apply to the `ttlbxpkg` and `ttlhmpkg` workareas under `/nfs/site/disks/issp_ttl_emu_compile_001/`
> - **[NVL]** sections are legacy reference for `nvlsi7_n2p` / NVL-AX builds — kept for historical context only
>
> **If you are building a TTL model, skip directly to the [TTL ZSE5 Build](#ttl-zse5-build-ttlbxpkg-workarea) section.**

---

## [TTL] TTL ZSE5 Build (ttlbxpkg Workarea)

### Build Command

> ⚠️ **CRITICAL — WORKAREA determines ALL output paths, not `pwd`:**
> `gradle.properties` contains `outputDir=${WORKAREA}/output/grdlbuild`. grdlbuild reads `$WORKAREA` at launch time to determine where to write ALL outputs — logs, nbtasks, ZSE5 zcui.work, etc.
> If `$WORKAREA` is stale (e.g., inherited from a different workarea in VSCode's environment), grdlbuild writes everything to the WRONG workarea even if you `cd` into the correct one first.
> The NB feeder name is derived from `pwd` (so `.1` appears in the name), but all actual paths inside the nbtask use `$WORKAREA`.

```bash
# ALWAYS use explicit path — do NOT use export WORKAREA=$(pwd) (fragile if you're in a subdir)
export WORKAREA=/nfs/site/disks/issp_ttl_emu_compile_001/<workarea>   # e.g. pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1
export LM_PROJECT=DDG-TTLPKG
cd $WORKAREA/flows/grdlbuild
nohup grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb > /tmp/grdlbuild_ttlbx_nb.log 2>&1 &
```

**Verify the build is writing to the correct workarea** (run this 60 seconds after launch):
```bash
# nbtask files should appear under $WORKAREA/output/grdlbuild/nbtasks/
ls $WORKAREA/output/grdlbuild/nbtasks/*.nbtask 2>/dev/null | head -3
# If no nbtask appears here, $WORKAREA was wrong — kill and relaunch after setting WORKAREA correctly
```

Key differences from NVL builds:
- **Target syntax**: `ttlbx_n2p:emu:sle:<target> -nb` — no leading colon (unlike NVL's `:emu_build:zebu:...`)
- **`-nb`** (NB mode) instead of `-Penv=immediate` — submits DVB sub-tasks (jem, vcssimmpp, cpp) to NB queue
- DVB output under: `output/ttlbx_n2p/emu/zebu_zebu/pkg_chpr_p2e4_816_fast/zse5/`
- Gradle task logs under: `output/grdlbuild/logs/ttlbx_n2p.<stage>.log`

### TTL DVB Task Sequence (with `-nb`)
| Task | Log | Notes |
|------|-----|-------|
| `template_gen`, `pkg_repo_prep` | `common.*.log` | First tasks, ~1-5 min each |
| `gen_filelist` | `ttlbx_n2p.filelists_rtl.gen_filelist.log` | Grows to 10-70MB while running |
| `jem` | `ttlbx_n2p.codegen_dv.jem.log` | Submits per-lib sub-jobs to NB; ~20 min |
| `vcssimmpp` | `ttlbx_n2p.sim.vcssimmpp.vcssimmpp_analysis.log` | VCS analysis per lib; ~20 min |
| `cpp` | `ttlbx_n2p.codegen_dv.cpp.log` | C++ compile; ~5-10 min |
| `vcssimmpp_elab` | `ttlbx_n2p.sim.vcssimmpp.vcssimmpp_elab.log` | VCS elaboration |
| `pkg_chpr_p2e4_816_fast_zse` | `ttlbx_n2p.emu.sle.pkg_chpr_p2e4_816_fast_zse.log` | Final ZSE5 compile (hours) |

### Recovering from Stale DVB `.done` File Timestamps

DVB uses empty `.done` marker files to track which libs are already compiled:
- **Old timestamp** (e.g., May 1) = "Skipped" — already done, not resubmitted
- **Today's timestamp** = "Failed" — DVB thinks a previous run tried and failed; will retry

When a previous run fails (e.g., due to `getLf` / LM_PROJECT error), DVB may reset `.done` files to today's timestamp, causing all downstream runs to treat those libs as "Failed" until fixed.

**Diagnosis:**
```bash
# Find .done files with today's timestamps (these are stale/failed)
find $WORKAREA/output/ttlbx_n2p/jem/lib/ -name "*.done" -newer /tmp/some_old_ref_file | head -10
ls -la $WORKAREA/output/ttlbx_n2p/jem/lib/*/.*.done | awk '{print $6,$7,$8,$NF}'

# Check a lib's indicators to confirm it previously PASSED
cat $WORKAREA/output/ttlbx_n2p/jem/lib/<lib_name>/.indicators
# ✅ Expected: {"lib_name":{"STATUS":"PASS"}}
```

**Fix — restore timestamps using a passing reference file:**
```bash
# 1. Find a reference file with a known-good timestamp (from a passing run)
REF=$(find $WORKAREA/output/ttlbx_n2p/jem/lib/ -name "*.done" | xargs ls -lt | grep "May  1" | tail -1 | awk '{print $NF}')

# 2. Reset all stale .done files to the reference timestamp
find $WORKAREA/output/ttlbx_n2p/jem/lib/ -name "*.done" -newer "$REF" -exec touch -r "$REF" {} \;

# Same for vcssimmpp and cpp
find $WORKAREA/output/ttlbx_n2p/vcssimmpp/lib/ -name "*.done" -newer "$REF" -exec touch -r "$REF" {} \;
find $WORKAREA/output/ttlbx_n2p/cpp/lib/ -name "*.done" -newer "$REF" -exec touch -r "$REF" {} \;
```

**Fix — create missing `.done` files (cpp libs with no marker at all):**
```bash
# If a cpp lib compiled successfully (has .so file) but has no .done file:
ls $WORKAREA/output/ttlbx_n2p/cpp/lib/<lib_name>/
# If libuvm_val_cpp.so exists but .uvm_val_cpp.done is missing:
touch -r $WORKAREA/output/ttlbx_n2p/cpp/lib/<lib_name>/analysis.log \
         $WORKAREA/output/ttlbx_n2p/cpp/lib/<lib_name>/.<lib_name>.done
```

**After fixing .done files**: Kill the old feeder (if still running), then relaunch grdlbuild. DVB will see all libs as "Skipped" and proceed directly to the next stage.

### [TTL] Pre-Compilation Environment Setup

```bash
# ALWAYS set explicitly before any grdlbuild invocation — including relaunches
export WORKAREA=/nfs/site/disks/issp_ttl_emu_compile_001/<workarea>   # exact path, including .1/.2 suffix
export LM_PROJECT=DDG-TTLPKG   # CRITICAL — VSCode auto-sets invalid SC_HNGUY11_UNKN fallback

# Verify before launching
echo "WORKAREA   : $WORKAREA"
echo "PWD        : $(pwd)"          # should match WORKAREA/flows/grdlbuild
echo "LM_PROJECT : $LM_PROJECT"    # must be DDG-TTLPKG

# Disk space (need at least 200GB free)
df -h /nfs/site/disks/issp_ttl_emu_compile_001 | tail -1
```

### [TTL] Resume / Restart After Failure

```bash
export WORKAREA=/nfs/site/disks/issp_ttl_emu_compile_001/<workarea>
export LM_PROJECT=DDG-TTLPKG
cd $WORKAREA/flows/grdlbuild
grdlbuild ttlbx_n2p:emu:sle:<MODEL_TARGET> -nb -id
```

**When to use `-id`** (skip completed upstream stages):
- Any upstream task already completed: jem, vcssimmpp, cpp, vcssimmpp_elab, analyze, fe_be, or any combination
- After applying a fix to a failed stage — all prior stages skip automatically
- **ALWAYS include `-nb`** when using `-id` for TTL builds

**NEVER use `-id`**:
- On first build
- After changes to RTL source, `cfg/compute.cth`, `tool.cth`, or filelists that invalidate upstream stages

### [TTL] 6 Pass Checks — Verify Compilation Succeeded

```bash
ZSE5_OUT="$WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5"
# EMU_MODEL examples: pkg_chpr_p2e4_816_fast, pkg_chpr_cfgr_p2e0_816_fast

# 1. Shadow files = 19
[ $(ls $ZSE5_OUT/.shadow/ 2>/dev/null | wc -l) -eq 19 ] && echo "CHECK-1: PASS" || echo "CHECK-1: FAIL ($(ls $ZSE5_OUT/.shadow/ 2>/dev/null | wc -l) found)"

# 2. U0-U3 backend directories exist
ls $ZSE5_OUT/zcui.work/backend_default/ 2>/dev/null | grep -c "^U[0-9]"
# Expected: 4

# 3. MuDb info non-empty
[ -s $ZSE5_OUT/zcui.work/backend_default/MuDb/equis/info ] && echo "CHECK-3: PASS" || echo "CHECK-3: FAIL"

# 4. No missing shared libraries
ldd $ZSE5_OUT/simics_workspace/linux64/lib/zse_engine.so 2>/dev/null | grep -c "not found"
# Expected: 0

# 5. readmem.dump is a regular file
[ -f $ZSE5_OUT/readmem.dump ] && echo "CHECK-5: PASS" || echo "CHECK-5: FAIL"

# 6. No failure_info.log in latest log dir
LATEST=$(ls -t $ZSE5_OUT/log/ 2>/dev/null | head -1)
[ -n "$LATEST" ] && [ ! -f "$ZSE5_OUT/log/$LATEST/failure_info.log" ] && echo "CHECK-6: PASS" || echo "CHECK-6: FAIL"
```

**Quick check:**
```bash
ZSE5_OUT="$WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5"
[ $(ls $ZSE5_OUT/.shadow/ 2>/dev/null | wc -l) -eq 19 ] && echo "COMPILATION PASSED" || echo "COMPILATION INCOMPLETE"
```

### [TTL] Log File Locations

```bash
# Main grdlbuild task log
$WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.<MODEL_TARGET>.log

# ZSE5 zCui orchestrator log (phase transitions)
$ZSE5_OUT/zcui.work/zCui/log/zCui.log

# ZSE5 compilation status (running/waiting/finished tasks)
$ZSE5_OUT/zcui.work/compilation_status.log

# VCS splitter log (largest, ~1-2GB while running)
$ZSE5_OUT/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log

# driverClk timing (appears after zCoreBuildTiming stage)
$ZSE5_OUT/zcui.work/zebu.work/zTime.log
$ZSE5_OUT/zcui.work/backend_default/zTime_fpga.log   # post-FPGA

# Shadow files (presence = stage completed)
$ZSE5_OUT/.shadow/

# NB feeder task files — MUST be under $WORKAREA (wrong path = wrong workarea build)
$WORKAREA/output/grdlbuild/nbtasks/*.nbtask
```

---

## [NVL LEGACY] NVL-AX Build Reference

> ⚠️ **The sections below are NVL-AX legacy reference only.** They document the NVL workarea at `/nfs/site/disks/ive_sle_zsc11_tbaziza/`. Do NOT apply NVL commands or paths to TTL builds.

### [NVL] Pre-Compilation Steps

```bash
# NVL workarea setup
cd /nfs/site/disks/ive_sle_zsc11_tbaziza/models/integrate_bundle1106
export WORKAREA=$(pwd)
export LM_PROJECT=DDG-TTLPKG
echo "WORKAREA: $WORKAREA  LM_PROJECT: $LM_PROJECT"
df -h /nfs/site/disks/ive_sle_zsc11_tbaziza | tail -1
klist 2>&1 | grep -E "Expires|>>>"
```

### [NVL] Full Compilation Command

```bash
# NVL full build (leading colon, -Penv=immediate, no -nb)
cd /nfs/site/disks/ive_sle_zsc11_tbaziza/models/integrate_bundle1106
grdlbuild :emu_build:zebu:<MODEL_TARGET> -Penv=immediate
# Example for ghpf: grdlbuild :emu_build:zebu:pkg_ghpf_model_zse5 -Penv=immediate
```

### [NVL] Resume / Restart

```bash
# NVL resume (leading colon, no -nb)
grdlbuild :emu_build:zebu:<MODEL_TARGET> -id
```

**When to use `-id`** (NVL):
- analyze stage failed but jem/vcssimmpp already passed
- fe_be stage failed but analyze passed (shadow file exists)
- Any Zebu sub-stage failed and upstream tasks are done

**When NOT to use `-id`** (NVL):
- After changing IP versions in `filelists/sip.list`
- After modifying RTL source or `rtlchanges/`
- After changing `tool.cth` or compute settings
- On first build

### [NVL] Supported Models

| Gradle Target | `-emu_model` Flag | Short Name |
|---------------|-------------------|------------|
| `pkg_ghpf_model_zse5` | `pkg_ghpf_model` | ghpf |
| `pkg_chp_model_p2e4_fast_zse5` | `pkg_chp_model_p2e4_fast` | chp_p2e4_fast |
| `pkg_chp_hubs_full_model_p2e4_zse5` | `pkg_chp_hubs_full_model_p2e4` | chp_hubs_full_p2e4 |
| `pkg_chp_model_p2e4_zse5` | `pkg_chp_model_p2e4` | chp_p2e4 |

### [NVL] Build Stages (in order)

| Stage | Tool | Duration | Notes |
|-------|------|----------|-------|
| `prerequisite` | make | seconds | checks env |
| `spark_co` | make | seconds | spark co-sim setup |
| `override_vcs_home` | make | seconds | VCS path override |
| `gen_dv_flist` | make | seconds | generate file lists |
| `c_compile` | gcc | ~1 min | compile C sources |
| `dw_gen` | make | ~1 min | DesignWare gen |
| `gen_analyze_make` | make | ~1 min | analysis Makefile gen |
| `zse_lint` | make | seconds | ZSE lint |
| `pre_analyze` | make | seconds | pre-analysis setup |
| `gen_elab_src` | make | ~2 min | elaboration source gen |
| `analyze` | VCS | ~45 min | 1570 lib VCS analyses |
| `fe_be` | zCui/NB | ~25 hrs | full Zebu FPGA compile |
| `zebu_tb` | make | ~5 min | xtor/co-sim packaging |
| `emu_gen` | make | seconds | final model gen |

### [NVL] fe_be Sub-Stages

| Sub-stage | Duration | Notes |
|-----------|----------|-------|
| `vcs_splitter_VCS_Task_Builder` | ~9 hrs | VCS split into parallel tasks |
| `RTL_DB` | ~30 min | RTL database build |
| `zTopBuild` | ~3.5 hrs | Zebu top-level synthesis |
| `zCoreBuild` (parallel) | ~5 hrs | FPGA core synthesis |
| `zPar` / `PaR_Controller` | ~3.5 hrs | FPGA place & route |
| `zFpgaTiming` (parallel) | ~2.5 hrs | FPGA timing analysis |
| `FpgaResultAnalyzer` | ~2 min | analyze FPGA results |
| `zDB_Global` | ~2.5 hrs | global database assembly |
| `zTime` | ~22 min | timing analysis |
| `zTimeFpga` | ~30 min | FPGA timing |
| `zAuditReport` | ~7 min | audit |

### [NVL] 6 Pass Checks

```bash
# 1. Shadow files (NVL path)
ls output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/.shadow/ | wc -l
# Expected: 19

# 2-6. (Same checks as TTL but with NVL output path)
NVL_OUT="output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5"
ls $NVL_OUT/zcui.work/backend_default/ | grep "^U[0-9]"
wc -c $NVL_OUT/zcui.work/backend_default/MuDb/equis/info
ldd $NVL_OUT/simics_workspace/linux64/lib/zse_engine.so 2>/dev/null | grep "not found"
file $NVL_OUT/readmem.dump
```

### [NVL] Post-Build Steps

```bash
# Run post_zcui (NVL-specific)
grdlbuild :emu_build:zebu:<MODEL_TARGET>_post_zcui
bash scripts/fix_zse5_libs.sh
```

### [NVL] Log File Locations

```
output/grdlbuild/logs/emu_build.zebu.<MODEL_TARGET>.log
output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/log/<TIMESTAMP>/
output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/.shadow/
```

### bundle1106 (GK-integrated, 2026-04-26)
- Build was done by GK integration (`sleadmin`)
- All 19 shadow files present — model compilation is complete
- `output/` is a symlink to GK build at `/nfs/site/disks/ive_nvl_efs_gk_002/GK4/...`
- Required `chmod -R g+w` on `zse5/lib/` and `simics_workspace/linux64/lib/` (BUG-028)
- Then ran `fix_zse5_libs.sh` to create symlinks and patch RPATHs

### bundle1088 (2026-04-10 to 2026-04-12)
- Full recompilation, ~42 hours wall time
- Pre-applied: BUG-020 (CLASS_ANA 92G→250G), BUG-018 (utdb 24.06)
- During build: BUG-019 (shebang fixes), BUG-010 (softstrap_assembler)
- Post-build: BUG-021 (stub analyzed_libs), BUG-024 (fix_zse5_libs.sh)
- Non-critical: BUG-022 (resource_info OOM), BUG-023 (fix_readmem_dump double)
