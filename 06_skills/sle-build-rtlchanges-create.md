---
name: sle-build-rtlchanges-create
description: "Create new rtlchange files for SLE emulation builds. USE WHEN: need to modify an IP source file for emulation, need to add a new replacement file to the rtlchange system, need to trace which VCS library a file belongs to and set up PKG_IP_CHANGES.cfg for it, need to create a new rtlchange from scratch (replacement file + .ref + HSDs.toml + PKG_IP_CHANGES.cfg). Covers: rtlchange anatomy (replacement + .ref + HSDs.toml + config), VCS library identification via analyzed_libs, PKG_IP_CHANGES.cfg replace/remove/add directives, library pattern naming conventions, end-to-end workflow for creating a new rtlchange."
argument-hint: "Provide the WORKAREA path, the IP source file path that needs modification, and description of the change needed."
---

# Creating New rtlchanges for SLE Emulation Builds

## When to Use
- You need to modify an IP's source file for emulation but **cannot** edit the IP source directly (it's delivered via IP drop)
- A build error requires changing a file that lives inside an IP library (hub, cdie, pcd, etc.)
- You need to add a new file replacement to the existing rtlchange infrastructure
- You already have an existing rtlchange file and need to modify it further (the file is already a replacement — edit it directly)

## Background: rtlchange System Architecture

### What Is an rtlchange?

An rtlchange is a **file-level replacement** mechanism for emulation builds. Instead of patching an IP's source directly (which would be overwritten on the next IP drop), you provide:
1. A **replacement file** — your modified version of the IP source
2. A **`.ref` file** — a byte-for-byte copy of the original IP source at the time the replacement was authored
3. An entry in **`HSDs.toml`** — the manifest that tracks all rtlchanges and their justification
4. A **`PKG_IP_CHANGES.cfg`** directive — tells the build system to substitute the replacement for the original during VCS compilation

The build's `rtlchanges_precheck` phase validates that every `.ref` still matches the current IP source. If the IP source changes (new drop), the precheck fails, alerting you to re-examine and refresh the rtlchange. See the `sle-build-rtlchanges-refresh` skill for handling stale `.ref` files.

### Directory Structure

rtlchanges live under `$WORKAREA/src/val/emu/rtlchanges/` organized by IP, mirroring the IP's internal source path:

```
$WORKAREA/src/val/emu/rtlchanges/
├── cdie_816_n2p/                          # CDIE IP rtlchanges
│   ├── HSDs.toml                          # Manifest for all CDIE rtlchanges
│   ├── src/val/emu/testbench/rtl/
│   │   ├── cdie_emu_tb.sv                 # Replacement file
│   │   └── cdie_emu_tb.sv.ref             # Original snapshot
│   └── src/val/subsystems/.../
├── hubbx/                                 # HUB IP rtlchanges
│   ├── HSDs.toml
│   ├── src/val/emu/testbench/rtl/
│   │   ├── hub_emu_tb.sv                  # Replacement
│   │   ├── hub_emu_tb.sv.ref              # Original
│   │   ├── hub_emu_clock_connect.sv
│   │   ├── hub_emu_clock_connect.sv.ref
│   │   └── ...
│   └── subip/sip/.../                     # Deeper IP hierarchy also supported
├── pcd/                                   # PCD IP rtlchanges
│   ├── HSDs.toml
│   └── ...
└── soc/                                   # SOC-level rtlchanges
    └── ttlbx_n2p/
```

The **path within** the IP rtlchanges directory must mirror the IP's source path exactly. For example:
- IP source at: `$WORKAREA/soc/ttlbx_n2p/hubbx/src/val/emu/testbench/rtl/hub_emu_tb.sv`
- Replacement at: `$WORKAREA/src/val/emu/rtlchanges/hubbx/src/val/emu/testbench/rtl/hub_emu_tb.sv`
- Ref file at: `$WORKAREA/src/val/emu/rtlchanges/hubbx/src/val/emu/testbench/rtl/hub_emu_tb.sv.ref`

### How the Build System Uses rtlchanges

During VCS analysis, the build system reads `PKG_IP_CHANGES.cfg` and for each library:
- **`replace: file:`** — substitutes the listed replacement files for their originals in that library's compilation
- **`remove: file:`** — drops files entirely from the library's compilation
- **`add: file:`** — adds new files to the library
- **`prepend: vlog_opts:`** — adds compile options (e.g., `+incdir+`) before the library's files
- **`add: vlog_opts:`** — appends compile options

The `replace:` mechanism works by **filename matching** — VCS sees the replacement file instead of the original in the analyzed library. The replacement file's basename must match the original's basename exactly.

## Step-by-Step: Creating a New rtlchange

### Step 1: Identify which VCS library contains the target file

You need to know the **library name** to configure `PKG_IP_CHANGES.cfg`. The library names are visible in the `analyzed_libs/` output directory after a successful analysis phase.

```bash
OUTDIR=$WORKAREA/output/ttlbx_n2p/emu/<BUILD_DIR>/$MODEL/vcs

# Method A: grep for the filename inside analyzed_libs directory listings
# Each subdirectory under analyzed_libs/$MODEL/ is a VCS library name
# and contains a file listing or Makefile with the source files
grep -rl '<filename>.sv' $OUTDIR/analyzed_libs/ | head -5

# Method B: Find library directories matching an IP pattern
ls $OUTDIR/analyzed_libs/$MODEL/ | grep -i '<ip_name>'
```

**Example**: For `hub_emu_tb.sv` in the hub IP:
```bash
grep -rl 'hub_emu_tb' $OUTDIR/analyzed_libs/
# → .../analyzed_libs/pkg_.../hubbx__hubbx_hubbx_tls_tb_lib/...
```
The library name is `hubbx__hubbx_hubbx_tls_tb_lib`.

### Step 2: Check if a `replace:` section already exists for that library

Look in `$WORKAREA/verif/emu/rtl_cfg/PKG_IP_CHANGES.cfg`:

```bash
grep -n '<library_name_pattern>' $WORKAREA/verif/emu/rtl_cfg/PKG_IP_CHANGES.cfg
```

**If a section already exists** with `replace: file:` entries for that library, you just need to:
1. Add your new replacement file path to the existing `replace: file:` list
2. Create the replacement + .ref files (Steps 3-4)
3. Add the HSDs.toml entry (Step 5)

**If no section exists**, you need to create one (Step 6).

### Step 3: Create the .ref file (snapshot of current IP source)

```bash
# Identify the IP source location
IP_SOURCE=$WORKAREA/soc/ttlbx_n2p/<ip>/<internal_path>/file.sv

# Create the rtlchange directory structure (mirroring IP path)
mkdir -p $WORKAREA/src/val/emu/rtlchanges/<ip>/<internal_path>/

# Copy the current source as the .ref
cp $IP_SOURCE $WORKAREA/src/val/emu/rtlchanges/<ip>/<internal_path>/file.sv.ref
```

### Step 4: Create the replacement file

```bash
# Start from the current IP source
cp $IP_SOURCE $WORKAREA/src/val/emu/rtlchanges/<ip>/<internal_path>/file.sv

# Now edit the replacement file with your modifications
# (The .ref remains untouched — it's the pristine original)
```

**If the file already exists as an rtlchange** (replacement already present from prior work), skip Steps 3-4 and edit the existing replacement file directly.

### Step 5: Add an HSDs.toml entry

Edit `$WORKAREA/src/val/emu/rtlchanges/<ip>/HSDs.toml`:

```toml
["<internal_path>/file.sv"]
hsd = 0
description = "Brief description of why this rtlchange is needed"
```

The path is **relative to the IP's rtlchanges directory**. For example, for hub:
```toml
["src/val/emu/testbench/rtl/hub_emu_tb.sv"]
hsd = 0
description = "Disable D2D and CDIE BFM modeling as PKG contains real CDIE + Disable fast PyDoh in dielet"
```

Note: `hsd = 0` is acceptable for in-development changes. Production changes should reference an actual HSD tracking number.

### Step 6: Add PKG_IP_CHANGES.cfg entry (if needed)

If the library doesn't already have a section in `PKG_IP_CHANGES.cfg`, add one:

```yaml
    <library_pattern> :
        replace :
            file :
                - ${PKG_MODEL_ROOT}/src/val/emu/rtlchanges/<ip>/<internal_path>/file.sv
```

**Library pattern conventions**: The pattern in `PKG_IP_CHANGES.cfg` is a regex matched against library names. Common patterns:

| IP | Library Pattern Example | Notes |
|----|------------------------|-------|
| CDIE | `cdie.*__cdie_tls_tb_lib` | Testbench library |
| HUB | `hub.*__hubbx_hubbx_tls_tb_lib` | Testbench library |
| HUB | `hub.*__hub_sfcdisp_disp_rtl_lib` | Design sub-IP library |
| PCD | `pcd.*__pcd_pchlp_lib` | PCD sub-IP library |

**Variable references** used in paths:
- `${PKG_MODEL_ROOT}` — workspace root (= `$WORKAREA`)
- `${CDIE0_DUT}` — CDIE IP directory name (e.g., `cdie_816_n2p`)
- `${HUB_DUT}` — HUB IP directory name (e.g., `hubbx`)
- `${HUB_MODEL_ROOT}` — HUB IP root within soc tree
- `${EMU_MODEL_TARGET}` — Emulation model output directory

If the library already has a section with other directives (e.g., `add: vlog_opts:`), add the `replace: file:` block to the existing section — do NOT create a duplicate section for the same pattern.

You may also need `+incdir+` if your replacement `include`s files from the rtlchanges area:
```yaml
        prepend :
            vlog_opts :
                - +incdir+${PKG_MODEL_ROOT}/src/val/emu/rtlchanges/<ip>/<include_path>/
```

## PKG_IP_CHANGES.cfg Directive Reference

### `replace: file:` — Substitute a source file
```yaml
    <library_pattern> :
        replace :
            file :
                - ${PKG_MODEL_ROOT}/src/val/emu/rtlchanges/<ip>/path/to/file.sv
```
The build finds the original file with the same **basename** in the library's file list and substitutes it with the rtlchange version. The replacement file's basename must match exactly.

### `remove: file:` — Drop a file from compilation
```yaml
    <library_pattern> :
        remove :
            file :
                - ${HUB_MODEL_ROOT}/src/val/emu/testbench/rtl/unwanted_file.sv
```
Removes the file entirely from that library's compilation. Use when the file's module is not needed in emulation.

### `add: file:` — Add new files to a library
```yaml
    <library_pattern> :
        add :
            file :
                - -y ${EMU_MODEL_TARGET}/gen_stage/new_directory
```
Adds new file sources or directories to the library.

### Combined example (hub testbench library):
```yaml
    hub.*__hubbx_hubbx_tls_tb_lib :
        remove :
            file :
                - ${HUB_MODEL_ROOT}/src/val/emu/testbench/rtl/hub_emu_pydoh_xtors.sv
                - ${HUB_MODEL_ROOT}/src/val/emu/testbench/rtl/hub_emu_pydoh_forces.sv

        replace :
            file :
                - ${PKG_MODEL_ROOT}/src/val/emu/rtlchanges/${HUB_DUT}/src/val/emu/testbench/rtl/hub_emu_tb.sv
                - ${PKG_MODEL_ROOT}/src/val/emu/rtlchanges/${HUB_DUT}/src/val/emu/testbench/rtl/hub_emu_workarounds.sv

        prepend :
            vlog_opts :
                - +incdir+${PKG_MODEL_ROOT}/src/val/emu/testbench/rtl
```

## When the Target File Is Already an rtlchange

If the file you need to modify is **already** a replacement file in the rtlchange system (e.g., `hub_emu_tb.sv` already has a replacement + .ref + HSDs.toml entry + PKG_IP_CHANGES.cfg directive), then:
1. **Skip Steps 3-6** — the infrastructure is already in place
2. **Edit the existing replacement file directly** at `$WORKAREA/src/val/emu/rtlchanges/<ip>/.../<file>.sv`
3. Do **NOT** touch the `.ref` file — it stays as the original IP source snapshot
4. The HSDs.toml entry and PKG_IP_CHANGES.cfg directive are already present

This is common — many elab or runtime fixes involve further modifying an existing rtlchange rather than creating a brand new one.

## Verifying Before Building

After creating/modifying an rtlchange:

1. **Check .ref matches current source**:
   ```bash
   diff $WORKAREA/src/val/emu/rtlchanges/<ip>/path/file.sv.ref \
        $WORKAREA/soc/ttlbx_n2p/<ip>/path/file.sv
   ```
   If they differ, the `.ref` is stale — see `sle-build-rtlchanges-refresh` skill.

2. **Check HSDs.toml has the entry**:
   ```bash
   grep '<filename>' $WORKAREA/src/val/emu/rtlchanges/<ip>/HSDs.toml
   ```

3. **Check PKG_IP_CHANGES.cfg has the replace directive**:
   ```bash
   grep '<filename>' $WORKAREA/verif/emu/rtl_cfg/PKG_IP_CHANGES.cfg
   ```

4. **Check replacement file differs from .ref** (your change is actually present):
   ```bash
   diff $WORKAREA/src/val/emu/rtlchanges/<ip>/path/file.sv.ref \
        $WORKAREA/src/val/emu/rtlchanges/<ip>/path/file.sv
   ```

## Common Pitfalls

### Path must mirror exactly
The rtlchange path within `src/val/emu/rtlchanges/<ip>/` must mirror the IP's internal path structure. If the IP source is at `.../hubbx/src/val/emu/testbench/rtl/hub_emu_tb.sv`, the rtlchange must be at `.../rtlchanges/hubbx/src/val/emu/testbench/rtl/hub_emu_tb.sv`.

### Basename matching for replace
The `replace: file:` mechanism matches by **basename only**. If your replacement file has a different basename than the original, the replacement silently fails (original is still compiled).

### Duplicate library sections
Do NOT create two sections for the same library pattern in `PKG_IP_CHANGES.cfg`. If a section already exists, add your directives to it.

### .ref file must be pristine
The `.ref` file must be an exact copy of the current IP source — no modifications. The precheck compares it byte-for-byte. If you accidentally edit the `.ref`, the precheck will either pass incorrectly (hiding a real source change) or fail spuriously.

## Related Skills
- `sle-build-rtlchanges-refresh` — Refresh stale .ref files after IP drops, fix precheck failures
- `sle-build-fpga-elab-missing-cell-fix` — Guard testbench instantiations with `FPGA_EMU_BUILD` define (a common reason to create/modify rtlchanges)
- `sle-build-fpga-rtlchanges-postcheck-fix` — Fix postcheck failures for IPs not compiled in FPGA builds
