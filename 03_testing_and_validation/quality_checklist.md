---
title: "Quality Checklist — Pre-Handoff Validation"
module: 03_testing_and_validation
tags: [quality, checklist, validation, handoff, doa]
---

# Quality Checklist — Pre-Handoff Validation

## Build Verification

- [ ] All 19 shadow files present: `ls .shadow/ | wc -l` = 19
- [ ] `fix_zse5_libs.sh` ran successfully (100+ symlinks, 352 RPATH patches)
- [ ] `ldd zse_engine.so | grep "not found"` returns empty
- [ ] `readmem.dump` is a regular file (not symlink) with absolute paths
- [ ] U0-U3 directories exist in `backend_default/`
- [ ] MuDb `equis/info` file is non-empty

## Test Verification

- [ ] `spacedoa_mobile`: PASSED
- [ ] `spacex_mobile`: PASSED
- [ ] Zero assertion failures in both tests
- [ ] `iosf_sb_jem_tracker` either passes or is in `not_fail_on` list
- [ ] `postmortem.log` shows `OVERALL STATUS: PASS` for both tests

## Documentation Verification

- [ ] All bugs encountered during this integration are documented in `known_bugs_and_fixes/`
- [ ] `commands_reference.md` is up-to-date with any new commands used
- [ ] `common_patterns.md` updated if new patterns discovered
- [ ] Build session log appended to `build_flow.md`

## Post-Fix Validation Protocol (Extracted from ai_picker_sle Reference)

### 1. Multi-Stage Result Verification

**CRITICAL:** A test passing emulation does NOT mean it passed overall. The test execution pipeline has multiple stages:

```
Test Build → Emulation (Model Run) → Creating RPT → Post Processing → SVA Check
ALL stages must show PASS in logbook.log stage table.
```

**Verification steps after any fix:**

```bash
# 1. Check overall result
cat results.log
# Must show: PASSED

# 2. Check ALL stages in logbook (not just emurun)
zgrep -A 10 "Stage.*Elapsed.*Status" logbook.log.gz | tail -6
# ALL stages must show: PASS

# 3. Check for hidden assertion failures
ls assertion_failures.log zse_assertions.log 2>/dev/null
# If files exist, check they are empty or contain no errors
grep -c "error\|fail" assertion_failures.log zse_assertions.log 2>/dev/null

# 4. Check emurun final status
grep -i "PASSED\|FAILED" emurun.log | tail -3
```

**Common trap:** emurun.log says "PASSED" (emulation completed) but TLM_POST or SVA post-processing detected assertion violations → overall FAILED. ALWAYS verify the logbook stage table.

### 2. DOA Test Re-Run Verification

After fixing a bug, re-run both DOA tests:

```bash
cd /nfs/site/disks/ive_sle_zsc11_tbaziza/models/integrate_bundle1106
simregress -dut nvlsi7_n2p -save -no_xs -trex -emu_model pkg_ghpf_model -emu_tech zse5 \
  -no_compress EMUL_QSLOT=/prj/sv/nvl/emu/interactive -trex- \
  -P zsc11_express -Q /IVE/NVL/emu \
  -l reglist/nvlsi7_n2p/emu/doa_pkg_ghpf_model_zse5.list
```

**Both tests must pass:**
- `spacedoa_mobile` — All 4 Atom cores boot + SpaceDOA workload completes + `EBX=0xaced`
- `spacex_mobile` — PCIe link training + SpaceX GPU MMIO test + `EBX=0xaced`

### 3. Methodology Creation Trigger

If you encountered a **novel failure** (not matching any existing pattern), you MUST create a new methodology/bug file:

**Trigger conditions:**
- No existing BUG file matches the failure
- No common pattern in `common_patterns.md` covers this case
- The fix required non-trivial investigation (>15 minutes)

**Creation steps:**
1. Create `BUG-NNN_description.md` in `05_knowledge_and_debugging/known_bugs_and_fixes/` using `bug_template.md`
2. If the pattern is generalizable, add a new entry to `common_patterns.md`
3. Include YAML frontmatter with: bug_id, title, date_discovered, status, severity, stage, bundle, category, tags
4. Include: Symptom, Root Cause, Applied Fix, Validation steps
5. Update `02_execution/commands_reference.md` if new commands were used

### 4. Documentation Gate

**A fix is NOT complete until it is documented.**

Before declaring any fix done, verify:
- [ ] Bug file created in `known_bugs_and_fixes/` (if novel)
- [ ] `common_patterns.md` updated (if pattern generalizable)
- [ ] `commands_reference.md` updated (if new commands discovered)
- [ ] Test re-run submitted and results verified
- [ ] Changes committed to git with descriptive message

> "Documentation is part of the fix, not an afterthought." — AI Guidelines Rule #1

### 5. Integration Loop Completion Criteria

The integration loop is complete ONLY when ALL of the following are true:

1. **Build:** All 19 shadow files present (compilation complete)
2. **Permissions:** `output/` directory readable and libraries accessible
3. **DOA Tests:** Both `spacedoa_mobile` and `spacex_mobile` show PASSED
4. **Stage Table:** ALL stages (Test build, Model run, Creating RPT, Post processing) show PASS
5. **Documentation:** All encountered bugs documented with fixes
6. **Knowledge Base:** New patterns added to common_patterns.md
7. **Git:** All changes committed and pushed to GitHub

Only after ALL 7 criteria are met should the agent report "Integration Loop Complete."
