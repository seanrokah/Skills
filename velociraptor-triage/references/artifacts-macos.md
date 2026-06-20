# macOS artifact reference (Velociraptor)
Tags: [core] always-run, [heavy] large/slow.
Collect headless: `velociraptor --nobanner artifacts collect <name> --format json`.

## Phase 1 — Host/context
| Generic.Client.Info | Host facts (hostname, OS, arch) | [core] |

## Phase 2 — Processes
| MacOS.Sys.Pslist | Running processes | [core] |
| Generic.System.Pstree | Process tree — spot bad parentage | [core] |

## Phase 3 — Network
| MacOS.Network.Netstat | Active connections | [core] |

## Phase 4 — Persistence / autoruns
| MacOS.Detection.Autoruns | LaunchDaemons/Agents + login items | [core] |
| MacOS.System.QuarantineEvents | Downloaded-file quarantine history | [core] |
| MacOS.System.TCC | TCC privacy permissions (abuse) | [core] |

## Phase 5 — Execution evidence
| MacOS.Detection.InstallHistory | Software install history | [core] |
| MacOS.Sys.SUID | SUID binaries (privilege escalation) | [core] |

## Phase 6 — Malware detection (YARA)
| MacOS.Detection.Yara.Process | YARA scan of process memory | [core] |
| MacOS.Detection.Yara.Glob | YARA scan of files by glob | [heavy] |

## Phase 7 — Forensic deep-dive
| MacOS.Search.FileFinder | Find files by path/size/time/yara | [heavy] |
| MacOS.Forensics.FSEvents | Filesystem-event history | [heavy] |
