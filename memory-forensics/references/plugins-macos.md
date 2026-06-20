# macOS plugin reference (Volatility 3)
Requires matching ISF symbols. Tags: [core]/[heavy]/[dump].

## Phase 1 — Image context
| banners.Banners | Kernel banner/version | [core] |

## Phase 2 — Process triage
| mac.pslist.PsList | Active processes | [core] |
| mac.pstree.PsTree | Process tree | [core] |
| mac.psaux.Psaux | Process args | [core] |

## Phase 3 — Network
| mac.netstat.Netstat | Network connections | [core] |

## Phase 4 — Injection / rootkit
| mac.malfind.Malfind | Injected code regions | [core] |
| mac.check_syscall.Check_syscall | Syscall hooks | [core] |
| mac.check_sysctl.Check_sysctl | sysctl hooks | [core] |
| mac.kauth_listeners.Kauth_listeners | kauth listeners (rootkits) | [core] |

## Phase 5 — Modules / bulk
| mac.lsmod.Lsmod | Loaded kexts | [core] |
| mac.lsof.Lsof | Open files | [heavy] |

## Phase 6 — Carving
| mac.pslist.PsList --pid <PID> --dump | Dump a process | [dump] |
