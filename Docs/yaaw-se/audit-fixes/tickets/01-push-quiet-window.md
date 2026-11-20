# 01: Push script installs only inside a quiet window

**Status:** ready
**Agent:** yaaw-dev
**Blocked by:** None
**Issue:** Fixes #3

## What to build
The phone push script stops killing the app while it is in use. A new commit on the branch is built and installed only inside a quiet window (default 02:00-06:00 local time). `--force` installs at once, at any hour. Re-signing the build already on the phone still happens outside the window when the 7-day signature has less than a day left.

Behaviour of `Scripts/push-to-phone.sh` after the change:
- New option `--quiet-hours HH-HH`: start hour inclusive, end hour exclusive, local time, default `02-06`. A window may wrap midnight (`22-06`). An invalid value logs an error and exits non-zero.
- New commit available and the hour is inside the window, or `--force`: build and install as today. The ancestry check (`push-to-phone.sh:94`) is unchanged; `--force` still overrides it too.
- New commit available, outside the window, no `--force`: log `waiting for quiet window HH-HH (now HH)` and do not build or install.
- Re-signing the installed build (same commit, or a commit that cannot land): inside the window, when the signature is 3 days old or more (today's `resign_after`). Outside the window, only when it is 6 days old or more. An urgent re-sign outside the window never installs a new commit.
- Every run logs the local hour it used, so the user can confirm WSL's time zone.

Behaviour of `Scripts/install-push-task.ps1`:
- New parameter `-QuietHours` (string, default `'02-06'`, validated as `HH-HH` with hours 0-23), passed to the script as `--quiet-hours`.
- Besides the `-Minutes` repetition, the task gets a daily trigger 5 minutes after the window opens, so at least one run lands inside the window whatever `-Minutes` is. The printed summary names the window.
- The task does not wake the PC (decided, `DECISIONS.md` Round 2): no `-WakeToRun` in its settings. When the PC is off or asleep during the window, nothing installs, and the `waiting for quiet window HH-HH (now HH)` log line is how the user sees it.
- Header comments in both files describe the window, `--force` and `-QuietHours`, and say the PC is not woken: if it is usually off at night, move the window with `-QuietHours`.

The decision logic (in window, install, re-sign) moves into shell functions that take the hour and the signature age as arguments. The script's side effects (log redirect at `:21`, `flock` at `:22-23`, relay start, `xtool`, `git`) must not run when the functions are tested. Either source a small `Scripts/push-policy.sh` from the script, or guard the main body so it does not run when sourced.

## Design direction
None.

## Seams
- New `Scripts/test-push-to-phone.sh`, run locally with Git Bash (`bash Scripts/test-push-to-phone.sh`). It exits 0 when every case passes and prints each failing case. Cases: `02-06` at hours 1, 2, 5, 6; `22-06` at 21, 22, 3, 6; install decision inside, outside and outside with force; re-sign decision at 2, 3, 5, 6 and 7 days inside and outside the window; rejection of `25-06`, `2-6x` and an empty value.
- PowerShell parse check of `install-push-task.ps1` with no errors: `powershell -NoProfile -Command "$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('Scripts/install-push-task.ps1',[ref]$null,[ref]$e) | Out-Null; if ($e) { $e; exit 1 }"`.

## Reuse first
- `Scripts/push-to-phone.sh`: `resign_after`, `due`, `deploy`, `build`, `log` (lines 19, 63-91, 107-111).
- `Scripts/install-push-task.ps1`: `param` block, `New-ScheduledTaskTrigger`, `Register-ScheduledTask` (lines 4-17).

## Acceptance criteria
- [ ] `bash Scripts/test-push-to-phone.sh` passes locally; the output is in the report.
- [ ] The PowerShell parse check prints nothing and exits 0; the output is in the report.
- [ ] `bash -n Scripts/push-to-phone.sh` passes.
- [ ] Outside the window with a new commit and no `--force`, the script logs the waiting line and never calls `build` or `deploy` (shown by a test case on the decision function).
- [ ] With `--force` a new commit installs at any hour.
- [ ] Outside the window a re-sign happens only at a signature age of 6 days or more; inside it, at 3 days or more.
- [ ] `install-push-task.ps1 -QuietHours '23-05'` would register a daily trigger at 23:05 plus the repetition (shown by reading the code path; the agent does not register a task on this machine).
- [ ] `install-push-task.ps1` does not use `-WakeToRun` (`grep -n WakeToRun Scripts/install-push-task.ps1` prints nothing), and its header says the PC is not woken.
- [ ] Branch `fix/audit` is pushed and the draft PR to `main` exists (`gh pr create --draft --base main --head fix/audit` if `gh pr list --head fix/audit` shows none). The PR URL is in the report.
- [ ] Committed with `Fixes #3` in the message, pushed, and the CI `test` job on the draft PR is green; the run URL and result are in the report.

## Not in this ticket
Waking the PC for the window (`-WakeToRun`, declined in `DECISIONS.md` Round 2). Changing build steps, device discovery or the ancestry check. Registering the scheduled task on this PC (the user re-runs `install-push-task.ps1` after merge).
