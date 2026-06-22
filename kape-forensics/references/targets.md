# KAPE collection targets

Run: `kape.exe --tsource <X:> --tdest <out> --target <Name> [--vhdx <name>]`
Compound targets start with `!`. Pick the smallest target that covers the question.

## Triage defaults (start here)
| Target | Collects | When to use |
|---|---|---|
| !SANS_Triage | Broad DFIR triage set (MFT, registry, EVTX, prefetch, amcache, browser, etc.) | First choice for unknown-scope IR |
| KapeTriage   | Similar broad triage compound target | Alternative broad triage |
| !BasicCollection | Smaller core set | Fast/limited collection |

## Focused targets (when scope is known)
| Target | Collects | When to use |
|---|---|---|
| FileSystem      | $MFT, $J (USN), $LogFile, $Boot | Filesystem timeline / deleted-file evidence |
| EventLogs       | Windows EVTX logs | Logon/process/persistence event analysis |
| RegistryHives   | SYSTEM/SOFTWARE/SAM/SECURITY/NTUSER/UsrClass | Persistence, config, user activity |
| Prefetch        | C:\Windows\Prefetch\*.pf | Execution evidence |
| Amcache         | Amcache.hve | Executed-PE evidence + SHA1 |
| WebBrowsers     | Chrome/Edge/Firefox history & profiles | Browsing / download source |
| ScheduledTasks  | \Windows\System32\Tasks + \Windows\Tasks | Persistence via tasks |
| WindowsTimeline | ActivitiesCache.db | User activity timeline |

## Notes
- Use `--vhdx <name>` to containerize the collection (integrity + easy mounting for analysis).
- Use `--tflush` only on a fresh dest you intend to overwrite.
- `--tlist` lists all available targets in the KAPE install if you need one not above.
