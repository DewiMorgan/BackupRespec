Changelog
=========

1.0.0
-----
Initial upload.

ToDo
----
MVP:
* WONTDO: Can I back up all characters from one character? (NO) If not, consider changing from ZO_SavedVars:NewAccountWide (Why?) 
* WONTDO: Safety Feature: Manual backup should reloadui, so crashes don't prevent backup. (No, just warn about it)
* DONE: Decide which windows I want to add the buttons to. Hook open/close.
* DONE: Feature: Add backup and restore buttons.
* DONE: Safety Feature: Back up any character that is not already backed up.
* DONE: Safety Feature: Don't enable the backup button if no points have been spent.
* DONE: Confirmation dialog for overwriting with new backup.
* DONE: Feature: Back up CP on pressing the backup button.
* DONE: Feature: Back up SP on pressing the backup button.
* DONE: "N of M characters backed up" or "All characters backed up", if can't do it from a single char. (Can't. Can only say "N backed up.")
* DONE: Index data by server and account id as well as user.
* DONE: Organize CP by attribute. 
* ToDo: Feature: Restore CP on pressing the restore button.
* ToDo: Feature: Restore SP on pressing the restore button.
* ToDo: Update the link in the readme and batch file once I've uploaded it.
* ToDo: BUG: CP Available should be capped at the max (there's a fn to get it, currently 810)
* ToDo: BUG: Always detecting as overwriting older.

Nice to have:
* ToDo: Safety Feature: Export to CSV?
* ToDo: Feature: Update auto-backup on character update?
* ToDo: Feature: Have restore button only show up/enable if there is a backup?
* ToDo: Save timestamp with each backup so user can pick which to delete?
* ToDo: Maintain auto-backup and manual backup, and offer a choice on restore if manual is older than auto?
* ToDo: Get it working in gamepad mode.
* ToDo: Confirmation dialog for restoring.
* ToDo: Allow user to verify the CP spend, before committing it.
* ToDo: Some way to verify the skillpoint spend, before committing it?
* ToDo: guesstimate if their skill points add up correctly, warn if they might lose some.
