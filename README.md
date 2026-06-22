# Skills

A collection of [Claude Code](https://claude.com/claude-code) skills.

## Skills

- **[memory-forensics](memory-forensics/)** — Volatility 3 memory-image analysis: locates Volatility, auto-detects the image OS (Windows/Linux/macOS), runs a phased plugin workflow, and produces a comprehensive IR report. Supports automatic and semi-auto modes.
- **[velociraptor-triage](velociraptor-triage/)** — Standalone DFIR triage with Velociraptor: acquires/preps the binary (portable, no install), detects the host OS (Windows/Linux/macOS), runs a phased headless artifact-collection workflow to hunt malicious activity, and produces an IR report (Markdown or HTML). Supports automatic and semi-auto modes.
- **[kape-forensics](kape-forensics/)** — Collect and analyze forensic artifacts with KAPE (Windows): locates KAPE, checks prerequisites/elevation, collects triage targets (with a mandatory dry-run confirm gate) or analyzes a collection via !EZParser + EZ Tools, and produces a manifest or comprehensive IR report. Supports automatic and semi-auto modes.
