---
applyTo: "**"
---

# Step 3: Run DOA Tests

Run DOA tests ONLY after compilation passes and post-build completes.

## Command — Submit DOA Tests

```bash
cd /nfs/site/disks/ive_sle_zsc11_tbaziza/models/integrate_bundle1106
simregress -dut nvlsi7_n2p -save -no_xs -trex -emu_model pkg_ghpf_model -emu_tech zse5 \
  -no_compress EMUL_QSLOT=/prj/sv/nvl/emu/interactive -trex- \
  -P zsc11_express -Q /IVE/NVL/emu \
  -l reglist/nvlsi7_n2p/emu/doa_pkg_ghpf_model_zse5.list
```

## CRITICAL — NEVER CHANGE THESE

- **EMUL_QSLOT** MUST be `/prj/sv/nvl/emu/interactive` — NEVER `/prj/sv/nvl/showstopper` (production queue — will block other teams)
- **-local** flag is FORBIDDEN (BUG-001 — causes silent failures)
- **-P zsc11_express -Q /IVE/NVL/emu** MUST be passed explicitly (BUG-003)

## How to Verify a Test Passed — ALL 5 Must Pass

```bash
cd <test_workarea>

# 1. Overall result
grep -q "PASSED" results.log && echo "CHECK-1: PASS" || echo "CHECK-1: FAIL"

# 2. ALL logbook stages must be PASS (most important check)
zgrep -A 10 "Stage.*Elapsed.*Status" logbook.log.gz | tail -6
# Expected:
#  Stage                   Elapsed  Errors Warnings Status
# Test build              00:30:22   0       0     PASS
# Model run               48:42:13   0       1     PASS
# Creating RPT            00:26:55   0       0     PASS
# Post processing         00:00:04   0       0     PASS

# 3. emurun result
grep -i "PASSED\|FAILED" emurun.log | tail -3

# 4. No assertion failures
[ ! -s assertion_failures.log ] && echo "CHECK-4: PASS" || echo "CHECK-4: FAIL"

# 5. Core pass marker (spacedoa)
zgrep -q "EBX=0xaced" logbook.log.gz && echo "CHECK-5: PASS" || echo "CHECK-5: FAIL"
```

## WARNING: emurun PASS != overall PASS
Post-processing (SVA/TLM_POST) can fail AFTER emulation passes. ALWAYS check the logbook stage table — ALL 4 stages must show PASS.

## Available DOA Tests
- **spacedoa_mobile**: All 4 Atom cores boot + SpaceDOA workload + `EBX=0xaced` (~4-5 hrs)
- **spacex_mobile**: PCIe link training + GPU MMIO test + `EBX=0xaced` (~5 hrs)

## If Test Fails → Go to debug instructions
