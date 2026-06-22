# KAPE analysis — phases, tools, stop triggers

Broad pass first: `kape.exe --msource <coll> --mdest <out> --module !EZParser` (produces CSVs).
NOTE: `kape.exe` requires Administrator even for this `--module` pass. If you are not elevated, skip
the broad pass and run the EZ Tools directly (below) — they do NOT need admin and cover the same artifacts.
Then targeted EZ-Tool deep-dives per phase below. EZ Tools live in `<KAPE>\Modules\bin`
(some, e.g. EvtxECmd, are in a subfolder there).

## Phases (tag: [core]/[heavy])
1. Collection/host context [core] — host/OS from SYSTEM/SOFTWARE hives; collection metadata.
2. Execution [core] — `PECmd.exe -d <coll>\Windows\prefetch --csv <out>` (Prefetch);
   `AmcacheParser.exe -f <coll>\Windows\appcompat\Programs\Amcache.hve --csv <out>` (SHA1s);
   `AppCompatCacheParser.exe -f <coll>\Windows\System32\config\SYSTEM --csv <out>` (ShimCache).
3. Filesystem timeline [core] — `MFTECmd.exe -f "<coll>\$MFT" --csv <out>`;
   recover resident small-file contents with `MFTECmd.exe -f "<coll>\$MFT" --de <entryNumber>`.
4. Events [core] — `EvtxECmd.exe -d <coll>\Windows\System32\winevt\Logs --csv <out>`;
   key IDs: 4624/4625 logon, 4688 process creation, 4720 account, 7045 service, 4698 task, 4104 PowerShell.
5. Persistence [core] — registry Run keys/services via RECmd (or from !EZParser registry output);
   scheduled tasks under \Windows\System32\Tasks and \Windows\Tasks.
6. User activity [heavy] — UserAssist; `SBECmd.exe` (shellbags); `LECmd.exe`/`JLECmd.exe` (lnk/jumplists);
   browser history.
7. Network/usage [heavy] — `SrumECmd.exe -f <coll>\Windows\System32\sru\SRUDB.dat --csv <out>`.
8. Recovered content [heavy] — `RBCmd.exe` (recycle bin); resident MFT data (phase 3).

## Semi-auto STOP triggers
Stop + summarize + wait when: (a) a phase completes; (b) about to run a [heavy] step;
(c) a suspicious IOC appears (external C2, odd autostart, attacker tool path, credential file,
timestomping); (d) a tool errors or a hive/log is missing.

## Notes
- A small file (<~700 bytes) may be MFT-resident -> recoverable from `$MFT` alone via `--de`.
  Larger files are non-resident -> need the actual collected file / disk image.
- Record every command run for chain of custody.
