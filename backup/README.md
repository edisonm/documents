# Cold storage backup tool

- Copy the directory [backup](backup/) to your backup host

- Create a file called settings_[hostname].sh, where hostname is your backup
  hostname, following the example in settings_template.sh.

- Run ./backup.sh to do a dry-run that will show you what is going to happen

- Finally, run ./backup.sh all to start the backup process.
