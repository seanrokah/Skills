---
name: velociraptor-triage
description: Use when asked to run Velociraptor, triage a live host for malicious activity, hunt/IR on this machine, or collect DFIR artifacts. Acquires and preps the Velociraptor binary (portable, no install), detects the host OS, runs a phased headless artifact-collection workflow, and produces an IR report (Markdown or HTML). Supports automatic and semi-auto modes.
---

# Velociraptor Triage (standalone DFIR)

## When to use
The user wants to triage the live host with Velociraptor — "run Velociraptor", hunt for malicious
activity, do live IR/DFIR on this machine, or collect detection artifacts. Runs against the LOCAL
host (not a disk/memory image).

## First: pick mode + report format (ask if unspecified)
- **Mode:** Automatic (run end-to-end; pause only on hard errors) or Semi-auto (plan, then
  phase-by-phase with stops).
- **Report format:** `md` (default) or `html` (self-contained, print-to-PDF capable).

## Step 1 — Acquire Velociraptor (portable, no install)
Resolve in order, first success wins:
1. Path the user provided.
2. `velociraptor*` in cwd (`./velociraptor`, `.\velociraptor.exe`, `velociraptor-v*-<os>-<arch>`).
3. On PATH: `velociraptor`, `velociraptor.exe`.
If none resolve, ASK the user: (a) they download + provide the path, or (b) Claude downloads the
matching asset from the official GitHub repo (`Velocidex/velociraptor` releases) for the host OS+arch
and verifies it (size/hash/signature where published). Then prep for portable use:
- Unix: `chmod +x <binary>`.
- macOS also: `xattr -d com.apple.quarantine <binary>` (clears Gatekeeper; required).
Verify with `velociraptor version`; record the resolved invocation. NEVER `service install`.

## Step 2 — Detect host OS
Velociraptor runs on the live host, so OS = this machine. Detect platform (Windows/Linux/macOS) and
use the matching reference `references/artifacts-<os>.md`. Record host OS/arch/hostname.

## Step 3 — Case folder
Default `./velo_triage_<UTCstamp>/` with `collection/` (raw artifact JSON + `_collection_log.txt`),
`report/`, and `iocs.csv`. All outputs UTF-8.

## Step 4 — Run the phased workflow
Headless: `velociraptor --nobanner artifacts collect <Artifact> --format json` (per-artifact to
`collection/<name>.json`); ad-hoc `velociraptor query "<VQL>"` for follow-ups. Batch with the helper:
`scripts/run_velo.ps1` (Windows) or `scripts/run_velo.sh` (Linux/macOS). Artifacts are tagged
`[core]`/`[heavy]` in the per-OS reference.
Helper limitation: extra args split on spaces — run an artifact whose arg value contains a space directly.

Phase order: 1) Host/context  2) Processes  3) Network  4) Persistence/autoruns
5) Execution evidence  6) YARA malware detection  7) [heavy] forensic deep-dive.

- **Automatic:** run all `[core]` + sensible `[heavy]`; then write the report.
- **Semi-auto:** present the plan, wait for OK, run phase-by-phase, STOP + summarize + wait when:
  (a) a phase completes, (b) about to run a `[heavy]` step, (c) a suspicious detection appears
  (YARA hit, external/odd-port C2, suspicious autostart/scheduled task/service, anomalous process
  tree, credential/SSH-key exposure), (d) an artifact errors. Resume on the user's "ok"/guidance.

## Step 5 — Parse results & write the report
Parse the per-artifact JSON in `collection/` (each row carries a `_Source` tag). Follow
`references/report-template.md`. Produce `report/IR_Report.md`; if `html` chosen, also
`report/IR_Report.html` (single self-contained file, inline CSS, printable to PDF). Mirror IOCs to
`iocs.csv`. Lead with the outcome; ground every finding in a named artifact; label confidence.

## Safety rules (always)
- Collection/READ-ONLY by default. NEVER run remediation/quarantine/kill artifacts unless the user
  explicitly asks (treat as destructive, gated).
- Portable: never `service install`; nothing persists. Offer to remove the binary + case folder after.
- UTF-8 everywhere; batch collection is continue-on-error (log failures).
- YARA may flag/lock live malware via host AV; note AV interactions, never disable AV unilaterally.
- Record exact Velociraptor version + every artifact invocation for reproducibility.

## References
- `references/artifacts-windows.md`, `references/artifacts-linux.md`, `references/artifacts-macos.md`
- `references/report-template.md`
- `scripts/run_velo.ps1`, `scripts/run_velo.sh`
