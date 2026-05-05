---
name: sle-build-pcd-bkc-integration
description: "Integrate a new PCD BKC release into the SLE emulation workspace. USE WHEN: new PCD BKC drop available, need to pull BKC from FM and apply SLE-specific changes, PCD model refresh for SLE build. Covers: rsync BKC from FM, SLE delta identification from reference area, three-way merge of SLE changes onto new BKC baseline, disk cleanup, symlink materialization."
argument-hint: "User must supply: 1) BKC release area path (on FM), 2) destination area path (local), 3) non-BKC reference area path (provides SLE change pattern via file + .ref pairs)."
---

# PCD BKC SLE Integration Skill

## When to Use
- A new PCD BKC release is available and needs to be integrated into the SLE emulation workspace
- PCD model needs refresh with latest BKC while preserving SLE-specific modifications

## Required User Inputs

1. **BKC release area** — path on FM containing the new PCD BKC drop
2. **Destination area** — local path where the BKC will be placed for integration
3. **Non-BKC reference area** — a workspace directory containing SLE-specific changes as `file` + `file.ref` pairs

## Critical Constraints

- **DO NOT modify the non-BKC reference area.** That area comes from the PCD model (not the BKC) and must remain untouched. All writes go to the BKC destination only.
- Files from FM arrive with restrictive permissions — always `chmod -R u+rwX` the relevant directories before attempting writes.

## Procedure

### Step 1: Copy BKC from FM to Local Destination

rsync the BKC release area from FM to the local destination, preserving the BKC release name as a subdirectory:

```bash
# Extract the BKC release name from the source path (last path component)
BKC_NAME=$(basename <BKC_RELEASE_AREA>)
rsync -avz fm-login.fm.intel.com:<BKC_RELEASE_AREA>/ <DESTINATION_AREA>/${BKC_NAME}/
```

- Use `fm-login.fm.intel.com` as the FM host
- The destination must include the BKC release name as a subdirectory (e.g., `TTLBX_BKC/emu_pcd-ttl-h-main-26ww13a-config-R_DFD-Rev3/`)
- This allows multiple BKC versions to coexist in the destination area
- Trailing slash on source ensures contents are copied (not the directory itself)
- Verify transfer completed without errors

### Step 2: Identify SLE Deltas from the Non-BKC Reference Area

The non-BKC reference area contains pairs of files:
- `<filename>` — the file WITH SLE-specific changes applied
- `<filename>.ref` — the ORIGINAL file before SLE changes (baseline reference)

For each file pair:
1. List all files in the reference area (excluding `.ref` files) to get the set of modified files
2. For each file, compute the SLE delta: `diff <filename>.ref <filename>`
3. Confirm the corresponding file exists in the BKC destination area

### Step 3: Apply SLE Deltas to the New BKC Files

Fix permissions first:
```bash
chmod -R u+rwX <DESTINATION_AREA>/${BKC_NAME}/pcd_run_dir_ovrd/run_files/
```

For each SLE-modified file, perform a three-way merge:

1. If the `.ref` file matches the new BKC file (no upstream changes): simply copy the SLE override directly onto the BKC file.
2. If the new BKC file differs from the `.ref` (upstream changed): use `diff3 -m` for three-way merge:
   - **Mine** = `<destination_area>/<filename>` (new BKC baseline)
   - **Older** = `<reference_area>/<filename>.ref` (old baseline)
   - **Yours** = `<reference_area>/<filename>` (old baseline + SLE changes)
   - **Result** → written to `<destination_area>/<filename>`
3. If conflicts arise, resolve them by keeping the SLE intent. For log-level conflicts (upstream and SLE both reduce verbosity), prefer the SLE value (typically 0).

Use awk to resolve conflicts programmatically if needed (keep "theirs" = SLE version):
```awk
/^<<<<<<</ { in_conflict=1; section="mine"; next }
/^\|\|\|\|\|\|\|/ { section="older"; next }
/^=======/ { section="theirs"; next }
/^>>>>>>>/ { in_conflict=0; section=""; next }
{ if (in_conflict) { if (section == "theirs") print } else { print } }
```

### Step 4: Delete `jem` Directories (Disk Savings)

The BKC `run/` directory contains `jem/` subdirectories that are large and not needed in the reference area:

```bash
find <DESTINATION_AREA>/${BKC_NAME}/run -type d -name "jem" -exec chmod -R u+rwX {} \; -exec rm -rf {} \;
```

This typically saves 4-5GB.

### Step 5: Materialize `me-region*` Symlinks

The BKC contains `me-region*` symlinks that point to versioned binary files. Convert these to real files so the BKC area is self-contained and doesn't depend on FM symlink targets:

```bash
find <DESTINATION_AREA>/${BKC_NAME} -type l -name "me-region*" | while read f; do
  target=$(readlink -f "$f")
  chmod u+w "$(dirname "$f")"
  rm "$f" && cp "$target" "$f"
done
```

## Future Enhancements

- **N-1 BKC copy**: An N-1 (previous) BKC area will be supplied. Some SLE-specific files should be copied from the N-1 BKC to the new BKC area. (Details TBD)

## Key Principles

- The non-BKC reference area is READ-ONLY during this procedure — it belongs to the PCD model
- The `.ref` file always represents the unmodified BKC baseline
- SLE changes are the diff between `.ref` and the modified file
- Each integration is a forward-port of SLE patches onto a new BKC baseline
- Conflicts require understanding of both the BKC changes and the SLE change intent
- Always fix FM file permissions before writing to the BKC destination
