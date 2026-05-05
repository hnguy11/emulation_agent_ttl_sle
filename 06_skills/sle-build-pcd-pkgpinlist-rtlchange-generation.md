---
name: sle-build-pcd-pkgpinlist-rtlchange-generation
description: "Generate RTL change files for PCD wrapper (ttlpcdhpkg.sv) integration. USE WHEN: PCD port list changed in new RTL drop, need to regenerate rtlchange for ttlpcdhpkg wrapper, fuzzy-matching ports between pcd.sv and wrapper, fixing case mismatches, ddi/dditc index remapping, SystemVerilog LRM validation. Covers: gen_ttlpcdhpkg_rtlchange.py usage, post-processing corrections, port matching methodology."
argument-hint: "Describe the task: new PCD drop integration, wrapper port mismatch, or rtlchange regeneration"
---

# PCD RTL Change Generation Skill

## When to Use
- New PCD RTL drop changes the `pcd.sv` module port list
- Need to regenerate `ttlpcdhpkg.sv` wrapper rtlchange for SLE build
- Port mismatches between wrapper and pcd.sv after RTL update
- Debugging generated rtlchange files (MPC errors, duplicate signals, missing commas)

## Tool Location
```
src/val/emu/scripts/sle_build_scripts/gen_ttlpcdhpkg_rtlchange.py
```

## Quick Usage

```bash
python3 src/val/emu/scripts/sle_build_scripts/gen_ttlpcdhpkg_rtlchange.py \
    --ttlpcdhpkg <output_rtlchange_path> \
    --pcd-sv <path_to_pcd.sv> \
    --ref <pristine_wrapper_path>
```

Arguments:
- `--ttlpcdhpkg`: Output file path (the generated rtlchange)
- `--pcd-sv`: Path to the PCD top-level module (`pcd.sv`) — the **definitive** port list
- `--ref`: Path to the pristine/original wrapper file (read-only input)

## What the Script Does (11 Steps)

| Step | Action | Purpose |
|------|--------|---------|
| 1 | Extract `pcd.sv` module ports | Get definitive port list |
| 2b | Fix case mismatches (e.g., `AIO200_GND` → `aio200_gnd`) | Prevent unnecessary commenting |
| 3 | Parse wrapper instance section | Find `pcd pcd(...)` connections |
| 5 | Identify unconnected pcd.sv ports | Ports in pcd.sv but not in wrapper |
| 6 | Fuzzy-match to commented-out ports (≥0.75 threshold) | Infer reconnections |
| 6b | Fuzzy-match to wrapper wire declarations | Additional reconnection attempts |
| 7 | Generate modified file with `//SLE Change` markers | Output the rtlchange |
| 8 | Post-process: ddi/dditc index remapping | Fix display→DDI index mapping |
| 8b | Remove known bad fuzzy matches (`PORTS_TO_REMOVE`) | Clean up false positives |
| 9 | Remove duplicate signal connections | Fix VCS compile errors |
| 9b-c | Fix trailing/missing commas | Fix SystemVerilog syntax |
| 10 | SystemVerilog LRM validation (8 checks) | Catch compile issues pre-build |
| 11 | Change report (original vs generated) | Show added/removed/changed ports |

## Key Design Decisions

### Why fuzzy matching?
PCD ports change names between RTL drops, but the underlying signal connections stay similar. The script uses `difflib.SequenceMatcher` with a 0.75 threshold to automatically reconnect renamed ports.

### Why post-processing corrections?
Fuzzy matching sometimes produces wrong results:
- **ddi/dditc index errors**: `disp0_trans0` should map to `ddi0`, not `ddi1`. The DDI_INDEX table corrects this.
- **Known bad matches**: Some ports fuzzy-match to completely wrong signals (e.g., `pcd_ipu` → `display_disp`). The `PORTS_TO_REMOVE` set catches these.
- **Duplicate signals**: Some wrapper ports connect to the same signal, causing VCS errors.

### DDI Index Mapping
```
disp0_trans0 → ddi0 / dditc0
disp1_trans0 → ddi1 / dditc1
disp1_trans1 → ddi2 / dditc2
disp1_trans2 → ddi3 / dditc3
```

## Validation Checks (Step 10)

The script performs 8 SystemVerilog LRM checks:
1. **Mixed port connections** (named + positional in same instance)
2. **Trailing comma before `);`**
3. **Unbalanced parentheses**
4. **Unbalanced begin/end**
5. **Duplicate port connections** (same port name twice)
6. **Duplicate signal connections** (same signal on two ports)
7. **Unclosed module/endmodule**
8. **Missing commas between port connections**

## Extending the Script

### Adding new known-bad ports
Edit `PORTS_TO_REMOVE` set (around line 325):
```python
PORTS_TO_REMOVE = {
    'yy_pcd_display_dditc0_pica_de_ddi_clk_up',
    # Add new bad fuzzy matches here
}
```

### Adjusting fuzzy threshold
Change the threshold at line ~155:
```python
if score < 0.75:  # lower = more aggressive matching
```

### Adding new DDI mappings
Edit `DDI_INDEX` dict (around line 300):
```python
DDI_INDEX = {
    'disp0_trans0': '0',
    'disp1_trans0': '1',
    # Add new display/transport mappings
}
```

See the [workflow guide](./references/workflow-guide.md) for end-to-end regeneration workflow.
