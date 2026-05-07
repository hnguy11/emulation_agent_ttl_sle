---
name: sle-build-pkgch-refresh
description: "Prepare a new SLE workarea for a pkg_ch IP refresh. USE WHEN: a new pkg_ch model release is available on zsc10, need to create a new clone of the base SLE workarea, extract cdie/hub versions from the new pkg_ch model on zsc10 and PCD version from the base SLE model, name the clone appropriately, and pull the new pkg_ch content into it."
argument-hint: "Provide: (1) path to base SLE model, (2) path to new pkg_ch model on zsc10, (3) working disk path for the new workarea."
---

# pkg_ch Refresh — New SLE Workarea Setup

## Overview

This skill prepares a new SLE workarea when a new `pkg_ch` IP release is available.
The flow has two main phases:

1. **Gather inputs** — base SLE model, new pkg_ch model path (zsc10), working disk
2. **Clone + pull** — git clone the base SLE model with a version-derived name, then pull from the new pkg_ch model

> ⚠️ The new pkg_ch model lives on the **zsc10** compute zone. Access it via `zsc10-login.zsc10.intel.com`.
> The base SLE model and new workarea live on the **local** compute zone disk.

---

## Step 1: Gather Inputs

Ask the user for all three inputs before proceeding:

| Input | Example |
|-------|---------|
| Base SLE model path | `/nfs/site/disks/issp_ttl_emu_compile_001/pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1` |
| New pkg_ch model path (on zsc10) | `/p/cth/rtl/models/ddgcth/ttl/pkg_emu/pkg-ttlpkg-a0-ttlbxpkg-cdie_ww17f_hub_ww17e` |
| Working disk for new workarea | `/nfs/site/disks/issp_ttl_emu_compile_001` |

---

## Step 2: Extract Version Tags

Version tags come from **two different sources**:

| IP | Source | How to access |
|----|--------|--------------|
| cdie | `filelists/.soc.list.mako` in the **new pkg_ch model** (on zsc10) | SSH to zsc10-login |
| hub  | `filelists/.soc.list.mako` in the **new pkg_ch model** (on zsc10) | SSH to zsc10-login |
| pcd  | `filelists/.soc.list.mako` in the **base SLE model** (local) | Read locally |

> ⚠️ **PCD version is NOT available in the new pkg_ch model.** Always read it from the base SLE model.

### 2a: Extract cdie and hub versions from the new pkg_ch model (zsc10)

```bash
# Access the file via zsc10-login
ssh zsc10-login.zsc10.intel.com "grep -E 'cdie|hub' <PKG_CH_MODEL>/filelists/.soc.list.mako"
```

### Example output:
```
${CDIE0_DUT}, /p/ipx/ipcache2/rzlcn2x/cdie/cdie-rzlcn2x-a0-26ww17f/3/rzlcn2x.cdie, ${CDIE0_DUT},
${HUB_DUT},  /p/ipx/ipcache2/ttlbxh78/hub/hub-ttlh78-a0-26ww17e/4/ttlbxh78.hub, ${HUB_DUT},
```

### 2b: Extract PCD version from the base SLE model (local)

```bash
grep 'pcd_cfgr' <BASE_SLE_MODEL>/filelists/.soc.list.mako
```

### Example output:
```
pcd_cfgr,    /nfs/site/disks/zsc16_ttlpcd_00008/release/emu_pcd-ttl-h-main-26ww13a-config-R_DFD_refresh, pchlp, pcd.flow.cfg;
```

### Version extraction rules:

| IP | Source | Find in path | Extract | Prefix | Result |
|----|--------|-------------|---------|--------|--------|
| cdie | new pkg_ch (zsc10) | `26ww**17f**` in cdie path | `17f` | `c` | `c17f` |
| hub  | new pkg_ch (zsc10) | `26ww**17e**` in hub path  | `17e` | `h` | `h17e` |
| pcd  | base SLE (local)   | `26ww**13a**` in pcd path  | `13a` | `p` | `p13a` |

The version token is the `ww`-suffixed portion of the `26wwXXX` workweek string (e.g., `26ww17f` → `17f`).

---

## Step 3: Construct the New Workarea Name

Use the base SLE model name as a template, replacing the `cXXX_hXXX_pXXX` portion with the newly extracted tags.

**Pattern**: `<prefix>-c<cdie>_h<hub>_p<pcd>`

**Example**:
- Base: `pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1`
- Prefix (strip version + suffix): `pkg-ttlpkg-a0-ttlbxpkg`
- New version string: `c17f_h17e_p13a`
- New name: `pkg-ttlpkg-a0-ttlbxpkg-c17f_h17e_p13a`

### Collision check

If a directory with that name already exists on the working disk, append an incrementing suffix:

```bash
NEW_NAME="pkg-ttlpkg-a0-ttlbxpkg-c17f_h17e_p13a"
WORKING_DISK="/nfs/site/disks/issp_ttl_emu_compile_001"
TARGET="${WORKING_DISK}/${NEW_NAME}"

if [ -d "$TARGET" ]; then
    i=2
    while [ -d "${TARGET}.${i}" ]; do
        i=$((i+1))
    done
    TARGET="${TARGET}.${i}"
fi
echo "New workarea: $TARGET"
```

---

## Step 4: Git Clone the Base SLE Model

```bash
BASE_SLE="/nfs/site/disks/issp_ttl_emu_compile_001/pkg-ttlpkg-a0-ttlbxpkg-c15a_h15b_p13a.1"
git clone $BASE_SLE $TARGET
```

> This creates a full git clone of the base SLE model at the new path. The clone retains the full git history and remote configuration of the base model.

---

## Step 5: Pull from the New pkg_ch Model (on zsc10)

```bash
cd $TARGET
git pull <USER>@zsc10-login.zsc10.intel.com:<PKG_CH_MODEL_PATH>
```

**Example**:
```bash
cd /nfs/site/disks/issp_ttl_emu_compile_001/pkg-ttlpkg-a0-ttlbxpkg-c17f_h17e_p13a
git pull hnguy11@zsc10-login.zsc10.intel.com:/p/cth/rtl/models/ddgcth/ttl/pkg_emu/pkg-ttlpkg-a0-ttlbxpkg-cdie_ww17f_hub_ww17e
```

> **Note**: This pull brings in the new cdie/hub/PCD version pointers and any updated RTL integration files from the new pkg_ch release into the cloned SLE workarea.

---

## Step 6: Resolve Merge Conflicts

The `git pull` will often produce merge conflicts where the new pkg_ch content overlaps with SLE-specific modifications in the base clone. Work through them as follows.

### 6a: Check for conflicts

```bash
git status | grep "both modified\|both added\|unmerged"
# Or list all conflicted files:
git diff --name-only --diff-filter=U
```

### 6b: Identify SLE-specific content in each conflicted file

SLE-specific changes are marked with one of these comment patterns:

| Marker | Used in |
|--------|---------|
| `// SLE Change` | SV, C, Tcl, and other comment-supporting files |
| `// SLE Addition` | Same |
| `## SLE Change` | Makefile, Python, shell, YAML, and markdown files |
| `## SLE Addition` | Same |

> ⚠️ **Not all SLE changes will have markers** — some file formats do not support comments (e.g., JSON, CSV, `.mako` templates, binary-adjacent config files). For those, use git blame on the base SLE model or compare with the pkg_ch side to infer which content is SLE-specific.

### 6c: Resolution strategy per conflict

For each conflicted file:

```
<<<<<<< HEAD          ← this is the SLE side (base clone)
... content ...
=======
... content ...
>>>>>>> <pkg_ch_ref>  ← this is the new pkg_ch side
```

**Rule**: Keep the pkg_ch version as the base, then re-apply any SLE-marked content on top.

| Conflict type | Resolution |
|---------------|------------|
| SLE marker present in HEAD block | Keep pkg_ch side; append/insert the `// SLE` or `## SLE` marked block back in |
| No SLE marker in HEAD block, but lines differ | Prefer pkg_ch side (it's the upstream); alert user if content looks non-trivial |
| New file added by both sides | Keep both; merge content with SLE additions clearly preserved |
| SLE-added block not present in pkg_ch side at all | Restore the entire SLE block — pkg_ch simply doesn't have it |

### 6d: Resolve and stage each file

After manually resolving each file:
```bash
git add <resolved_file>
```

### 6e: Scan for unmarked SLE content (files without comment support)

For file types that can't carry comments (e.g., `.json`, `.mako`, `.csv`, config files), check whether the SLE side has any content the pkg_ch side lacks:

```bash
# View all remaining conflict markers (should be zero when done)
grep -rl "<<<<<<< HEAD" $TARGET/

# For a specific file, diff SLE vs pkg_ch content manually:
git show HEAD:<file>       # SLE version
git show MERGE_HEAD:<file> # pkg_ch version
```

Present these to the user for confirmation before resolving — do not silently discard SLE-side content in comment-free files.

### 6f: Complete the merge

Once all conflicts are resolved and staged:
```bash
git commit -m "Merge pkg_ch refresh: c<cdie>_h<hub>_p<pcd>"
```

**Example**:
```bash
git commit -m "Merge pkg_ch refresh: c17f_h17e_p13a"
```

---

## Step 7: Sync Missing IPs

After the merge commit is complete, run the IP sync script from inside the new workarea. This pulls over any IP packages referenced by the new model that are not yet present locally.

> ⚠️ **CRITICAL**: `$WORKAREA` **must** be explicitly set to the new workarea path before running the script. The script uses `$WORKAREA` to locate `filelists/.soc.list.mako`. If `$WORKAREA` is unset or points to the old workarea, the script will silently read the old IP paths, report them as "IP exists", and return without syncing the new IPs.

```bash
export WORKAREA=$TARGET
cd $TARGET
python scripts/sync_ips_zsc16.py
```

> This script fetches any missing IPs needed by the refreshed model. It must be run **after** the merge commit so the updated `filelists/.soc.list.mako` (with new cdie/hub pointers) is in place.

Wait for the script to complete before proceeding to build.

---

## Summary Checklist

| Step | Action | Done? |
|------|--------|-------|
| 1 | Gather: base SLE path, pkg_ch path, working disk | |
| 2 | Read `.soc.list.mako` on zsc10 (cdie, hub) and in base SLE model (PCD) — extract version tags | |
| 3 | Construct new workarea name (check for collisions) | |
| 4 | `git clone <base_SLE> <new_workarea>` | |
| 5 | `git pull <user>@zsc10-login:<pkg_ch_path>` from inside new workarea | |
| 6 | Resolve merge conflicts (preserve SLE markers; confirm unmarked files with user) | |
| 7 | `export WORKAREA=$TARGET && python scripts/sync_ips_zsc16.py` — sync missing IPs (WORKAREA must point to new workarea) | |
