---
title: "Common Failure Patterns"
module: 05_knowledge_and_debugging
tags: [patterns, failures, categories, recurring, classification]
---

# Common Failure Patterns

> Recurring issue categories and their general resolution strategies.
> When you encounter a new bug that fits a pattern, add a reference here.
> When you discover a NEW pattern, create a new section.

## Pattern 1: Interpreter / Shebang Errors
- **Symptom**: Script exits immediately; `bad interpreter: No such file or directory`
- **Cause**: Script uses a pinned interpreter path that doesn't exist on SLES15
- **General Fix**: Replace pinned path with generic `/usr/intel/bin/python3` or `/usr/intel/bin/perl`
- **Known-Bad Paths**: `/usr/intel/bin/python3.7.4`, `/usr/intel/pkgs/python3/3.7.4/bin/python3`, `/usr/intel/bin/python2.7`, `/usr/intel/pkgs/perl/5.14.1/bin/perl`
- **Known-Good Paths**: `/usr/intel/bin/python3` (→ 3.11.1), `/usr/intel/bin/perl`
- **Related Bugs**: BUG-010, BUG-018, BUG-019

## Pattern 2: IP / Filelist Not in IPX Cache
- **Symptom**: `hotfix_file_check` or `bump_pins_check_gen` fails; IP variant not found
- **Cause**: Specific IP release variant never released to IPX
- **General Fix**: Change to a released variant (e.g., `_Full_model` → `_reduced_2`)
- **Files to Check**: `filelists/*.soc.list`, `filelists/.soc.list.mako`
- **Related Bugs**: BUG-002

## Pattern 3: EDA Tool Path Not Found
- **Symptom**: VCS compilation fails; tool binary not found
- **Cause**: Mount point `/p/com/eda/` doesn't exist; tools at `/p/hdk/rtl/cad/x86-64_linux26/`
- **General Fix**: Run `scripts/fix_die_ctech_paths.csh`
- **Related Bugs**: (general — multiple bugs reference this)

## Pattern 4: Missing Module Instantiation (XMRE Errors)
- **Symptom**: VCS elaboration XMRE cross-module reference errors
- **Cause**: Module referenced but not instantiated in testbench
- **General Fix**: Add `<module_name> <module_name>();` to `src/val/emu/testbench/rtl/pkg_emu_tb.sv`

## Pattern 5: Disk Full During zDB_Global
- **Symptom**: `RDB0466E: basic_ios::clear: iostream error`
- **Cause**: NFS disk hits 100% during global database write
- **General Fix**: Free disk space, restart with `grdlbuild ... -id`

## Pattern 6: `vcs_splitter/` Deleted Before `zebu_tb`
- **Symptom**: `cp: cannot stat '../vcs_splitter/zemi3.h': No such file or directory`
- **Cause**: `vcs_splitter/` deleted for disk space before `zebu_tb`
- **General Fix**: Create stub `zemi3.h`, run `make -f dpixtor.mk install`, touch shadow
- **Related Bugs**: BUG-005

## Pattern 7: zDB_Global Log Appears Stuck
- **Symptom**: Log line count not increasing for 10+ minutes
- **Cause**: zDB runs on farm node with local scratch; NFS log flushed periodically
- **Diagnosis**: Check Controller log modify time — if recent, job is alive
- **Action**: WAIT. Do NOT restart.

## Pattern 8: Tests Fail — "No builds found to validate"
- **Symptom**: `emurun WARNING: Filtering out zse5/` + `No builds found to validate`
- **Cause**: `prepare_spark` and `spark_tb` never ran (zebu_tb was manually forced)
- **General Fix**: Re-run `grdlbuild :emu_build:zebu:pkg_ghpf_model_zse5 -Penv=immediate`
- **Related Bugs**: BUG-005

## Pattern 9: MuDb Missing / FpgaPostProc Skipped
- **Symptom**: `CORE0001E: Cannot read MuDb version` + `LUI1744E` + `ZHW0909E`
- **Cause**: FpgaPostProc skipped during fe_be (zPRD mode)
- **Diagnosis**: `grep "FpgaPostProc normal task termination: skipped" fe_be.log | wc -l`
- **General Fix**: Re-run fe_be: `rm .shadow/fe_be && grdlbuild ... -Penv=immediate`
- **Related Bugs**: BUG-007, BUG-008

## Pattern 10: `fuse_assembler/` Missing — pcd_ss_gen Fails
- **Symptom**: `bad interpreter` in softstrap/fuse assembler scripts
- **Cause**: Read-only PCD release symlinks with old Python shebangs
- **General Fix**: Replace symlinks with local copies, fix shebangs
- **Related Bugs**: BUG-010, BUG-019

## Pattern 11: Zebu FM — `zse_engine.so` Cannot Load Shared Libraries
- **Symptom**: `SimExc_General('Failed to load module...')` with missing `.so`
- **Cause**: gecco LD_LIBRARY_PATH points to wrong path; RPATHs need fixing
- **General Fix**: Create symlinks in `zse5/lib/` via `scripts/fix_zse5_libs.sh`; patch RPATH with `$ORIGIN`
- **Key insight**: `addEnv('LD_LIBRARY_PATH')` does NOT work in gecco FM env. Use RPATH/co-location.
- **Related Bugs**: BUG-011, BUG-014, BUG-024, BUG-026, BUG-028

## Pattern 12: Kerberos/SSH Authentication Failures
- **Symptom**: rsync "connection unexpectedly closed", SSH "Password change required"
- **Cause**: Kerberos ticket expired OR Intel/AD password expired
- **General Fix**: `kinit -R` for ticket renewal; change password if PAM blocks
- **Related Bugs**: BUG-033, BUG-034

## Pattern 13: GK Build Read-Only Permissions
- **Symptom**: "Permission denied" or "Read-only file system" when fixing libs
- **Cause**: `output/` symlinked to GK build owned by `sleadmin`, mode 750
- **General Fix**: `chmod -R g+w` on specific directories (requires GK owner or admin)
- **Related Bugs**: BUG-028

## Runtime & Test Execution Patterns (from ai_picker_sle Reference Methodologies)

### Pattern 14: SAGV/DVFS Memory Corruption
- **Phase:** TEST_EXECUTION
- **Symptoms:** memory corruption, sagv, dvfs, frequency transition, undefined_opcode, exception, address_misalignment, gear_shift, read_zero, data_mismatch
- **Description:** Memory corruption, address misalignment, or CPU exceptions occurring during System Agent Gear/Voltage (SAGV) or frequency transition events. The root cause is often DFI timing violations during gear shifts, not instruction bugs.
- **Detection:** CPU exception + DVFS/SAGV event within 50ms in `PyDoh.Sequence.log`
- **Key Logs:** `PyDoh.Sequence.log`, `DEBUG`, `uop_log*.log`, `cfi_trk.log`, LPDDR5 logs
- **Heuristic:** If `dvfsq` appears in `PyDoh.Sequence.log` near the failure timestamp → likely SAGV-related corruption, not a core issue
- **Related Bugs:** (none in bundle1106 yet — document if encountered)

### Pattern 15: Mailbox Timeout / Pcode Communication Failure
- **Phase:** TEST_EXECUTION
- **Symptoms:** mailbox, timeout, pcode, 0xdead, request, response, hang, communication, p24c, gt_driver
- **Description:** Test writes to a mailbox interface (e.g., GT P24C) but pCode firmware never sees or responds to the request. Often caused by writing to non-existent/misconfigured interface or wrong mailbox address.
- **Detection:** `0xdead` error code in test output or `pcode_jem_tracker.log`
- **Key Logs:** `pcode_jem_tracker.log`, `testbench.log`, `PyDoh.Agent.log`
- **Heuristic:** Check if the mailbox address is valid for the current DUT configuration. P24C mailbox issues often indicate a test targeting wrong interface.
- **Time to Root Cause:** 20-45 minutes

### Pattern 16: Boot FSM Hang (Security/Protocol)
- **Phase:** RUNTIME
- **Symptoms:** boot, hang, fsm, security, protocol, sb_link, secure, handshake, timeout
- **Description:** Boot FSM gets stuck at a security handshake or sideband link training state. The DUT cannot complete its boot sequence because a protocol handshake never completes.
- **Detection:** `bootfsm_state_tracker.log.gz` shows stuck at SECURE/LINK state; `iosf_sb_jem_tracker.log.gz` shows large time gap (>100K ps) between last transaction and current time.
- **Key Logs:** `bootfsm_state_tracker.log.gz`, `iosf_sb_jem_tracker.log.gz`, `*BFM.log`
- **Heuristic:** If BFM logs show "unsupported" messages → configuration mismatch between model and BFM. If no BFM warnings → check CFI/sideband for protocol deadlock.

### Pattern 17: TLM_POST SVA Assertion Failure (Multi-Stage Deception)
- **Phase:** POST_PROCESS
- **Symptoms:** TLM_POST, sva_post_proc, SVA_ASSERTION_ERROR, assertion, multi-stage
- **Description:** A deceptive pattern where emulation stage reports "Test PASSED" but post-processing (TLM_POST) detects SVA assertion violations, making the overall result FAILED. Engineers often waste hours confused because emurun.log says PASSED.
- **Detection:** `emurun.log` shows PASSED, `logbook.log` shows "Post processing" FAIL, `assertion_failures.log` or `zse_assertions.log` contain errors
- **Key Logs:** `logbook.log`, `assertion_failures.log`, `zse_assertions.log`, `emurun.log`
- **Heuristic:** ALWAYS check logbook stage table, not just emurun. Test execution stages: Build → Emulation → RPT → Post Processing → SVA Check. ALL must pass.

### Pattern 18: LPDDR5 Signal Alignment / DFI Timing
- **Phase:** TEST_EXECUTION
- **Symptoms:** lpddr5, ddr, memory, read, write, dfi, signal, alignment, timing, data_mismatch, calibration, training
- **Description:** Memory READ/WRITE operations fail intermittently (e.g., "every second READ") due to DFI signals being misaligned between data and valid/enable signals. Common root cause: `write_lat_adjust` or `read_lat_adjust` set incorrectly.
- **Detection:** Intermittent memory errors, especially periodic patterns (every 2nd or 4th access)
- **Key Logs:** LPDDR5 logs, `DEBUG`, `testbench.log`
- **Heuristic:** If memory failures show periodic pattern → suspect DFI latency adjustment. Check `write_lat_adjust` and `read_lat_adjust` register values.

### Pattern 19: Model Build Force Error
- **Phase:** BUILD
- **Symptoms:** force, error, build, fail, elaboration, hierarchical_path, type_mismatch, compilation, syntax, dpi
- **Description:** Model build fails due to issues with `force` statements in SystemVerilog. Force statements override signal values but improper usage causes build-time or elaboration errors (incorrect hierarchical path, type mismatch, forcing optimized-away signals).
- **Detection:** Build log contains "force.*signal.*error" or "force.*not.*found" or "hierarchical path" errors
- **Key Logs:** `build.log`, `emurun.log`, `compile.log`
- **Heuristic:** Check if the forced signal path exists in the elaborated design. Signals may be optimized away or renamed during synthesis.

### Pattern 20: Register Read Uninitialized
- **Phase:** TEST_EXECUTION
- **Symptoms:** register, read, uninitialized, random, replicate, assignment
- **Description:** Register reads return random/unexpected values because the register was never properly initialized in the emulation model. Often caused by `replicate()` vs `fill()` operator confusion in test code, or missing register initialization in boot sequence.
- **Detection:** SelfCheck failures with unexpected register values that change between runs (random seed dependent)
- **Key Logs:** `testbench.log`, `uop_log*.log`, register access logs
- **Heuristic:** If register value changes across runs with different seeds → likely uninitialized. Check boot sequence for missing register writes.

### Pattern 21: SelfCheck Counter / Interrupt Handler Mismatch
- **Phase:** TEST_EXECUTION
- **Symptoms:** selfcheck, interrupt, count, handler, vector, mismatch, registration, conflict
- **Description:** SelfCheck fails because interrupt count doesn't match expected value. Root cause: multiple interrupt handlers registered for the same vector, causing double-counting or missed interrupts.
- **Detection:** SelfCheck error message with "interrupt count" or "handler count" mismatch
- **Key Logs:** `uop_log*.log`, `testbench.log`, `DEBUG`
- **Heuristic:** Check for duplicate handler registration in test code. Look for multiple `register_handler(vector_N)` calls with the same vector number. Also check if PM_INIT and CREATE_SMI both register SMI handlers.
