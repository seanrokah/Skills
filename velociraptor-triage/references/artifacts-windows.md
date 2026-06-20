# Windows artifact reference (Velociraptor)
Columns: Artifact | What it finds | Tag. Tags: [core] always-run, [heavy] large/slow.
Collect headless: `velociraptor --nobanner artifacts collect <name> --format jsonl` (one JSON object
per line; `--format json` emits concatenated per-source arrays that won't parse as one document).
YARA `[heavy]` artifacts need rules as args and are gated on a lead — don't run them empty by default.

## Phase 1 — Host/context
| Generic.Client.Info | Hostname, OS, arch, MACs, basic host facts | [core] |

## Phase 2 — Processes
| Windows.System.Pslist | Running processes (path, pid/ppid, hashes) | [core] |
| Generic.System.Pstree | Process tree — spot bad parentage | [core] |

## Phase 3 — Network
| Windows.Network.Netstat | Active TCP/UDP connections + owning process | [core] |
| Windows.Network.NetstatEnriched | Netstat enriched with process metadata | [core] |

## Phase 4 — Persistence / autoruns
| Windows.Sysinternals.Autoruns | Autostart entries (autorunsc) | [core] |
| Windows.System.Services | Services incl. stopped | [core] |
| Windows.System.TaskScheduler | Scheduled tasks | [core] |
| Windows.Persistence.PermanentWMIEvents | WMI event-consumer persistence | [core] |
| Windows.Persistence.PowershellProfile | PowerShell profile persistence | [core] |

## Phase 5 — Execution evidence
| Windows.Forensics.Prefetch | Program execution (prefetch) | [core] |
| Windows.Detection.Amcache | Program execution / presence (Amcache) | [core] |

## Phase 6 — Malware detection (YARA)
| Windows.Detection.Yara.Process | YARA scan of process memory | [core] |
| Windows.Detection.Yara.Glob | YARA scan of files by glob | [heavy] |

## Phase 7 — Forensic deep-dive
| Windows.EventLogs.Evtx | Raw EVTX event-log records | [heavy] |
| Windows.EventLogs.EvtxHunter | Keyword/IOC hunt across event logs | [heavy] |
| Windows.Detection.ProcessCreation | Suspicious process-creation events | [heavy] |
| Windows.Detection.Usn | USN journal (recent file activity) | [heavy] |
