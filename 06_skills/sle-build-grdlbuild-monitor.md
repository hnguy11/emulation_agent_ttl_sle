---
name: sle-build-grdlbuild-monitor
description: "Monitor grdlbuild compilation progress and diagnose build failures. USE WHEN: grdlbuild VCS/ZSE build is running, need to check progress, detect failures early, identify which phase or task failed, parse error logs from analysis/elaboration/distcomp stages. Covers: build type identification (ZeBu/ZSE5 vs FPGA VCS slimsim — different outputs, logs, failure signals), grdlbuild.log monitoring, VCS analysis error parsing, elaboration error parsing, distcomp partition failure diagnosis, NB farm job status. Also covers: ZeBu (ZSE5) build monitoring via zCui orchestrator — compilation_status.log, zCui.log phase tracking, synthesis Bundle failure diagnosis, zTopBuild.log force assign verification (HFA001), zTime.log driverClk analysis, FPGA backend PnR progress tracking (spawned/PASSED/FAILED job counts), non-deterministic driverClk placement risk. Side-by-side ZeBu vs FPGA VCS comparison table with failure triage decision tree."
argument-hint: "Provide the WORKAREA path or grdlbuild log path. Optionally specify the MODEL name."
---

# grdlbuild Build Monitor Skill

## When to Use
- A `grdlbuild` compilation is running and you want to track progress
- A build failed and you need to identify the root cause
- You need to check if specific phases (codegen, analysis, elaboration) succeeded
- You want to find the first error in a long build log

## Build Type Quick Reference

Before doing anything, identify which build type you are dealing with. The grdlbuild target suffix and output directory are the definitive signals:

| Build Type | grdlbuild target suffix | Output directory | Orchestrator | Key logs |
|------------|------------------------|-----------------|-------------|----------|
| **ZeBu / ZSE5** | `_zse` (e.g., `pkg_chpr_p2e4_816_fast_zse`) | `output/$DUT/emu/zebu_zebu/$MODEL/zse5/` | zCui | `zCui.log`, `zTime.log`, `zTopBuild.log` |
| **FPGA slimsim** | `_vcs` with `emu:fpga:` prefix | `output/$DUT/emu/fpgasim_emuvcs/$MODEL/vcs/` | VCS | `emu_gen.log`, `analyze_summary.log`, `elab.log` |

> **Common confusion**: the `emuvcs_emuvcs` path (line below) is an **older VCS-only build variant** — it is NOT ZeBu. ZeBu always goes to `zebu_zebu/`. The FPGA slimsim model used in TTLbx SLE builds uses `fpgasim_emuvcs/`. All monitoring, failure detection, and debug commands differ between these two types — always confirm the build type before running any log commands.

**How to confirm which type you have (from the grdlbuild target):**
```bash
# ZSE5 targets contain "sle" and end with "_zse":
grdlbuild ttlbx_n2p:emu:sle:pkg_chpr_p2e4_816_fast_zse -nb        # → zebu_zebu/

# FPGA targets contain "fpga" and end with "_vcs":
grdlbuild ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -nb  # → fpgasim_emuvcs/
```

---

## Key Files and Paths

### grdlbuild Log
```
$WORKAREA/.grdlbuild_logs/grdlbuild.log
```
Contains timestamped entries for each task start/finish with exit codes and runtimes.

### VCS Build Output Directory
```
# FPGA slimsim builds (BUILD_DIRNAME=fpgasim) — used in TTLbx SLE builds:
$WORKAREA/output/$DUT/emu/fpgasim_emuvcs/$MODEL/vcs/
# Older VCS-only (non-FPGA) builds — NOT ZeBu, NOT used in current TTLbx SLE:
$WORKAREA/output/$DUT/emu/emuvcs_emuvcs/$MODEL/vcs/
# ZeBu (ZSE5) builds — completely separate orchestrator, different output tree:
$WORKAREA/output/$DUT/emu/zebu_zebu/$MODEL/zse5/
```
Subdirectories: `analysis/`, `elab/`, `transactors/`, `log/`

### emu_gen.log (Pre-compilation Actions)
```
$WORKAREA/output/$DUT/emu/{fpgasim_emuvcs,emuvcs_emuvcs}/$MODEL/vcs/log/emu_gen.log
```
This log tracks all the buildit.py actions (rtlchanges_precheck, gen_dut_cfg, copy_rom_files, etc.) BEFORE VCS analysis/elaboration starts. Each action is logged with `EXECUTING ACTION <name>` and `action <name> PASSED/FAILED`.

### Distcomp Logs
```
$WORKAREA/output/$DUT/emu/{fpgasim_emuvcs,emuvcs_emuvcs}/$MODEL/vcs/analysis/dpc_log/
$WORKAREA/output/$DUT/emu/{fpgasim_emuvcs,emuvcs_emuvcs}/$MODEL/vcs/elab/dpc_log/
```

## Monitoring Procedure

### Step 1: Check overall progress
```bash
tail -30 $WORKAREA/.grdlbuild_logs/grdlbuild.log
```
Each line shows `[timestamp] :DUT:phase:task started/finished (exit: N, runtime: HH:MM:SS, status: [Success/Failed])`.

**Note**: If `tail` hangs on NFS, use `cat file | tail -30` as a workaround.

### Step 1b: Check emu_gen actions (pre-compilation phase)
```bash
grep "EXECUTING ACTION\|PASSED\|FAILED" $WORKAREA/output/$DUT/emu/{fpgasim_emuvcs,emuvcs_emuvcs}/$MODEL/vcs/log/emu_gen.log | tail -30
```
This shows the sequence of buildit.py actions and their pass/fail status. Key actions to watch:
- `rtlchanges_precheck` — validates all rtlchange .ref files
- `gen_dut_cfg` — generates DUT configuration
- `copy_pkg_upf_changes` — UPF patching
- Once all emu_gen actions pass, the Makefile-driven VCS analysis/elaboration begins

### Step 2: Count successes vs failures
```bash
grep -c "Success" $WORKAREA/.grdlbuild_logs/grdlbuild.log
grep "FAIL\|Failed\|error" $WORKAREA/.grdlbuild_logs/grdlbuild.log
```

### Step 3: Identify current phase
The grdlbuild task dependency chain for a VCS emu build typically follows this order:
1. `codegen_rtl` — RTL codegen (v2k, upf, sai)
2. `codegen_dv` — DV codegen (JEM trackers, VIP shared objects, fuse picker)
3. `filelists_rtl` — filelist generation, fix_missing_dware/visa
4. `emu:common:pkg_tls_compile_ready` — common compilation readiness gate
5. `emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs` (or equivalent) — the actual VCS build:
   - `flowgen` — generates emu flow artifacts
   - `gendvflist` — generates DV filelists
   - `make cleanall all` — runs VCS analysis + elaboration

#### Sub-phases within `make all` (in order, with wall times from FPGA VCS pkg_chpr_cfgr_p2e0_816_fast build):
1. `emu_gen.log` — buildit.py actions (~2-5 min)
2. `gen_dv_flist.log` — genfilelist_dv output (~5-8 min)
3. `gen_analyze_make.log`, `dw_gen.log`, `spark_co.log` — analysis setup (~1 min each)
4. `handle_dynamic_blackboxes.log` — (~5-15 min, grows to ~4MB)
5. `pre_analyze.log` — pre-analysis checks (~1 min)
6. VCS analysis — distributed via NB farm jobs (~20-40 min, creates `<TIMESTAMP>/analyze_summary.log`)
7. VCS elaboration — creates `<TIMESTAMP>/elab.log`

### Step 4: If build failed, find the error
For VCS **analysis** errors:
```bash
grep -r "Error-\|error:" $WORKAREA/output/$DUT/emu/{fpgasim_emuvcs,emuvcs_emuvcs}/$MODEL/vcs/analysis/ | head -20
```

For VCS **elaboration** errors:
```bash
grep -r "Error-\|error:" $WORKAREA/output/$DUT/emu/{fpgasim_emuvcs,emuvcs_emuvcs}/$MODEL/vcs/elab/ | head -20
```

For **distcomp** partition failures (when using distributed compilation):
```bash
# Find which partition failed
grep -l "Error\|FAIL" $WORKAREA/output/$DUT/emu/emuvcs_emuvcs/$MODEL/vcs/analysis/dpc_log/*.log | head -5
# Then read the failing partition log
```

### Step 5: Check NB farm job status (if build uses nbjob)
```bash
nbjob list --user $USER | grep -i "pkg_chpr\|emu"
```

## Common Build Failure Patterns

### Missing file / include path
```
Error-[CSINFI] ... Could not find include file ...
```
**Fix**: Check FPGA_CHANGES.cfg or model's `analysis_opts` for missing `-f` or `+incdir+` paths.

### Undefined module
```
Error-[URMI] ... Undefined module instantiation ...
```
**Fix**: Missing rtlchange file or lib not included. Check `fpga_remove_libs` didn't exclude something needed, or a rtlchange file wasn't copied.

### Multiply defined module (MPD)
```
Error-[MDNOL] ... Module was already defined ...
```  
**Fix**: Conflict between rtlchange replacement file and original. Check FPGA_CHANGES.cfg for duplicate file inclusions. Common cause: FPGA_CHANGES.cfg `prepend: file:` adds a file (e.g., emu_clk_osc.sv), but an IP's source also `+incdir+`-includes the same file. Fix with `ifndef` include guards in the FPGA replacement file.

### Syntax error in prepended file (rtl_configs_lib)
```
Error-[SE] Syntax error
  ... parameter int FREQ_WIDTH = 16;
```
**Root cause**: `rtl_configs_lib` libraries do NOT use the global vlog_opts file (no `global_fpgasim_pkg_ch_vlog_opts.f`), so they lack `-sverilog`. SystemVerilog syntax like `parameter int` causes a syntax error.
**Fix**: Add `-sverilog` to the `prepend: vlog_opts:` section of the second `.*:` block in FPGA_CHANGES.cfg. This ensures all libraries get the flag even if they don't use the global opts.

### Unbalanced ifdef/endif in IP source
```
Error-[IWNMEE] `ifdef or `ifndef with no matching ...
```
**Root cause**: IP source file has more ifdef/ifndef than endif. Often hidden by other builds because a define (like `HUB_URI_DISABLE`) skips the broken section entirely.
**Fix**: Compare the FPGA build's defines against the working ZSE build's defines. If ZSE defines a macro (e.g., `+define+HUB_URI_DISABLE=1`) that skips the broken block, add the same define to the FPGA build's FPGA_CHANGES.cfg for the affected library.
**Diagnosis**: Count ifdef/ifndef vs endif: `grep -cn 'ifdef\|ifndef' file.sv` vs `grep -cn 'endif' file.sv`. If counts differ, there's an imbalance.

### Missing hierarchy defines
```
Macro (nap_cdie1_link0_top) is undefined ...
```
**Root cause**: IP's hubs_hier_defines.sv only defines cdie0 variants, but other files reference cdie1 unconditionally.
**Fix**: Add missing defines to `fpga_missing_hier_defines.sv` (prepended via FPGA_CHANGES.cfg to the affected library).

### Include guard pattern for FPGA replacement files
When multiple IPs `+incdir+`-include the same source file (e.g., emu_clk_osc.sv), and the FPGA build also `prepend: file:` adds its replacement version, VCS sees the module twice (MPD). Fix:
```systemverilog
`ifndef FPGA_EMU_CLK_OSC_SV
`define FPGA_EMU_CLK_OSC_SV
// ... module body ...
`endif
```

### Guard defines for libraries missing global opts
Some libraries (e.g., `rtl_configs_lib`) don't use the global analysis opts file. If the FPGA build's `prepend: file:` files depend on `+define+` flags from global opts, those defines will be missing. Fix: Create a guard-defines file (e.g., `fpga_emu_clk_guards.sv`) with `ifndef`-guarded defines and prepend it as the FIRST file via FPGA_CHANGES.cfg.

### UPF / power-aware errors
```
Error-[UPF-...]
```
**Fix**: Check `global_fpgasim_upf_elab_opts.f` or the UPF soc_include_json config.

### grdlbuild --project-dir resolves to wrong workspace
The `grdlbuild` wrapper resolves `--project-dir` via cth env setup. If it picks up a stale workspace:
- **Workaround**: Call gradle directly with explicit `--project-dir $WORKAREA/flows/grdlbuild`
- **Better**: Ensure `WORKAREA` is set correctly *before* invoking `grdlbuild`, and that no stale cth session is cached

## Typical Build Variables

| Variable | Example (FPGA VCS) |
|----------|-------------------|
| DUT | `ttlbx_n2p` |
| MODEL | `pkg_chpr_cfgr_p2e0_816_fast_fpga_slimsim` |
| TECH | `vcs` |
| BUILD_DIRNAME | `fpgasim` |
| grdlbuild task | `:ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs` |

## Incremental Builds

When re-running after fixing errors, use the `-id` flag to skip already-completed tasks:
```bash
grdlbuild :ttlbx_n2p:emu:fpga:pkg_chpr_cfgr_p2e0_816_fast_vcs -id
```
This tells gradle to treat tasks whose inputs haven't changed as up-to-date, skipping them. This is essential when iterating on precheck or compilation failures.

## NFS Performance Notes

- **PREFER `read_file` tool over terminal commands** for all log monitoring. NFS-mounted files frequently stall `tail`, `cat`, and `grep` in interactive terminals. The `read_file` tool bypasses this and returns content reliably.
- Only use terminal commands for files > 50MB (where `read_file` fails) — use targeted `grep -c` or `wc -l`, NOT open-ended `cat`/`tail`.
- When monitoring a long-running build, check file size via `read_file` of the directory listing or `ls -la` to verify the log is still growing.
- `ls -lt $LOG_DIR/ | head -10` shows the most recently modified logs, useful for finding the active phase.

---

## ZeBu (ZSE5) Build Monitoring

ZeBu builds are launched via grdlbuild with a `_zse` task suffix (e.g., `grdlbuild :ttlbx_n2p:emu:sle:pkg_chpr_cfgr_p2e0_816_fast_zse -id`). After grdlbuild finishes the initial VCS compilation setup, the ZeBu `zCui` orchestrator takes over and runs the full ZeBu flow. **zCui has its own task scheduling, logging, and status tracking** that is completely separate from grdlbuild.log.

### ZeBu Build Output Directory
```
$WORKAREA/output/$DUT/emu/zebu_zebu/$MODEL/
```
The zCui work directory is:
```
$BUILD/zse5/zcui.work/
```
Where `$BUILD = $WORKAREA/output/$DUT/emu/zebu_zebu/$MODEL`.

### ZeBu Key Log Files
| Log | Path | Purpose |
|-----|------|---------|
| zCui.log | `$BUILD/zse5/zcui.work/zCui/log/zCui.log` | Master orchestrator log — all task spawns, terminations, failures |
| compilation_status.log | `$BUILD/zse5/zcui.work/compilation_status.log` | Quick summary: Running/Waiting/Finished task counts |
| VCS_Task_Builder.log | `$BUILD/zse5/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log` | Power-aware VCS elaboration (huge: 100MB+, 1M+ lines) |
| Bundle synthesis logs | `$BUILD/zse5/zcui.work/zCui/log/design_Default_RTL_GroupBundle_NNN_Synthesis.log` | Per-bundle ZFAST synthesis |
| zTopBuild.log | `$BUILD/zse5/zcui.work/zebu.work/zTopBuild.log` | ZeBu synthesis merge, force assign matching, FASTCLOCK detection |
| zPar.log | `$BUILD/zse5/zcui.work/zebu.work/zPar.log` | Partitioning |
| zTime.log | `$BUILD/zse5/zcui.work/zebu.work/zTime.log` | Pre-FPGA timing — **driverClk speed is here** |
| zTime_fpga.log | `$BUILD/zse5/zcui.work/backend_default/zTime_fpga.log` | Post-FPGA timing (final driverClk) |

### ZeBu Pre-zCui Stages (grdlbuild task log)

Before zCui even starts, grdlbuild runs **three make phases** sequentially. These are tracked in the **gradle task log** (`$WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log`), NOT in zCui.log. Failures here produce `Exit status: 2` in the task log and grdlbuild.log shows `[Failed]`.

**Monitor progress with:**
```bash
cat $WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log | grep "Target:\|PASSED\|FAILED\|Executing\|#####\|Exit"
```

#### Make Phase 1: `cleanall flowgen` (~5-10 min)
| Stage | Log File | Duration | Notes |
|-------|----------|----------|-------|
| prerequisite | (inline in task log) | ~2 min | Creates output-dir, copies user_inputs. **Can fail with `cp: File exists`** if stale files remain — fix: `rm -rf $BUILD/zse5` |
| spark_co | `$BUILD/zse5/log/spark_co.log` | ~1 min | Transactor checkout |
| emu_gen | `$BUILD/zse5/log/emu_gen.log` | ~2-5 min | RTL generation via buildit.py (rtlchanges_precheck, gen_dut_cfg, copy_rom_files, etc.) |

#### Make Phase 2: `gendvflist` (~5-8 min)
| Stage | Log File | Duration | Notes |
|-------|----------|----------|-------|
| gen_dv_flist | `$BUILD/zse5/genfilelist_dv/log/dvJsonGenerator.log` | ~5-8 min | DVB file list generation via dvJsonGenerator.py |

#### Make Phase 3: `runelab` (~30-60 min)
This is the largest pre-zCui phase. It runs these stages in dependency order:

| Stage | Log File | Duration | Notes |
|-------|----------|----------|-------|
| c_compile | `$BUILD/zse5/log/c_compile.log` | ~1 min | Testbench C++ compile (libemubuildtb.so) |
| zse_lint | (inline) | ~1 min | Optional lint check |
| gen_analyze_make | `$BUILD/zse5/log/<TIMESTAMP>/gen_analyze_make.log` | ~1 min | Generate analysis makefiles via genFlow.py |
| dw_gen | `$BUILD/zse5/log/dw_gen.log` | ~1 min | DesignWare library generation |
| pre_analyze | `$BUILD/zse5/log/pre_analyze.log` | ~1-2 min | Pre-analysis checks via buildit.py |
| **analyze** | `$BUILD/zse5/log/<TIMESTAMP>/analyze_summary.log` | **15-40 min** | **VCS analysis of all RTL libraries** — distributed via NB farm. This is the longest pre-zCui stage. Check `analyze_summary.log` for PASSED/FAILED counts. |
| gen_elab_src | `$BUILD/zse5/log/<TIMESTAMP>/gen_elab_src.log` | ~1 min | Generate elaboration sources |
| zebu_tb | (inline) | ~1 min | ZeBu testbench build |
| prepare_spark + spark_tb | (inline) | ~1 min | Spark transactor prep |
| tb | (inline) | ~1 min | Final testbench link |

After all `runelab` stages complete, grdlbuild invokes `fe_be` which launches **zCui**.

### ZeBu zCui Phase Order
Once zCui starts, it schedules tasks in this dependency order (from `compilation_status.log`):

| Phase | Task Type | Duration | What to Check |
|-------|-----------|----------|---------------|
| 1. Target_Config | external | ~1 min | Tool version, project setup |
| 2. design_Fs_Macro | external | ~1 min | FS macro generation |
| 3. VCS_Task_Builder | external (NB farm) | **3-6 hours** | Power-aware VCS elaboration with UPF. Submitted to Netbatch. |
| 4. Synthesis Bundles (1-2057) | external (parallel) | **1-3 hours** | ZFAST synthesis of module bundles. Up to ~2057 bundles. |
| 5. zTopBuild | external | 30-90 min | Design merge, force assign application, FASTCLOCK detection |
| 6. zPar | external | 1-3 hours | FPGA partitioning, SCC reduction |
| 7. zTime | external | 5-15 min | Pre-FPGA timing analysis — **check driverClk here** |
| 8. Design_FPGA_Dispatch | internal | Variable | Vivado synthesis per FPGA |
| 9. zDB_Global | external | 10-30 min | Global database |
| 10. zTimeFpga | external | 5-15 min | Post-FPGA timing (final driverClk) |
| 11. SingleBackend_Compilation_Checker | internal | ~1 min | Final pass/fail check |

### ZeBu Monitoring Procedure

> ⚠️ **CRITICAL — Use WORKAREA-specific sources ONLY. Never use the shared NB feeder log alone.**
>
> The NB feeder log at `/tmp/gradle.nbflow.hnguy11/logs/nbfeeder.*.log` is **shared across ALL builds** that ran on the same day — including builds from other workareas (e.g., non-.1 vs .1). Task IDs in that log accumulate from every grdlbuild launched by the user. Reading it without filtering by workarea path will mix status from other builds and produce incorrect results.
>
> **Always use these WORKAREA-specific primary sources for ZSE5 monitoring:**
> | Stage | Correct Log to Use |
> |-------|--------------------|
> | Pre-zCui (spark_co, emu_gen, analyze, etc.) | `$WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log` |
> | zCui phase overview | `$BUILD/zse5/zcui.work/compilation_status.log` |
> | zCui task detail | `$BUILD/zse5/zcui.work/zCui/log/zCui.log` |
> | ZSE5 output existence | `ls $BUILD/zse5/zcui.work/` |
>
> Where `$BUILD = $WORKAREA/output/ttlbx_n2p/emu/zebu_zebu/$MODEL` — all paths use the **exact same `$WORKAREA`** (including any `.1`, `.2` suffix).
>
> **When you MUST check the feeder log** (e.g., to get NB job details), ALWAYS verify the task file path in every entry contains your exact `$WORKAREA`:
> ```bash
> grep "pkg_chpr_p2e4_816_fast" /tmp/gradle.nbflow.hnguy11/logs/nbfeeder.*.log | grep "$WORKAREA"
> # If the grep hits entries with a DIFFERENT workarea path → those are from a different build. Ignore them.
> ```

#### Pre-zCui Status Check
Before zCui starts (~30-60 min after grdlbuild launch), the gradle task log tracks pre-zCui stages:
```bash
# Check which stages have passed/failed
cat $WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log | grep "Target:\|PASSED\|FAILED\|#####\|Exit"

# Check if zCui has started (compilation_status.log appears when zCui starts)
ls -la $BUILD/zse5/zcui.work/compilation_status.log
```
If `compilation_status.log` doesn't exist, the build is still in pre-zCui stages. Check the gradle task log for progress. Common pre-zCui failures:
- `cp: File exists` at prerequisite stage → `rm -rf $BUILD/zse5`, then relaunch
- `FAILED` in analyze_summary.log → VCS analysis error, check the specific library's `.scrout` log

#### zCui Quick Status Check
Use `read_file` tool (NOT terminal `cat`):
```
read_file(filePath="$BUILD/zse5/zcui.work/compilation_status.log", startLine=1, endLine=100)
```
Shows: `[Running - N task(s)]`, `[Waiting - N task(s)]`, `[Finished - N task(s)]`.

**CRITICAL — Check the Subtask Names:** `compilation_status.log` lists each task BY NAME under its status category. This tells you exactly which zCui subtask is currently active:
```
[Running - 1 task(s)]
VCS_Task_Builder
[Waiting - 21 task(s)]
design_Default_RTL_GroupBundle_0_Synthesis
design_Default_RTL_GroupBundle_1_Synthesis
...
zTopBuild
zPar
zTime
Design_FPGA_Dispatch
zTimeFpga
[Finished - 5 task(s)]
Target_Config
design_Fs_Macro
...
```

After identifying the running subtask, check its **specific log** for detailed progress:

| Running Subtask | Log Path (relative to `zcui.work/`) | Size | Monitor Method |
|----------------|--------------------------------------|------|----------------|
| `VCS_Task_Builder` | `zCui/log/vcs_splitter_VCS_Task_Builder.log` | 50-150 MB | Terminal `grep -c 'Error-'`; `ls -la` for freshness |
| `design_*_Synthesis` | `zCui/log/design_Default_RTL_GroupBundle_NNN_Synthesis.log` | 1-10 MB | `read_file` last 50 lines |
| `zTopBuild` | `zebu.work/zTopBuild.log` | 5-50 MB | `read_file` — grep for HFA001, FASTCLOCK |
| `zPar` | `zebu.work/zPar.log` | 5-50 MB | `read_file` last 100 lines |
| `zTime` | `zebu.work/zTime.log` | <1 MB | `read_file` — driverClk result |
| `Design_FPGA_Dispatch` | (distributed) | N/A | Check `zCui.log` for spawned/PASSED/FAILED |
| `zTimeFpga` | `backend_default/zTime_fpga.log` | <1 MB | `read_file` — final driverClk |

#### Detailed Progress from zCui.log
Use `read_file` on `zCui.log` (check last 50 lines for recent activity):
```
read_file(filePath="$BUILD/zse5/zcui.work/zCui/log/zCui.log", startLine=<end-50>, endLine=<end>)
```
Look for:
- `"<TaskName> normal task termination"` — task completed successfully
- `"<TaskName> abnormal task termination"` — task FAILED
- `"Compilation Ended successfully"` — entire build PASSED
- `"Compilation Ended abnormally"` — entire build FAILED

#### VCS_Task_Builder Progress (longest single phase)
This log is typically 50-150 MB / 1M+ lines — too large for `read_file`. Use terminal-based targeted commands:
```bash
# Check log size (growing = still running)
ls -la $BUILD/zse5/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log | awk '{print $5, $6, $7, $8}'

# Check for errors (should be 0)
grep -c 'Error-' $BUILD/zse5/zcui.work/zCui/log/vcs_splitter_VCS_Task_Builder.log
```

**Preferred approach**: Instead of parsing VCS_Task_Builder.log directly, check `compilation_status.log` and `zCui.log` via `read_file`:
- If `compilation_status.log` still shows `VCS_Task_Builder` under `[Running]` → still active
- When `zCui.log` shows `"VCS_Task_Builder normal task termination"` → completed, synthesis begins next

#### Synthesis Bundle Failures
If the build fails during synthesis, zCui.log will show which Bundle had `abnormal task termination`:
```bash
# Find failed bundles
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | grep "abnormal"

# Read the failed bundle's log
cat $BUILD/zse5/zcui.work/zCui/log/design_Default_RTL_GroupBundle_NNN_Synthesis.log | grep -i "error\|fail\|fatal" | tail -20
```

**Common synthesis failure**: `clock_boundary_marker` directive causes `fatal error in ZFAST: Unsupported System Task $clock_boundary_marker_task` in ZeBu V-2024.03-1.7. Fix: comment out `clock_boundary_marker` from sle_dut.utf (pre-staged as commented out already). `force assign -value 0` on PCD IO pads is DEPRECATED (breaks functional signals like EPD_ON). Wait for tool upgrade to re-enable `clock_boundary_marker`.

#### Pre-zCui Failure: `cp: File exists` (Exit Status 2)
This failure occurs **before zCui even starts** — in the grdlbuild `cleanall flowgen` phase. Symptom in the gradle task log (`$WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log`):
```
cp: cannot create regular file '.../zse5/user_inputs/Makefile': File exists
cp: cannot create regular file '.../zse5/user_inputs/Makefile.cfg': File exists
cp: cannot create directory '.../zse5/user_inputs/compute': File exists
make: *** [.../Makefile.common:36: .../zse5/.shadow/prerequisite] Error 1
Exit status: 2
```
**Root cause**: DVB's `Makefile.common` prerequisite target (line 36) uses `\cp -Hrf` (without `-f` flag) to copy build configs into `zse5/user_inputs/`. When a previous failed or interrupted build leaves stale files in that directory, the copy command fails on existing files.

**Fix**: Manually remove the stale `zse5/` directory, then relaunch with the same `-id` command:
```bash
rm -rf $BUILD/zse5
grdlbuild :ttlbx_n2p:emu:sle:<model>_zse -id
```
`.nfs*` busy-file errors from `rm -rf` are harmless (NFS lock files from old log processes).

#### Post-zTopBuild: Verify Force Assign Matching
```bash
# Check for HFA001 warnings (force assign that didn't match = dead fix)
grep "HFA001" $BUILD/zse5/zcui.work/zebu.work/zTopBuild.log

# Check FASTCLOCK detection
grep "FASTCLOCK_GENERIC" $BUILD/zse5/zcui.work/zebu.work/zTopBuild.log | head -10
```
If HFA001 appears for an io1p2 force assign, the RTL signal name is wrong. See the `sle-build-zebu-driverclock-debug` skill for the correct pattern (`io1p2_inst.xio_pad_1p2`, NOT `io1p2_inst.pad` or `*probe_xio_pad*`).

#### driverClk Speed Check (Critical)
After zTime completes:
```bash
grep -E "driverClk|kHz|Critical" $BUILD/zse5/zcui.work/zebu.work/zTime.log | head -10
```
After zTimeFpga completes:
```bash
grep -E "driverClk|kHz|Critical" $BUILD/zse5/zcui.work/backend_default/zTime_fpga.log | head -10
```
- **> 200 kHz**: Acceptable for most emulation scenarios
- **< 200 kHz**: Likely a FASTCLOCK DPO bottleneck — investigate with the `sle-build-zebu-driverclock-debug` skill
- **CRITICAL**: Same model can produce wildly different driverClk across builds (e.g., 612 kHz vs 10 kHz from same workspace) due to non-deterministic zPar placement. A single "good" build does NOT mean the FASTCLOCK DPO issue is resolved.

#### FPGA Backend PnR Progress Tracking
After zPar/zTime, the build enters FPGA backend (Vivado ISE place-and-route). This phase spawns hundreds of parallel Netbatch jobs:
```bash
# Count spawned, completed, and failed PnR jobs:
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | grep -c "spawned"
echo " spawned jobs"
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | grep -c "PASSED"
echo " PASSED jobs"
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | grep -c "FAILED"
echo " FAILED jobs"

# Check the most recent activity:
cat $BUILD/zse5/zcui.work/zCui/log/zCui.log | tail -n 20
```
Typical PnR: ~4000-5000 jobs spawned (multiple strategies per FPGA unit), completion takes 2-6 hours. Each FPGA has multiple PnR strategies — only one needs to succeed per unit.

**IMPORTANT**: `compilation_status.log` may not exist during the PnR phase (it's created at a later stage). Use `zCui.log` directly for progress tracking during backend.

### ZeBu Background Monitor Script
For long-running ZeBu builds, deploy a background monitor script per the template in `sle-build-iterative-build-monitor-fix.md` (ZeBu Step 3). The script covers two phases:

**Pre-zCui monitoring** (poll every 60 sec):
1. Detect new `log/<TIMESTAMP>/` subdirs — signals a new build run started
2. Check `failure_info.log` in the **current run's log dir only** — never in the baseline dir that existed at script start (that is stale from a prior run)
3. Track `analyze_summary.log` for PASSED/FAILED counts

**zCui monitoring** (poll every 5 min, once `zcui.work/` appears):
4. Detect `"Compilation Ended abnormally"` in zCui.log (the only definitive failure signal)
5. After zTopBuild completes, check for HFA001 force assign mismatches
6. After zTime appears, parse driverClk and alert if < 200 kHz
7. On completion or failure, send email with WORKAREA, MODEL, and build summary

### Two-Layer Monitoring Pattern (Recommended)

**Layer 1: Background monitor script**
- Runs via `nohup`, survives terminal/conversation disconnects
- Log file: `/tmp/monitor_<WORKAREA_STEM>_<MODEL>.log` — unique per build, even for parallel builds
- See `sle-build-iterative-build-monitor-fix.md` for the full script template and deployment command

**Layer 2: Periodic foreground status check**
- When user asks for status: `tail -30 /tmp/monitor_<WORKAREA_STEM>_<MODEL>.log`
- Also check logs directly when needed: `compilation_status.log`, `zCui.log`, `analyze_summary.log`
- **Do NOT spawn background terminals for one-off status checks** — accumulate and clutter

Key implementation notes:
- Use `bash` (not tcsh) — tcsh lacks `$()`, `[[ ]]`, and heredocs
- Use `cat file | grep` instead of `grep file` to avoid NFS hangs
- **WORKAREA and MODEL must be hardcoded inside the script** at deployment — never inherit from shell env. User may have multiple parallel builds in different workareas; each monitor must be explicitly bound to one.
- **Do NOT use `pgrep`** — it is prohibited in this shell environment. Use file-based signals only.
- **STARTUP_LOG_DIR baseline is mandatory**: capture the newest existing log subdir at startup. Only report failures from NEW log subdirs created after startup — otherwise the monitor sees stale `failure_info.log` from prior runs and immediately exits with a false positive.
- Monitor log goes to `/tmp` with WORKAREA+MODEL in the filename — parallel builds get separate logs
- Include WORKAREA stem AND MODEL in every email subject — user runs multiple parallel builds
- Email address: always use `hoa.nguyen@intel.com` — do NOT derive from `whoami`
- **CRITICAL — Backend FPGA P&R false positives**: `backend_default_U*_M*_F*_L* abnormal task termination` is **NOT a build failure**. The only definitive failure signal is `"Compilation Ended abnormally"` in zCui.log.

---

## ZeBu vs FPGA VCS: Side-by-Side Comparison

Use this section whenever you need to branch on build type — different logs, different failure signals, different monitoring tools.

| Dimension | ZeBu / ZSE5 | FPGA slimsim (VCS) |
|-----------|------------|---------------------|
| **grdlbuild target** | `emu:sle:..._zse` | `emu:fpga:..._vcs` |
| **Output root** | `output/$DUT/emu/zebu_zebu/$MODEL/zse5/` | `output/$DUT/emu/fpgasim_emuvcs/$MODEL/vcs/` |
| **Primary orchestrator** | zCui (Cadence ZeBu) | VCS (make + distcomp) |
| **Build duration** | ~25-50 hrs total | ~2-5 hrs |
| **driverClk check** | YES — mandatory mid-build (`zTime.log`) | NO — not applicable |
| **Mid-build monitor** | `monitor_build.sh` → `/tmp/monitor_<WS>_<MODEL>.log` | `fpga_vcs_build_monitor.sh` → `output/.fpga_vcs_build_monitor.out` |
| **Progress log** | `zcui.work/zCui.log` | `emu_gen.log` → `analyze_summary.log` → `elab.log` |
| **Failure signal** | `"Compilation Ended abnormally"` in zCui.log | `Error-[` in `analysis/dpc_log/` or `elab/dpc_log/` |
| **Phase detection** | zCui stages: VCS_Task_Builder → Synthesis Bundles → zTopBuild → zPar → zTime → FPGA → zTimeFpga | VCS stages: emu_gen → analysis → elaboration |
| **False positive risk** | Backend P&R strategy failures (`abnormal task termination`) — ignore unless `Compilation Ended abnormally` | None — VCS `Error-[` is definitive |
| **Post-build verification** | 6 pass checks: shadow files, U0-U3 dirs, MuDb, ldd, readmem.dump, failure_info.log | Check elab exit code and `elab.log` for errors |
| **Fix → relaunch flag** | `-nb -id` (skip completed ZSE5 stages) | `-nb -id` (skip completed VCS stages) |

### Which logs to check first (by build type)

**ZeBu (ZSE5):**
```bash
# 1. Overall grdlbuild progress (pre-zCui)
cat $WORKAREA/output/grdlbuild/logs/ttlbx_n2p.emu.sle.*_zse.log | grep "Target:\|PASSED\|FAILED"

# 2. zCui orchestrator status
grep -E "stage|Bundle|FAILED|PASSED|Compilation Ended" $ZSE5_OUT/zcui.work/zCui.log | tail -10

# 3. driverClk (once zTime stage appears)
grep -E "driverClk|kHz" $ZSE5_OUT/zcui.work/zebu.work/zTime.log | head -5
```

**FPGA VCS:**
```bash
# 1. Pre-compilation actions
grep "EXECUTING ACTION\|PASSED\|FAILED" $FPGA_OUT/log/emu_gen.log | tail -20

# 2. VCS analysis errors
grep -r "Error-\|error:" $FPGA_OUT/analysis/dpc_log/ | head -20

# 3. VCS elaboration errors
grep -r "Error-\|error:" $FPGA_OUT/elab/dpc_log/ | head -20
```

### Failure triage decision tree (by build type)

```
Build failed — which type?
│
├── ZSE5 (_zse target, zebu_zebu/ output)
│   ├── Failed before zCui started?
│   │   └── Check gradle task log: ...emu.sle.*_zse.log for FAILED
│   ├── Failed during synthesis?
│   │   └── grep "abnormal" zCui.log → read bundle failure log
│   ├── driverClk < 200 kHz?
│   │   └── Read sle-build-zebu-driverclock-debug.md immediately
│   └── "Compilation Ended abnormally" in zCui.log?
│       └── Check zCui.log + zTopBuild.log for root cause
│
└── FPGA VCS (_vcs target, fpgasim_emuvcs/ output)
    ├── Failed in emu_gen phase?
    │   └── grep "FAILED" emu_gen.log → find the failing action
    ├── Failed in analysis?
    │   └── grep "Error-[" analysis/dpc_log/*.log
    ├── Failed in elaboration?
    │   └── grep "Error-[" elab/dpc_log/*.log
    └── rtlchanges issue?
        └── Check rtlchanges_precheck.log or rtlchanges_postcheck.log
```
