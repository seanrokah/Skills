---
name: memory-forensics
description: Use when asked to analyze a memory image/dump, run Volatility, or investigate a memory file (.raw/.mem/.vmem/.lime/.dmp). Locates Volatility 3, auto-detects the image OS, runs a phased plugin workflow, and produces a comprehensive IR report. Supports automatic and semi-auto modes.
---

# Memory Forensics (Volatility 3)

## When to use
The user wants to analyze a memory image / "run Volatility" / investigate a `.raw`, `.mem`,
`.vmem`, `.lime`, `.dmp`, or `.bin` memory file.

## First: pick a mode (ask if unspecified)
- **Automatic** — run end-to-end; Claude chooses vol path, OS plugin set, and heavy steps.
  Pause only on hard errors / missing symbols.
- **Semi-auto** — present a plan, get the user's OK, then run phase-by-phase and STOP for
  guidance at the triggers below.

## Step 1 — Locate Volatility (record the exact invocation)
Resolve in order, first success wins:
1. Path the user provided.
2. `./vol.exe`, `./vol.py`, `./volatility3` in cwd or the image's directory.
3. On PATH: `vol`, `vol.exe`, `vol.py`, `volatility3`.
4. `python -m volatility3` (try `python`, `py`, `python3`).
Verify with the version banner. If a local `symbols/` dir exists, pass it with `-s`.
If nothing resolves, STOP and ask the user for the path.

## Step 2 — Detect the image OS
1. Run `windows.info`. If it returns kernel info → Windows; use `references/plugins-windows.md`.
2. If it errors, run `banners.Banners` to read the kernel banner → Linux or macOS + version;
   use `references/plugins-linux.md` or `references/plugins-macos.md`.
3. Linux/macOS need matching ISF symbols. If absent, STOP and tell the user which banner/symbol
   pack is required.
Record detected OS + profile for the report.

## Step 3 — Set up the case folder
Default: `<image_dir>/vol_analysis_<UTCstamp>/` with `artifacts/`, `dumps/`, `report/`.
All outputs are UTF-8.

## Step 4 — Run the phased workflow
Use the per-OS reference. Phases are tagged `[core]`, `[heavy]`, `[dump]`.
Collect with the helper: `scripts/run_vol.ps1` (Windows host) or `scripts/run_vol.sh` (Linux/macOS host).
The helper splits a plugin's extra args on spaces, so an extra arg whose VALUE contains spaces
(e.g. a registry key with a space) won't pass through intact — run those plugins directly instead
of via the helper.

Phase order: 1) Image context  2) Process triage  3) Network  4) Injection/rootkit
5) Persistence  6) Credentials  7) Execution/console  8) [heavy] bulk  9) [dump] carving.

- **Automatic:** run all `[core]` phases + sensible `[heavy]`; carve (`[dump]`) only when a clear
  malicious artifact warrants it. Then write the report.
- **Semi-auto:** present the plan, wait for OK, run phase-by-phase, and STOP + summarize + wait when:
  (a) a phase completes, (b) about to run a `[heavy]`/`[dump]` step, (c) a suspicious IOC appears
  (external/odd-port C2, injected code, suspicious process tree/path, autostart persistence,
  credential dump), (d) a plugin errors or symbols fail. Resume on the user's "ok"/guidance.

## Step 5 — Carving (gated, [dump])
Only when warranted. Carved executables: rename with a `.txt` suffix so they can't be
double-click-executed; compute SHA256/MD5 into `dumps/hashes.txt`. Live malware may trip the
analyst host's AV; if it blocks access, ask the user to approve an AV exclusion for `dumps/`
(never disable AV unilaterally). Note: a memory process-image hash will NOT match VirusTotal —
say so; a VT-matchable hash needs the on-disk file.

## Step 6 — Write the comprehensive IR report
Follow `references/report-template.md`. Produce `report/IR_Report.md` (+ optional `report.html`)
and `iocs.csv`. Lead with the outcome; ground every finding in a named artifact; label confidence.

## Safety rules (always)
- The image is READ-ONLY; never write to it. All output goes to the case folder.
- UTF-8 everywhere (avoids the PowerShell `>` UTF-16 problem).
- Batch collection is continue-on-error; log failures.
- Record the exact vol invocation + tool/plugin versions for reproducibility.

## References
- `references/plugins-windows.md`, `references/plugins-linux.md`, `references/plugins-macos.md`
- `references/report-template.md`
- `scripts/run_vol.ps1`, `scripts/run_vol.sh`
