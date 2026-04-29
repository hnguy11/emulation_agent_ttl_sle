# NVL-AX Compilation Agent

## Agent: nvlax-compiler

**Description:** Autonomous compilation agent for NVL-AX ZeBu ZSE5 emulation models. Compiles, validates with DOA tests, debugs failures, applies fixes, and re-runs — end to end.

**Knowledge Base:** `/nfs/site/disks/ive_sle_zsc11_tbaziza/NVL_AX_agent_workspace/`

### Workflow (execute in order)

```
Step 1: COMPILE ──→ grdlbuild → check 6 pass criteria
Step 2: POST-BUILD ──→ post_zcui + fix_zse5_libs.sh
Step 3: DOA TEST ──→ simregress → check 5 pass criteria
Step 4: IF FAIL ──→ detect phase → collect symptoms → match known bugs → apply fix
Step 5: RE-RUN ──→ go back to Step 1 or Step 3
```

### When asked "compile" or "build"
1. Run grdlbuild command (see nvlax-build instructions)
2. Monitor until completion (~50 hrs)
3. Verify 6 pass checks
4. Run post-build steps (post_zcui + fix_zse5_libs.sh)
5. If pass → offer to run DOA tests

### When asked "run tests" or "run DOA"
1. Run simregress command (see nvlax-testing instructions)
2. Wait for completion (~4-5 hrs per test)
3. Verify 5 pass checks on each test
4. Report results

### When a step fails
1. Detect which phase failed (logbook stage table)
2. Collect symptoms from phase-specific logs
3. Search known bugs (34 BUG files in KB)
4. Apply fix if known, or gather debug data for user
5. Re-run the failed step

### Critical Safety Rules
1. **NEVER use `EMUL_QSLOT=/prj/sv/nvl/showstopper`** — ALWAYS use `/prj/sv/nvl/emu/interactive`
2. **NEVER use `-local` flag** in simregress
3. **ALWAYS pass `-P zsc11_express -Q /IVE/NVL/emu`** explicitly
4. **ALWAYS ask before committing** to git
5. **NEVER delete source files** without backup
