---
bug_id: BUG-039
title: "Model build force error due to incorrect hierarchical path"
date_discovered: 2026-04-29
status: informational
severity: blocker
stage: "model build / elaboration"
bundle: all
category: build-config
related_patterns: []
tags: [force, hierarchical_path, build, elaboration, type_mismatch, compilation, dpi, model_build]
phase: "BUILD"
symptoms: "force error build fail elaboration hierarchical_path type_mismatch compilation syntax dpi undefined unresolved"
keywords: "model_build simulation_setup verilog_force testbench_error hierarchical_path"
trackers: "compile.log, elaborate.log"
---

# BUG-039: Model Build Force Error — Incorrect Hierarchical Path

## Symptom

Build failure with force-related error messages during compilation or elaboration:

```
Error: Hierarchical name 'top.cpu.core.signal_name' not found
Error: Type mismatch in force statement
Error: Cannot force protected signal
```

Found in: `compile.log`, `elaborate.log`

## Triggered By

```bash
# Model build with force statements referencing non-existent or renamed signals
vcs -sverilog <testbench_with_forces>.sv
```

## Root Cause

Force statements in SystemVerilog testbench/DPI code reference hierarchical signal paths that are incorrect. Common causes:
- Signal was renamed or moved in RTL refactoring
- Hierarchical path has typo (double dot, missing hierarchy level)
- Signal was optimized away during synthesis/compilation
- Type mismatch between force value and target signal width
- Attempting to force protected/constant signals
- DPI-C force functions using invalid `svGetScopeFromName()` paths

## Fix / Solution

```bash
# Step 1: Locate the force statement causing the error
grep -r "force " --include="*.sv" --include="*.v" --include="*.c" .
grep -E "(Error|Fatal)" compile.log | grep -i force

# Step 2: Validate hierarchical path exists
# In simulation or using hierarchy dump:
# ucli% show scope -hier top.cpu.core

# Step 3: Verify signal width compatibility
# Use $bits() to check: $display("Signal width: %0d", $bits(top.u_module.signal_name));

# Step 4: Fix the path in the force statement
# Before: force top..signal_name = 1;         (double dot)
# After:  force top.u_module.signal_name = 1;  (correct path)

# Step 5: For missing forces causing FSM hangs, search for EMULATION guards
grep -n "ifndef EMULATION\|ifdef EMULATION" *forces*.sv
```

## Files Affected

- Force statement source files (`*forces*.sv`, `*bring_up*.sv`, DPI `.c` files)
- Build scripts / Makefiles (compilation order)

## Verification

```bash
# Rebuild and check for force errors
grep -E "(Error|Fatal)" compile.log | grep -i "force\|hierarchical\|path"
# Should return no results after fix
```

## Notes

- If build succeeds but simulation hangs, the issue may be a **missing** force, not a broken one — check for `ifndef EMULATION` guards disabling forces in emulation mode
- Use waveform hierarchy search (`fsdb_client.py search_signals`) to find correct signal paths
- When RTL changes, all force paths must be re-validated
- DPI force functions should check `svGetScopeFromName()` return for NULL before applying force
