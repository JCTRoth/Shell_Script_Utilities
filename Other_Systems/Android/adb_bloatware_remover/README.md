Safely preview and remove or disable Android packages (bloatware) over ADB. \
Takes a blacklist file (Apps never to remove, negative list) and a bloatwear.list. \
You can use the here provided files or create your own ones.

Files
- `adb_bloatware_remover.sh` — main script (dry-run by default).
- `bloatware.list` — example package list (one package name per line).
- `blacklist.list` — mandatory packages to never remove (one per line).

Quick usage
- Make script executable:

```bash
chmod +x adb_bloatware_remover.sh
```

- Preview actions (dry-run):

```bash
./adb_bloatware_remover.sh --dry-run bloatware.list
```

- Apply removals (uninstall or disable) after reviewing preview:

```bash
# Uninstall listed packages
./adb_bloatware_remover.sh --apply --action uninstall bloatware.list

# Disable listed packages instead
./adb_bloatware_remover.sh --apply --action disable bloatware.list
```

- Backup APKs/data before removing (recommended):

```bash
./adb_bloatware_remover.sh --apply --backup --action uninstall bloatware.list
```

- Simulation mode — write ADB commands to a script for review:

```bash
./adb_bloatware_remover.sh --simulate --action uninstall bloatware.list
```
This creates a file looking like this: \
adb_debloat_cmds_YYYYMMDD_HHMMSS.sh

- Phone simulation: use a file as the device's installed package list

```bash
# Use a pre-made `phone_simulation.list` instead of querying a real device
./adb_bloatware_remover.sh --phone-sim phone_simulation.list --dry-run bloatware.list
```

- Capture installed packages from a connected device and simulate with those packages:

```bash
# Capture current device packages and run a dry-run
./adb_bloatware_remover.sh --capture --dry-run bloatware.list
```


Behavior notes
- Lines starting with `#` and empty lines are ignored in package lists.
- Packages not present on the device are logged as `NOT FOUND` but skipped; summary contains only successful actions.
- Packages not present on the device are logged as `NOT FOUND` but skipped; summary contains only successful actions.
- The script expects `safe_blacklist.list` in the same folder. Update `BLACKLIST_FILE` inside the script to change this.
- Create `disable.list` to list packages that should be disabled (not uninstalled). Packages in `disable.list` are processed with the disable action regardless of the `--action` flag.
- Always run a dry-run or simulate before applying changes.

List format
- Plain text, one package name per line. Use `#` for comments.

Example list

```text
# Example: remove these
com.example.bloatapp
com.vendor.sponsor
```

Safety recommendations
- Do not add entries from `blacklist.list` to your removal lists.
- If unsure, comment out a package instead of deleting it.
- Use `--backup` before removing anything you might want to restore.

Extras (suggested)
- Consider adding `--check` to the script to produce a present/missing/blacklisted report.
- Consider adding a flag to specify the simulate output filename.

Support
- Requires ADB (Android Platform Tools) and an authorized device with USB debugging enabled.
```
Safety Tips
- Never add packages from `blacklist.txt` to a removal list.
- If unsure, comment the package out instead of deleting it.
- Use `--backup` when removing apps you might want to restore.

Support
- This tool uses `adb`. Ensure Android Platform Tools are installed and the device is authorized.
- For questions or changes, edit the script directly or open an issue in this repository.
