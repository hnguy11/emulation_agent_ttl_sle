---
title: "Build Flow — Compilation & Resume Instructions"
module: 02_execution
tags: [build, compilation, grdlbuild, zebu, resume, stages]
---

# Build Flow — Compilation & Resume Instructions

## Overview
This workspace compiles Zebu emulation models for the `nvlsi7_n2p` DUT
on the ZSE5 Zebu platform. The build system is `grdlbuild` (Gradle wrapper over DVB/make).

> **Multi-model support:** This agent supports multiple models. Replace `<MODEL_TARGET>` with
> the Gradle target suffix for the model you are building (e.g., `pkg_ghpf_model_zse5`).

### Supported Models

| Gradle Target | `-emu_model` Flag | Short Name |
|---------------|-------------------|------------|
| `pkg_ghpf_model_zse5` | `pkg_ghpf_model` | ghpf |
| `pkg_chp_model_p2e4_fast_zse5` | `pkg_chp_model_p2e4_fast` | chp_p2e4_fast |
| `pkg_chp_hubs_full_model_p2e4_zse5` | `pkg_chp_hubs_full_model_p2e4` | chp_hubs_full_p2e4 |
| `pkg_chp_model_p2e4_zse5` | `pkg_chp_model_p2e4` | chp_p2e4 |

## Pre-Compilation Steps

```bash
# Step 1: Set up environment — ALWAYS set WORKAREA and LM_PROJECT explicitly
cd /nfs/site/disks/ive_sle_zsc11_tbaziza/models/integrate_bundle1106
export WORKAREA=$(pwd)       # CRITICAL: always set from $PWD after cd, never rely on inherited value
export LM_PROJECT=DDG-TTLPKG  # CRITICAL: VSCode/Copilot shell sets an invalid fallback (SC_HNGUY11_UNKN);
                               # getLf rejects it and all DVB NB subtasks (jem, vcssimmpp, cpp) fail instantly
echo "WORKAREA: $WORKAREA  LM_PROJECT: $LM_PROJECT"  # verify both are correct

# Step 2: Verify disk space (need at least 200GB free for full build)
df -h /nfs/site/disks/ive_sle_zsc11_tbaziza | tail -1

# Step 3: Check Kerberos ticket validity
klist 2>&1 | grep -E "Expires|>>>"
```

## Full Compilation Command

```bash
# Full build from scratch (takes ~50+ hours)
cd /nfs/site/disks/ive_sle_zsc11_tbaziza/models/integrate_bundle1106
grdlbuild :emu_build:zebu:<MODEL_TARGET> -Penv=immediate
# Example for ghpf: grdlbuild :emu_build:zebu:pkg_ghpf_model_zse5 -Penv=immediate
```

## Resume / Restart from Zebu Stage

```bash
# Use -id (ignore deps) to restart from the Zebu compilation stage
# ONLY use AFTER analyze/fe_be have already started
grdlbuild :emu_build:zebu:<MODEL_TARGET> -id
# Example for ghpf: grdlbuild :emu_build:zebu:pkg_ghpf_model_zse5 -id
```

**When to use `-id`**:
- The analyze stage failed (e.g., NB kill, timeout) but jem/vcssimmpp already passed
- The `fe_be` stage failed but analyze already passed (shadow file exists)
- Any Zebu sub-stage failed and you want to retry without re-running upstream tasks

**When NOT to use `-id`**:
- After changing IP versions in `filelists/sip.list` (need full rebuild)
- After modifying RTL source files or `rtlchanges/` patches
- After changing `tool.cth` or compute settings affecting pre-stages
- On the very first build (no shadow files exist yet)

**How `-id` works**:
- `-id` = `-Pignore_deps` — tells Gradle to skip upstream dependency tasks
- Runs `make cleanall all` inside the Zebu Makefile target
- Checks `.shadow/` files to skip completed stages
- **WARNING**: Runs `cleanall` which can wipe `zcui.work/` — safe when fe_be already completed

## Build Stages (in order)

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

## fe_be Sub-Stages

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

## How to Know Compilation Passed Successfully

Run these checks **in order**. ALL must pass to confirm a successful build:

```bash
# 1. Shadow files — ALL 19 must exist (each represents a completed stage)
ls .shadow/ | wc -l
# ✅ Expected: 19
# ❌ If < 19: build did not complete. Identify the missing stage.

# 2. U0-U3 backend directories (FPGA partitions were placed & routed)
ls output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/zcui.work/backend_default/ | grep "^U[0-9]"
# ✅ Expected: U0, U1, U2, U3

# 3. MuDb info file non-empty (model database assembled)
wc -c output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/zcui.work/backend_default/MuDb/equis/info
# ✅ Expected: non-zero byte count

# 4. No missing shared library dependencies
ldd output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/simics_workspace/linux64/lib/zse_engine.so 2>/dev/null | grep "not found"
# ✅ Expected: EMPTY output (no missing libs)

# 5. readmem.dump is a regular file (not a symlink to itself)
file output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/readmem.dump
# ✅ Expected: "ASCII text" or "data"

# 6. No failure_info.log from last build run
ls output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/log/$(ls -t output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/log/ | head -1)/failure_info.log 2>/dev/null
# ✅ Expected: "No such file" (file should NOT exist)
```

**Quick one-liner verdict:**
```bash
[ $(ls .shadow/ | wc -l) -eq 19 ] && echo "✅ COMPILATION PASSED" || echo "❌ COMPILATION INCOMPLETE"
```

## Post-Build Steps (CRITICAL)

After successful `fe_be` completion:

```bash
# Step 1: Run post_zcui
grdlbuild :emu_build:zebu:<MODEL_TARGET>_post_zcui
# Example for ghpf: grdlbuild :emu_build:zebu:pkg_ghpf_model_zse5_post_zcui

# Step 2: Verify U0-U3 exist
ls output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/zcui.work/backend_default/ | grep "^U[0-9]"

# Step 3: Verify MuDb
wc -c output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/zcui.work/backend_default/MuDb/equis/info

# Step 4: Fix library symlinks (MANDATORY before testing)
bash scripts/fix_zse5_libs.sh

# Step 5: Verify no missing dependencies
ldd output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/simics_workspace/linux64/lib/zse_engine.so 2>/dev/null | grep "not found"
```

## Log File Locations

```
# Main grdlbuild log
output/grdlbuild/logs/emu_build.zebu.<MODEL_TARGET>.log
# Example for ghpf: output/grdlbuild/logs/emu_build.zebu.pkg_ghpf_model_zse5.log

# Build run log directory
output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/log/<TIMESTAMP>/

# Key files:
#   fe_be.NB.log       — main Zebu stage-by-stage progress
#   failure_info.log   — ONLY when build fails
#   zebu_tb.log        — zebu_tb packaging step

# Shadow files (presence = stage completed)
output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/.shadow/

# Find current run timestamp
ls -lt output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/log/ | head -5
```

## Build Session Log

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
