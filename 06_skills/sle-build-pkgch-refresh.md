---
name: sle-build-pkgch-refresh
description: "Prepare a new SLE workarea for a pkg_ch IP refresh. USE WHEN: a new pkg_ch model release is available on zsc10, need to create a new clone of the base SLE workarea, extract cdie/hub/PCD versions from the new pkg_ch model, name the clone appropriately, and pull the new pkg_ch content into it."
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

## Step 2: Extract Version Tags from pkg_ch Model

Read `filelists/.soc.list.mako` from the new pkg_ch model on zsc10 to extract the cdie, hub, and PCD version tags.

```bash
# Access the file via zsc10-login
ssh zsc10-login.zsc10.intel.com "grep -E 'cdie|hub|pcd_cfgr' <PKG_CH_MODEL>/filelists/.soc.list.mako"
```

### Example output:
```
${CDIE0_DUT}, /p/ipx/ipcache2/rzlcn2x/cdie/cdie-rzlcn2x-a0-26ww17f/3/rzlcn2x.cdie, ${CDIE0_DUT},
${HUB_DUT},  /p/ipx/ipcache2/ttlbxh78/hub/hub-ttlh78-a0-26ww17e/4/ttlbxh78.hub, ${HUB_DUT},
pcd_cfgr,    /nfs/site/disks/zsc16_ttlpcd_00008/release/emu_pcd-ttl-h-main-26ww13a-config-R_DFD_refresh, pchlp, pcd.flow.cfg;
```

### Version extraction rules:

| IP | Find in path | Extract | Prefix | Result |
|----|-------------|---------|--------|--------|
| cdie | `26ww**17f**` in cdie path | `17f` | `c` | `c17f` |
| hub  | `26ww**17e**` in hub path  | `17e` | `h` | `h17e` |
| pcd  | `26ww**13a**` in pcd path  | `13a` | `p` | `p13a` |

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

## Summary Checklist

| Step | Action | Done? |
|------|--------|-------|
| 1 | Gather: base SLE path, pkg_ch path, working disk | |
| 2 | Read `.soc.list.mako` on zsc10 — extract cdie, hub, PCD versions | |
| 3 | Construct new workarea name (check for collisions) | |
| 4 | `git clone <base_SLE> <new_workarea>` | |
| 5 | `git pull <user>@zsc10-login:<pkg_ch_path>` from inside new workarea | |
