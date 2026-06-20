# Windows plugin reference (Volatility 3)

Columns: Plugin | What it finds | Tag. Tags: [core] always-run, [heavy] large/slow, [dump] writes files.

## Phase 1 — Image context
| windows.info | OS build, arch, time of capture, KDBG, CPU count | [core] |

## Phase 2 — Process triage
| windows.pslist | Active processes (EPROCESS list) | [core] |
| windows.psscan | Pool-scanned processes (finds hidden/terminated) | [core] |
| windows.pstree | Parent/child tree — spot bad parentage | [core] |
| windows.cmdline | Process command lines | [core] |

## Phase 3 — Network
| windows.netscan | Pool-scanned connections/sockets (incl. closed) | [core] |
| windows.netstat | Live connection structures | [core] |

## Phase 4 — Injection / rootkit
| windows.malfind | Injected/unbacked executable memory (confirm with MZ/PE header, not RWX alone) | [core] |
| windows.ldrmodules | DLLs unlinked from loader lists (hollowing) | [core] |
| windows.modules | Loaded kernel modules (list) | [core] |
| windows.modscan | Pool-scanned kernel modules | [core] |
| windows.ssdt | System call table hooks | [core] |
| windows.callbacks | Kernel notification callbacks | [core] |
| windows.driverscan | Driver objects | [core] |

## Phase 5 — Persistence
| windows.svcscan | Services (incl. stopped) | [core] |
| windows.registry.printkey | Registry keys; run with `--key "Software\Microsoft\Windows\CurrentVersion\Run"` | [core] |
| windows.registry.userassist | Program execution evidence | [core] |

## Phase 6 — Credentials
| windows.hashdump | SAM NT/LM hashes | [core] |
| windows.lsadump | LSA secrets | [core] |
| windows.cachedump | Cached domain creds | [core] |

## Phase 7 — Execution / console
| windows.cmdscan | Console command history buffers | [core] |
| windows.consoles | Console screen buffers (typed + output) | [core] |
| windows.sessions | Logon sessions | [core] |
| windows.privileges | Token privileges | [core] |
| windows.getsids | Process owners (SIDs) | [core] |
| windows.envars | Process environment variables | [core] |

## Phase 8 — Bulk
| windows.dlllist | Loaded DLLs per process | [heavy] |
| windows.handles | Open handles per process | [heavy] |
| windows.filescan | File objects in memory (paths) | [heavy] |
| windows.vadinfo | VAD regions | [heavy] |
| windows.mutantscan | Named mutexes (malware markers) | [heavy] |

## Phase 9 — Carving
| windows.pslist --pid <PID> --dump | Dump a process image | [dump] |
| windows.dumpfiles --physaddr <off> | Dump a file by offset (from filescan) | [dump] |
| windows.malfind --dump | Dump injected regions | [dump] |
