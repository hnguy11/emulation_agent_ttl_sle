---
title: "Commands Reference"
module: 02_execution
tags: [commands, shell, reference, grdlbuild, simregress, nbstatus]
---

# Commands Reference

> Add new commands here whenever you discover one that works. This is a living document.
> Commands use `<MODEL_TARGET>` (Gradle target suffix) and `<EMU_MODEL>` (emu_model flag).
> See the model table below for available models.

### Supported Models

| Gradle Target | `-emu_model` Flag | Reglist Suffix | Short Name |
|---------------|-------------------|----------------|------------|
| `pkg_ghpf_model_zse5` | `pkg_ghpf_model` | `doa_pkg_ghpf_model_zse5.list` | ghpf |
| `pkg_chp_model_p2e4_fast_zse5` | `pkg_chp_model_p2e4_fast` | `doa_pkg_chp_model_p2e4_fast_zse5.list` | chp_p2e4_fast |
| `pkg_chp_hubs_full_model_p2e4_zse5` | `pkg_chp_hubs_full_model_p2e4` | `doa_pkg_chp_hubs_full_model_p2e4_zse5.list` | chp_hubs_full_p2e4 |
| `pkg_chp_model_p2e4_zse5` | `pkg_chp_model_p2e4` | `doa_pkg_chp_model_p2e4_zse5.list` | chp_p2e4 |

## Build Commands

> ⚠️ **CRITICAL — Before every `grdlbuild` invocation, always set both:**
> ```bash
> export WORKAREA=$(pwd)        # exact path including .1/.2 suffix
> export LM_PROJECT=DDG-TTLPKG # prevents getLf license failures for jem/vcssimmpp/cpp NB tasks
> ```

### NVL Builds (zsc11 site)
| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `grdlbuild :emu_build:zebu:<MODEL_TARGET> -Penv=immediate` | Full build from scratch | First build or major changes |
| `grdlbuild :emu_build:zebu:<MODEL_TARGET> -id` | Resume from Zebu stage | After mid-build failure |
| `grdlbuild :emu_build:zebu:<MODEL_TARGET>_post_zcui` | Post-build steps only | After fe_be completes |
| `bash scripts/fix_zse5_libs.sh` | Fix library symlinks | After every fe_be build, before testing |

### TTL ZSE5 Builds (zsc16 site — ttlbxpkg workareas)
```bash
# Prerequisite — always set before launching
cd /nfs/site/disks/issp_ttl_emu_compile_001/<workarea>  # include .1/.2 suffix!
export WORKAREA=$(pwd)
export LM_PROJECT=DDG-TTLPKG
```

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `nohup grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb > /tmp/grdlbuild_ttlbx_nb.log 2>&1 &` | Full TTL ZSE5 NB build | Initial launch or relaunch |
| `ls -lt output/grdlbuild/logs/*.log \| head -10` | Check which grdlbuild tasks are running/done | Monitor progress |
| `tail -30 output/grdlbuild/logs/ttlbx_n2p.codegen_dv.jem.log` | Check jem DVB task log | After jem starts |
| `cat output/ttlbx_n2p/jem/build_summary.log` | DVB jem build summary (Passed/Skipped/Failed libs) | Diagnose jem failures |
| `cat output/ttlbx_n2p/vcssimmpp/build_summary.log` | DVB vcssimmpp build summary | Diagnose vcssimmpp failures |
| `cat output/ttlbx_n2p/cpp/build_summary.log` | DVB cpp build summary | Diagnose cpp failures |

### DVB `.done` File Recovery (TTL — after getLf / license failures)
```bash
# Find libs with stale (today's) .done timestamps
ls -la output/ttlbx_n2p/jem/lib/*/.*.done | awk '{print $6,$7,$8,$NF}' | grep "$(date +%b)"

# Find a reference file with a good (old) timestamp
REF=$(ls -lt output/ttlbx_n2p/jem/lib/*/.*.done | grep -v "$(date +%b  %e)" | tail -1 | awk '{print $NF}')

# Reset stale .done files to old timestamp
find output/ttlbx_n2p/jem/lib/ -name "*.done" -newer "$REF" -exec touch -r "$REF" {} \;
find output/ttlbx_n2p/vcssimmpp/lib/ -name "*.done" -newer "$REF" -exec touch -r "$REF" {} \;
find output/ttlbx_n2p/cpp/lib/ -name "*.done" -newer "$REF" -exec touch -r "$REF" {} \;

# Create missing .done files (cpp libs that compiled but have no marker)
# Only do this when .indicators shows STATUS:PASS and the .so file exists
touch -r output/ttlbx_n2p/cpp/lib/<lib>/analysis.log \
         output/ttlbx_n2p/cpp/lib/<lib>/.<lib>.done
```

### New Workarea Setup — cfg/compute.cth (TTL ZSE5, REQUIRED before first -nb build)

New workareas cloned from the TTLbx seed have an **empty** `cfg/compute.cth`. DVB requires COMPUTE sections for jem/vcssimmpp/cpp when `NB=1` is set (which PCD Makefile.cfg does unconditionally for ZSE5). Apply this fix before the first `-nb` build, then commit it:

```bash
cat > $WORKAREA/cfg/compute.cth << 'EOF'
[COMPUTE]
    Name = jem@zsc16
    type = batch
    qslot = /PCH/CSS/TTL/emu
    target = zsc16_express
    NBCMD = nbjob
    RAM = 32
    CPU = 4
    OS = SLES15

[COMPUTE]
    Name = vcssimmpp@zsc16
    type = batch
    qslot = /PCH/CSS/TTL/emu
    target = zsc16_express
    NBCMD = nbjob
    RAM = 32
    CPU = 4
    OS = SLES15

[COMPUTE]
    Name = cpp@zsc16
    type = batch
    qslot = /PCH/CSS/TTL/emu
    target = zsc16_express
    NBCMD = nbjob
    RAM = 32
    CPU = 4
    OS = SLES15

[COMPUTE]
    Name = _DEFAULT@zsc16
    type = batch
    qslot = /PCH/CSS/TTL/emu
    target = zsc16_express
    NBCMD = nbjob
    RAM = 32
    CPU = 4
    OS = SLES15
EOF

git -C $WORKAREA add cfg/compute.cth
git -C $WORKAREA commit -m "cfg/compute.cth: add DVB NB COMPUTE sections for zsc16"
```

> ⚠️ **RAM must be a valid NB class** — valid 4-core values: `4G, 16G, 28G, 32G, 52G, 64G, 80G, 100G, 128G, 150G, 200G, 512G`. **256G does NOT exist**. Wrong RAM → inner NB lib jobs silently fail. See BUG-058.

## Test Commands

| Command | What It Does |
|---------|-------------|
| `simregress -dut nvlsi7_n2p -save -no_xs -trex -emu_model <EMU_MODEL> -emu_tech zse5 -no_compress EMUL_QSLOT=/prj/sv/nvl/emu/interactive -trex- -P zsc11_express -Q /IVE/NVL/emu -l reglist/nvlsi7_n2p/emu/doa_<MODEL_TARGET>.list` | Submit DOA tests to NB/FM |

> Example for ghpf: `simregress ... -emu_model pkg_ghpf_model ... -l reglist/nvlsi7_n2p/emu/doa_pkg_ghpf_model_zse5.list`

## Monitoring Commands

| Command | What It Does |
|---------|-------------|
| `df -h /nfs/site/disks/ive_sle_zsc11_tbaziza \| tail -1` | Check disk space |
| `nbq -u tbaziza 2>/dev/null \| head -20` | Check running NB jobs |
| `nbstatus jobs --target <host>:<port>` | Check job status in feeder |
| `nbstatus tasks --target <host>:<port>` | Check overall feeder status |
| `ls output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/.shadow/` | Check completed build stages |
| `tail -10 <LOGDIR>/fe_be.NB.log` | Monitor fe_be progress |
| `cat <LOGDIR>/failure_info.log 2>/dev/null` | Check build failure details |
| `klist 2>&1 \| grep -E "Expires\|>>>"` | Check Kerberos ticket |

## NB Task Management

| Command | What It Does |
|---------|-------------|
| `nbtask stop --target <host>:<port> <taskid>` | Stop a hung task |
| `nbtask delete --target <host>:<port> --force <taskid>` | Force-delete a task |
| `nbtask load --target <host>:<port> <path/to/nbtask_conf>` | Load/reload task |

## Kerberos / Auth

| Command | What It Does |
|---------|-------------|
| `kinit` | Get new Kerberos ticket (prompts for password) |
| `kinit -R` | Renew existing ticket (no password needed) |
| `kinit -r 7d` | Get 7-day renewable ticket |
| `klist` | Show current ticket status |
| `ssh -o BatchMode=yes <host> "echo OK"` | Test SSH auth works |

## Verification Commands

| Command | What It Does |
|---------|-------------|
| `ldd output/.../zse_engine.so 2>/dev/null \| grep "not found"` | Check missing shared libs |
| `readelf -d <file.so> \| grep RPATH` | Check RPATH of a shared object |
| `ls output/.../zse5/.shadow/ \| wc -l` | Count completed stages (19 = all done) |
| `file output/.../readmem.dump` | Verify readmem.dump is regular file |

## Debug / Triage

| Command | What It Does |
|---------|-------------|
| `bash 05_knowledge_and_debugging/run_phase_detection_nvlax.sh [TEST_DIR] [TOP_N]` | Detect failure phase from logbook.log, score BUG-NNN files against symptoms, output top matches |

## Path Variables (for substitution in commands above)
- `<MODEL_TARGET>` = Gradle target suffix (e.g., `pkg_ghpf_model_zse5`)
- `<EMU_MODEL>` = `-emu_model` flag value (e.g., `pkg_ghpf_model`)
- `<LOGDIR>` = `output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5/log/<TIMESTAMP>/`
- `<ZSE5_DIR>` = `output/nvlsi7_n2p/emu/zebu_zebu/<EMU_MODEL>/zse5`
- `<host>:<port>` = NB feeder (e.g., `sccc14644327.zsc11:42711`)
