# Linux plugin reference (Volatility 3)
Requires matching ISF symbols (kernel banner). Tags: [core]/[heavy]/[dump].

## Phase 1 — Image context
| banners.Banners | Kernel banner/version (also used for OS detection) | [core] |
| linux.kmsg.Kmsg | Kernel ring buffer | [core] |

## Phase 2 — Process triage
| linux.pslist.PsList | Active processes | [core] |
| linux.pstree.PsTree | Process tree | [core] |
| linux.psaux.PsAux | Process args (full command line) | [core] |
| linux.psscan.PsScan | Pool-scanned processes (hidden) | [core] |

## Phase 3 — Network
| linux.sockstat.Sockstat | Open sockets per process | [core] |

## Phase 4 — Injection / rootkit
| linux.malfind.Malfind | Injected code regions | [core] |
| linux.check_syscall.Check_syscall | Syscall table hooks | [core] |
| linux.check_modules.Check_modules | Hidden kernel modules | [core] |
| linux.lsmod.Lsmod | Loaded kernel modules | [core] |

## Phase 5 — Persistence / execution
| linux.bash.Bash | Recovered bash history | [core] |
| linux.elfs.Elfs | Mapped ELF binaries | [core] |

## Phase 6 — Files / bulk
| linux.lsof.Lsof | Open files per process | [heavy] |
| linux.pagecache.Files | File objects in page cache | [heavy] |

## Phase 7 — Carving
| linux.pslist.PsList --pid <PID> --dump | Dump a process | [dump] |
