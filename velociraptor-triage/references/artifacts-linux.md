# Linux artifact reference (Velociraptor)
Tags: [core] always-run, [heavy] large/slow.
Collect headless: `velociraptor --nobanner artifacts collect <name> --format jsonl` (one JSON object
per line; `--format json` emits concatenated per-source arrays that won't parse as one document).
YARA `[heavy]` artifacts need rules as args and are gated on a lead — don't run them empty by default.
Privilege note: journal, some process/SSH-key reads need root; run elevated or mark privilege-limited.

## Phase 1 — Host/context
| Generic.Client.Info | Host facts (hostname, OS, arch) | [core] |

## Phase 2 — Processes
| Linux.Sys.Pslist | Running processes | [core] |
| Generic.System.Pstree | Process tree — spot bad parentage | [core] |

## Phase 3 — Network
| Linux.Network.Netstat | Active connections | [core] |
| Linux.Network.NetstatEnriched | Connections enriched with process | [core] |

## Phase 4 — Persistence
| Linux.Sys.Crontab | Cron jobs | [core] |
| Linux.Sys.Services | systemd services | [core] |
| Linux.Ssh.AuthorizedKeys | SSH authorized_keys (backdoor keys) | [core] |
| Linux.Proc.Modules | Loaded kernel modules | [core] |

## Phase 5 — Execution evidence
| Linux.Sys.BashHistory | Shell history | [core] |
| Linux.Forensics.Journal | systemd journal | [core] |

## Phase 6 — Malware detection (YARA)
| Linux.Detection.Yara.Process | YARA scan of process memory | [core] |
| Linux.Detection.AnomalousFiles | Anomalous/suspicious files | [core] |
| Linux.Detection.Yara.Glob | YARA scan of files by glob | [heavy] |

## Phase 7 — Forensic deep-dive
| Linux.Search.FileFinder | Find files by path/size/time/yara | [heavy] |
| Linux.Sys.LogHunter | Hunt patterns across system logs | [heavy] |
| Linux.Sys.SUID | SUID binaries (privilege escalation) | [heavy] |
