---
name: kape-forensics
description: Use when asked to collect forensic artifacts with KAPE, triage a system, or analyze/parse a KAPE (or other triage) collection. Locates KAPE, checks prerequisites and elevation, then either collects (KAPE Targets) or analyzes (KAPE !EZParser + direct EZ Tools) and produces a manifest or a comprehensive IR report. Windows-only. Supports automatic and semi-auto modes with a mandatory confirmation before any live collection.
---

# KAPE Forensics (collect & analyze)

## When to use
The user wants to collect/triage a system with KAPE, or analyze an existing KAPE/triage collection.
Windows only.

## Step 0 — Decide operation and mode
- Operation: COLLECT vs ANALYZE (ask if unclear).
- Mode: **automatic** (end-to-end) or **semi-auto** (plan + stop at key points). Ask if unspecified.

## Step 1 — Locate KAPE + check prerequisites
Find `kape.exe` in order: user-given path -> `./kape.exe` / `./KAPE/kape.exe` -> common locations
(`~/Downloads/kape/KAPE`, `C:\KAPE`) -> `PATH`. Verify it runs.
If not found, STOP: KAPE is registration-gated and cannot be auto-downloaded — point the user to the
Kroll "KAPE" source and ask for the path.
Run `scripts/check_prereqs.ps1 -KapePath <dir>` to confirm `kape.exe` and the EZ Tools in
`Modules\bin`. If EZ Tools are missing, it prints what's absent and the `Get-KAPEUpdate.ps1` command
to fetch them (free).
**Elevation:** `kape.exe` requires Administrator for ANY operation — both COLLECT and the ANALYZE
`--module` broad pass. If not elevated: for COLLECT, STOP and tell the user to relaunch elevated
(you cannot self-elevate); for ANALYZE, skip the `kape.exe` broad pass and run the EZ Tools directly
per `references/analyze.md` — the direct tools do NOT need admin.

## Step 2 — COLLECT
- Source (`--tsource`): live drive (e.g. `C:`) by default, or any attached volume/mounted image.
- Target (`--target`): a triage default (`!SANS_Triage` or `KapeTriage`) in automatic; in semi-auto
  offer a choice from `references/targets.md`.
- Dest (`--tdest`): a writable case folder, ideally NOT on the volume being collected; optionally
  `--vhdx <name>` to containerize.
- **CONFIRM GATE (always, both modes):** render the exact command with
  `scripts/kape_collect.ps1 ... -DryRun`, show source/dest/target/elevation, and WAIT for explicit
  go-ahead. Only then run the same command without `-DryRun`.
- Result: the collection + `collection_manifest.md` (target, file/skip counts, VHDX hash, version, time).

## Step 3 — ANALYZE (hybrid)
- Source (`--msource`): a collection folder or mounted VHDX.
- Broad pass (needs admin): `scripts/kape_analyze.ps1 -Kape <kape.exe> -MSource <coll> -MDest <out>`
  runs `--module !EZParser` -> CSVs (MFT, registry, EVTX, Prefetch, Amcache, ...). If not elevated,
  the helper says so and you fall back to the direct EZ Tools below (which cover the same artifacts).
- Targeted deep-dives: run EZ Tools directly per `references/analyze.md` phases
  (e.g. `MFTECmd --de <entry>` to recover resident file contents; `EvtxECmd` for 4104/4688/4624/4720/7045/4698).
- **Automatic:** run the broad pass + sensible deep-dives end-to-end, then write the report; pause only on errors.
- **Semi-auto:** present the plan, run phase-by-phase, and STOP + summarize + wait when (a) a phase
  completes, (b) about to run a heavy/long step, (c) a suspicious IOC appears, (d) a tool errors.
- Result: parsed CSVs + `report/IR_Report.md` (+ optional `report.html`) + `iocs.csv`,
  following `references/report-template.md`.

## Safety rules (always)
- Source is READ-ONLY; never write to it. Output goes to a writable case folder; do not write a
  collection onto the volume being collected.
- UTF-8 everywhere. Record exact `kape.exe`/EZ-tool versions and the commands run (chain of custody).
- Carved/suspicious files: rename with a `.txt` suffix so they can't be double-click-executed; live
  malware may trip AV and need a user-approved exclusion (never disable AV unilaterally).

## References
- `references/targets.md`, `references/analyze.md`, `references/report-template.md`
- `scripts/check_prereqs.ps1`, `scripts/kape_collect.ps1`, `scripts/kape_analyze.ps1`
