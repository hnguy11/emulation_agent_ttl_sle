---
name: sle-build-rtlchanges-refresh
description: "Diagnose and fix rtlchanges_precheck failures in VCS/ZSE emulation builds. USE WHEN: grdlbuild fails at rtlchanges_precheck stage, precheck returns exit code 256, .ref files are stale after IP drop update, HSDs.toml missing entries for new rtlchange files, porting rtlchanges from one workspace to another (e.g., RZL to TTL). Covers: precheck log parsing, HSDs.toml entry creation, .ref file refresh, mechanical emu transformation application (hierarchy rewrite, library prefix, monitor comment-out, clock guard insertion)."
argument-hint: "Provide the WORKAREA path (the .fpga_vcs_enablement or build workspace) and optionally the MODEL name. Specify which IPs failed (CDIE, HUB, PCD, SOC)."
---

# rtlchanges Precheck Refresh Skill

## When to Use
- `grdlbuild` build fails at the `rtlchanges_precheck` phase
- Precheck returns exit code 256 for one or more IPs (CDIE, HUB, PCD)
- You ported rtlchange files from another workspace (e.g., RZL → TTL) and they're stale
- A new PCD/CDIE/HUB RTL drop changed source files that have rtlchanges

## Background: How rtlchanges Work

Each rtlchange consists of 3 parts:
1. **`.ref` file** — snapshot of the original source at the time the patch was authored
2. **Replacement file** (no `.ref` suffix) — the modified version with emu fixes applied
3. **`HSDs.toml`** — manifest listing every rtlchange file with its HSD number and description

The precheck tool (`rtlchanges_pre_check.py`) validates:
- Every rtlchange file has a corresponding entry in `HSDs.toml`
- Every `.ref` file matches the current source in the soc tree (byte-for-byte)

## Key Files and Paths

### rtlchanges Directory Structure
```
$WORKAREA/src/val/emu/rtlchanges/
├── cdie_816_n2p/          # CDIE rtlchanges
│   ├── HSDs.toml          # Manifest
│   ├── src/val/emu/testbench/rtl/
│   │   ├── cdie_emu_tb.sv       # Replacement
│   │   └── cdie_emu_tb.sv.ref   # Original snapshot
│   └── subip/...
├── hubbx/                 # HUB rtlchanges
│   ├── HSDs.toml
│   └── ...
├── pcd/                   # PCD rtlchanges
│   ├── HSDs.toml
│   └── ...
└── soc/                   # SOC-level rtlchanges
    └── ttlbx_n2p/ (or rzlhx_n2p/)
```

### Precheck Log
```
$WORKAREA/output/$DUT/emu/$BUILD_DIR/$MODEL/vcs/log/rtlchanges_precheck.log
```

### Source Trees (what .ref files are compared against)
```
$WORKAREA/soc/$DUT/cdie_816_n2p/   # CDIE source
$WORKAREA/soc/$DUT/hubbx/          # HUB source
$WORKAREA/soc/$DUT/pcd/            # PCD source
```

## Diagnosis Procedure

### Step 1: Read the precheck log
```bash
cat $WORKAREA/output/$DUT/emu/$BUILD_DIR/$MODEL/vcs/log/rtlchanges_precheck.log
```

### Step 2: Identify the three failure types

**Type A — Missing HSDs.toml entry:**
```
ERROR: No entry found in HSDs.toml for file <filename> in directory <dir>
```
Fix: Add an entry to HSDs.toml (see Step 3).

**Type B — Stale .ref file (source mismatch):**
```
ERROR: Reference file does NOT match source file. Please review.
```
Fix: Refresh the .ref and replacement files (see Step 4).

**Type C — Missing .ref file entirely:**
```
ERROR: Reference file /path/to/file.sv.ref does NOT exist. Please create one.
```
Fix: Copy the current source to the `.ref` path. This commonly happens when:
- New rtlchanges were ported from another workspace (e.g., RZL→TTL) and only the replacement file was copied, not the `.ref`
- The `.ref` was created at a wrong path (see "Critical: .ref path must mirror source path" in Pitfalls)

### Step 3: Fix missing HSDs.toml entries

The TOML format for each entry:
```toml
["relative/path/to/file.sv"]
hsd = 0
description = "Brief description of the rtlchange purpose"
```

The path is relative to the IP's rtlchanges directory. For example, for CDIE:
```toml
["src/val/emu/testbench/rtl/cdie_emu_clocks.sv"]
hsd = 0
description = "FPGA clock patching for PKG FPGA VCS target"
```

Insert new entries in the appropriate position within the HSDs.toml file.

### Step 4: Refresh stale .ref files

#### Step 4a: Understand the patch intent
Before refreshing, extract the diff between the old .ref and old replacement to understand what transformation was applied:
```bash
diff -u path/to/file.sv.ref path/to/file.sv
```

#### Step 4b: Categorize the transformation type
Common emu transformation patterns for PKG builds:

| Category | Pattern | Example |
|----------|---------|---------|
| **Comment-out** | Lines referencing non-existent BFM hierarchy | `$monitor(FC_TOP_TB_NAME.pcd_d2d_tb.*)` → `//SLE Addition $monitor(...)` |
| **Hierarchy rewrite** | PCD standalone `pcd_tb.pcd.` → PKG `tb_top.pkg.pcdpkg.pcd.` | `pcd_tb.pcd.paricc.` → `tb_top.pkg.pcdpkg.pcd.paricc.` |
| **Library prefix** | Namespace libs with `pcd__` to avoid conflicts | `liblist pchlp_lib` → `liblist pcd__pchlp_lib` |
| **Instance path prefix** | Instance in PKG hierarchy | `instance pcd.parX.` → `instance tb_top.pkg.pcdpkg.pcd.parX.` |
| **Clock guard** | Prevent double fast_clk definition | Wrap clock generation in `ifdef SLE_ADDITION_DO_NOT_CREATE_TWO_FAST_CLKS` |
| **Signal reroute** | Remap signals for PKG context | `ccosim_ctrl = TB_TOP.ccosim_ctrl` → `ccosim_ctrl = TB_TOP.fast_clk` |

#### Step 4c: Apply the refresh

**For all files:**
1. Copy current TTL source to `.ref`:
   ```bash
   cp $WORKAREA/soc/$DUT/pcd/<path>/file.sv  $WORKAREA/src/val/emu/rtlchanges/pcd/<path>/file.sv.ref
   ```
2. Copy current TTL source to replacement:
   ```bash
   cp $WORKAREA/soc/$DUT/pcd/<path>/file.sv  $WORKAREA/src/val/emu/rtlchanges/pcd/<path>/file.sv
   ```
3. Apply the mechanical transformation to the replacement only.

**Sed commands for common transformations:**

Comment-out D2D monitor lines:
```bash
sed -i 's/^\(\$monitor(`FC_TOP_TB_NAME\.pcd_d2d_tb\)/\/\/SLE Addition \1/' $FILE
sed -i 's/^\(\$monitor(`PCD_FC_TOP_TB_NAME\.pcd_d2d_tb\)/\/\/SLE Addition \1/' $FILE
```

Hierarchy path rewrite:
```bash
sed -i 's/pcd_tb\.pcd\./tb_top.pkg.pcdpkg.pcd./g' $FILE
```

Library name prefix (perl for word-boundary matching):
```bash
perl -pi -e 's/\b(\w+_lib)\b/pcd__$1/g if /liblist/' $FILE
```

Instance path prefix:
```bash
sed -i 's/^instance pcd\./instance tb_top.pkg.pcdpkg.pcd./' $FILE
```

Clock guard insertion (pcd_clocking.sv):
```bash
# Insert ifdef before `ifdef SOC_SOUTH_MODEL
sed -i '/^`ifdef SOC_SOUTH_MODEL/i\
// SLE Addition: Do not create two fast clocks\
`ifdef SLE_ADDITION_DO_NOT_CREATE_TWO_FAST_CLKS\
  // This is to avoid multiple definition of fast_clk signal\
  // when this file is included in higher level DUTs\
  // In that case, fast_clk is defined in the higher level DUT tb_top\
' $FILE

# Close the ifdef after `endif // SOC_SOUTH_MODEL
sed -i '/^`endif \/\/ SOC_SOUTH_MODEL/{n;s/^$/`endif \/\/ SLE_ADDITION_DO_NOT_CREATE_TWO_FAST_CLKS/}' $FILE

# Reroute ccosim_ctrl
sed -i 's/assign ccosim_ctrl = `TB_TOP\.ccosim_ctrl;/assign ccosim_ctrl = `TB_TOP.fast_clk;/' $FILE
```

## Verification

After applying fixes, verify with:

### Check .ref matches source
```bash
diff $WORKAREA/soc/$DUT/pcd/<path>/file.sv  $WORKAREA/src/val/emu/rtlchanges/pcd/<path>/file.sv.ref
# Should produce NO output (files identical)
```

### Check replacement has transformations
```bash
diff -u $WORKAREA/src/val/emu/rtlchanges/pcd/<path>/file.sv.ref  $WORKAREA/src/val/emu/rtlchanges/pcd/<path>/file.sv
# Should show only the intended emu transformations
```

### Check no untransformed references remain
```bash
grep -rn "pcd_tb\.pcd\." $WORKAREA/src/val/emu/rtlchanges/pcd/<path>/file.sv
# Should be empty for hierarchy-rewritten files
```

### Check all liblist entries are prefixed
```bash
grep "liblist [^p]" $FILE | grep -v "pcd__"
# Should be empty for library-prefixed files
```

## Common Pitfalls

1. **Don't edit .ref files** — they must be byte-identical copies of the soc source. Only edit the replacement files.

2. **Critical: .ref path must mirror the source file's path relative to the workarea.** The precheck tool constructs the expected `.ref` path from: `$RTLCHANGES_DIR/<path-of-source-relative-to-IP-workarea>.ref`. If you place the `.ref` at a different path, the precheck will report "does NOT exist" even though the file physically exists elsewhere.
   - **Example**: Source is at `soc/ttlbx_n2p/cdie_816_n2p/subip/hip/cdie_n2p_dlvr/subip/hip/ddgn2_dlvr2p00agslvrcbb/src/rtl/dlvr2p00agslvrcbb_emu.sv`
   - **Correct .ref**: `rtlchanges/cdie_816_n2p/subip/hip/cdie_n2p_dlvr/subip/hip/ddgn2_dlvr2p00agslvrcbb/src/rtl/dlvr2p00agslvrcbb_emu.sv.ref`
   - **Wrong .ref**: `rtlchanges/cdie_816_n2p/subip/hip/cdie_n2p_core/core/dlvr/rtl/cbb/dlvr2p00agslvrcbb_emu.sv.ref` (path from old RZL IP structure)
   - **How to get the correct path**: Read the precheck log — it prints the exact `Comparing source file ... to reference file ...` showing both paths.

3. **When porting rtlchanges from another workspace (e.g., RZL→TTL):** IP directory structures may have changed between projects. The replacement file path in the rtlchanges dir must match the *target* workspace's source tree, not the *source* workspace's. Always verify by reading the precheck log for the expected path.

4. **g5s3_cfg.sv may not need transforms** — if TTL restructured the file to use `include` directives instead of inline `instance`/`cell` lines, the library prefix transform won't match and that's expected.

3. **pchlp.pcd_cfg.sv needs structural additions** — beyond library prefixing, it also needs:
   - `design pchlp_lib.` → `design pcd__pchlp_lib.`
   - Add `ifdef EMULATION` / `include "pcd_default_emu_lib_list.sv"` block
   - Add `include "sle_v2k_cfg.sv"` before `include "mem_config_binding.sv"`

4. **Commented-out lines in source** — the perl `liblist` regex will also prefix libraries in commented-out lines. This is correct (matches the RZL behavior).

5. **pch_config_binding.sv is very large** (~1000 instance lines) — the transforms are purely mechanical but produce large diffs. This is expected.

6. **HSDs.toml entry paths** — paths are relative to the IP rtlchanges directory, NOT the workarea root. For CDIE rtlchanges, paths start from cdie_816_n2p's internal structure (e.g., `src/val/emu/testbench/rtl/filename.sv`).

7. **After fixing .ref files, verify before rebuilding** — Use this pattern to confirm all .ref files match their sources:
   ```bash
   diff $WORKAREA/soc/$DUT/$IP/<path>/file.sv $WORKAREA/src/val/emu/rtlchanges/$IP/<path>/file.sv.ref
   ```
   Should produce NO output. A quick verification script checking all failing files prevents wasted rebuild cycles.

8. **Stale precheck log can cause false diagnosis** — If you fix .ref files while a build is running (or between the precheck run and your diagnosis), the log may report errors for files that are already fixed. Always check the log's timestamp vs your fix timestamp before acting on errors.

9. **tcsh shell limitations** — When writing fix scripts, bash heredocs and `for` loops with complex quoting don't work in tcsh. Write a bash script to a file first, then run with `bash script.sh`, then `rm` the temp file.
