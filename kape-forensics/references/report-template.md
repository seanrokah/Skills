# IR Report Template (kape-forensics)

Fill every `<...>`. Lead with the outcome. Ground each finding in a named artifact. State confidence.
Produce `report/IR_Report.md` + optional `report.html`, and mirror IOCs to `iocs.csv`.
Section headings are unnumbered — keep them that way.

# Forensic Investigation — <HOST>

## Case metadata & evidence
- Case ID / examiner / dates (analysis date, incident date).
- Host / OS / build; collection source, KAPE target(s) used, acquisition time.
- Evidence integrity: collection/VHDX SHA256 (if available).
- KAPE version + EZ-tool versions; exact commands run.

## Executive summary
Plain language: what happened, scope/impact, attacker capability, confidence, top recommendations.

## Incident overview & scope
Systems and users involved; time window; what was collected/examined and what was not.

## Methodology & tools
KAPE collection + hybrid analysis (!EZParser + direct EZ Tools); tool versions; limitations.

## Detailed findings (grouped by artifact source)
For each: **Observation** / **Supporting artifact** / **Assessment** (malicious|suspicious|benign) /
**Confidence** (high|medium|low). Include benign items you explicitly cleared.

## Attack narrative
Initial access -> execution -> C2 -> discovery/collection -> persistence -> actions on objective.

## Investigation timeline (UTC)
| Timestamp (UTC) | Event | Source Artifact | Notes |

## MITRE ATT&CK mapping
| Tactic | Technique (ID + name) | Evidence |

## Indicators of Compromise (IOCs)
- **Network:** IPs / domains / ports / URLs.
- **Host/file:** names, full paths, hashes (SHA256/MD5/SHA1), sizes.
- **Registry:** keys / values.
- **Persistence:** mechanism + location.
- **Accounts/credentials:** affected users / exposed secrets.
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
What could not be determined and why; recommended next acquisition steps.

## Appendices
Full artifact/file index; recovered file contents; notable parsed-CSV excerpts.
