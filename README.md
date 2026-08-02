# desktop-organizer

Automatic macOS desktop cleanup.

## What it does

1. **Daily** (at 10:30 by default) moves files and folders that appeared on
   the desktop **yesterday** (created there or copied in — tracked via the
   Spotlight "date added" attribute) into a folder named after that date:
   files from `2026-08-01` → folder `2026-08-01`.
2. **On the 1st of every month** (at the same time) moves all date folders
   from the previous month into a folder like `2026 июль` (year + month name).
3. If the computer was asleep or powered off at the scheduled time, the job
   runs **at the first opportunity** (on wake, at login, or within an hour
   of powering on). Missed days are caught up: files are sorted into folders
   matching the dates they appeared.
4. Files that could not be moved (busy, no permission, name already taken in
   the destination) are **skipped** — they are retried on subsequent runs for
   up to `CATCH_UP_DAYS` days.

## Installation

```bash
git clone <repository-url>
cd desktop-organizer
./install.sh
```

`install.sh` creates a launchd agent in `~/Library/LaunchAgents` and enables
it.

**Required: give bash access to the Desktop.** macOS privacy protection
(TCC) silently hides the Desktop from scripts run by launchd — the agent
will see an empty folder and do nothing. Grant access once:

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Click **+**, press **⌘⇧G** in the file dialog, type `/bin/bash`, press
   Enter and add it
3. Verify it works: `launchctl kickstart -k gui/$(id -u)/com.desktop-organizer.daily`,
   then check `~/Library/Logs/desktop-organizer.log`

## Configuration

All settings live in [`config.env`](config.env):

| Setting | Default | Meaning |
|---|---|---|
| `RUN_HOUR`, `RUN_MINUTE` | `10`, `30` | daily run time |
| `DESKTOP_DIR` | `~/Desktop` | folder to watch |
| `ARCHIVE_DIR` | `~/Desktop` | where to put the date folders |
| `CATCH_UP_DAYS` | `14` | how many days back to catch up on missed work |

After changing the time, run `./install.sh` again — it updates the agent's
schedule.

## Manual runs and debugging

```bash
./organize.sh --dry-run   # show what would be done without moving anything
./organize.sh --force     # run right now, ignoring the schedule
./organize.sh --daily     # only sort yesterday's files into date folders
./organize.sh --monthly   # only gather last month's folders into "YYYY <month>"
```

Any `config.env` variable can be overridden for a single run, e.g. to test
against a sandbox folder:

```bash
DESKTOP_DIR=~/test-desktop ARCHIVE_DIR=~/test-desktop ./organize.sh --dry-run
```

Log: `~/Library/Logs/desktop-organizer.log`.

Check that the agent is installed: `launchctl list | grep desktop-organizer`.

## Uninstall

```bash
./uninstall.sh
```

## How it works

- Scheduling uses **launchd** (`StartCalendarInterval`): unlike cron, launchd
  runs a job missed due to sleep as soon as the Mac wakes up.
- To cover the case when the Mac was fully **powered off**, the agent also
  fires at login and once an hour; the script itself makes sure the work
  happens no earlier than the configured time and no more than once a day
  (stamp file in `~/.local/state/desktop-organizer/last-run`).
- The date a file "appeared" comes from the Spotlight attribute
  `kMDItemDateAdded` (set both when a file is created and when it is copied
  into a folder); if the attribute is unavailable, the file creation date is
  used as a fallback.
- The monthly cleanup is not hard-wired to the 1st: on every run, date
  folders belonging to past months are moved into the matching
  `"YYYY <month>"` folder. So even if the computer was off on the 1st, the
  cleanup happens on the very next run.
