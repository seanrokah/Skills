# IR Report Template (velociraptor-triage)

Fill every `<...>`. Lead with the outcome. Ground each finding in a named artifact. State confidence.
Produce `report/IR_Report.md`; if html chosen, also a single self-contained `report/IR_Report.html`
(inline CSS, no external assets, printable to PDF). Mirror IOCs to `iocs.csv`.
Section headings are unnumbered — keep them that way.

# Velociraptor Live Triage — <HOST>

## Case metadata & evidence
- Case ID / examiner / dates (analysis date, incident date).
- Host / OS / build / arch; hostname; collection start/end (UTC).
- Velociraptor version + exact invocation; artifacts collected (link `collection/_collection_log.txt`).

## Executive summary
Plain language: what happened, scope/impact, attacker capability, confidence, top recommendations.

## Incident overview & scope
Host and users involved; time window; what was collected and what was not.

## Methodology & tools
Phased headless collection used; tools/versions; inherent limitations of live triage (volatile data,
running-state only).

## Detailed findings (grouped by artifact / phase)
For each: **Observation** / **Supporting artifact** (artifact name + `_Source`) /
**Assessment** (malicious|suspicious|benign) / **Confidence** (high|medium|low).
Include benign items you explicitly cleared.

## Attack narrative
Initial access → execution → C2 → discovery/collection → persistence → actions on objective.

## Investigation timeline (UTC)
| Timestamp (UTC) | Event | Source Artifact | Notes |

## MITRE ATT&CK mapping
| Tactic | Technique (ID + name) | Evidence |

## Indicators of Compromise (IOCs)
- **Network:** IPs / domains / ports / URLs.
- **Host/file:** names, full paths, hashes (SHA256/MD5/SHA1), sizes.
- **Persistence:** mechanism + location (autorun/service/task/cron/launch item).
- **Accounts/credentials:** affected users / exposed secrets / SSH keys.
(Mirror all rows into `iocs.csv`: type,value,context,confidence.)

## Affected accounts & credential exposure
Compromised users/secrets; recommended reset scope.

## Persistence mechanisms
Each mechanism, its location, and how to remove it.

## Containment & remediation
Contain / Eradicate / Credentials / Recover / Harden — incident-specific, on-point.

## Detection & hunting recommendations
What to alert on; hunt ideas; IOCs to deploy to SIEM/EDR.

## Conclusion & assessment
Overall determination and confidence.

## Limitations & open items
What could not be determined and why; recommended next acquisition steps (memory image, disk, logs).

## Appendices
Full artifact/file index; notable artifact excerpts.
