---
applyTo: "**"
---

# Step 1: Compile the Model

## Command — Start Fresh Build

```bash
cd /nfs/site/disks/ive_sle_zsc11_tbaziza/models/integrate_bundle1106
grdlbuild :emu_build:zebu:pkg_ghpf_model_zse5 -Penv=immediate
```

## Command — Resume Build (skip completed stages)

```bash
grdlbuild :emu_build:zebu:pkg_ghpf_model_zse5 -id
```

Use `-id` ONLY when analyze/fe_be stages already completed. NEVER on first build.

## Build Stages (14 stages, ~50 hrs total)

prerequisite → spark_co → override_vcs_home → gen_dv_flist → c_compile → dw_gen → gen_analyze_make → zse_lint → pre_analyze → gen_elab_src → analyze (~45m) → fe_be (~25h) → zebu_tb → emu_gen

## How to Verify Compilation Passed — ALL 6 Must Pass

```bash
# 1. Shadow files = 19
[ $(ls .shadow/ | wc -l) -eq 19 ] && echo "CHECK-1: PASS" || echo "CHECK-1: FAIL"

# 2. U0-U3 backend directories exist
ls output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/zcui.work/backend_default/ | grep -c "^U[0-9]"

# 3. MuDb info non-empty
[ -s output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/zcui.work/backend_default/MuDb/equis/info ] && echo "CHECK-3: PASS" || echo "CHECK-3: FAIL"

# 4. No missing shared libraries
ldd output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/simics_workspace/linux64/lib/zse_engine.so 2>/dev/null | grep -c "not found"

# 5. readmem.dump is a regular file
[ -f output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/readmem.dump ] && echo "CHECK-5: PASS" || echo "CHECK-5: FAIL"

# 6. No failure_info.log in latest log dir
LATEST=$(ls -t output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/log/ | head -1)
[ ! -f "output/nvlsi7_n2p/emu/zebu_zebu/pkg_ghpf_model/zse5/log/$LATEST/failure_info.log" ] && echo "CHECK-6: PASS" || echo "CHECK-6: FAIL"
```

**Quick check:**
```bash
[ $(ls .shadow/ | wc -l) -eq 19 ] && echo "COMPILATION PASSED" || echo "COMPILATION INCOMPLETE"
```

## Step 2: Post-Build (MANDATORY after compilation passes)

```bash
grdlbuild :emu_build:zebu:pkg_ghpf_model_zse5_post_zcui  # post_zcui
bash scripts/fix_zse5_libs.sh                              # fix library symlinks — NEVER SKIP
```

## If Compilation Fails → Go to debug instructions
