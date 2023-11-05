# Installing Linux encrypted

One of the tasks in the company I work for was to improve the security of the
systems.  Since most of our servers use Linux, it was natural to try to encrypt
the storage of those machines, but then the problems begin, the installers don't
provide an easy way.  Instead, I was immersed in a read of several web pages,
and figuring out the right sequence of manual steps results being a challenge.
So to avoid to forget those steps over the time, and to automate them, I created
a script to be used instead of the default installer.

Currently it supports **Debian**, **Proxmox** and **Ubuntu**.

## Requirements:

This script assumes it will be used in a machine of minimum 32GB of storage,
although I would recommend a minimum of 64GB for production machines, it support
UEFI or BIOS, the root fs will be a btrfs/zfs/ext4 encrypted via LUKS.

To support encryption, it doesn't use dracut since is too much hustle,
fail-prone in practice and proxmox is not compatible with it yet.  Instead, it
does a password-less unlock via a key-file which is encrypted via clevis+(tang
or tpm2) or tpm1, and password input via keyboard as fail-over.

The script ask a minimum amount of questions only at the beginning, and once
settled, it runs in a non-interactive way.

## Installation:

- First make sure you backup your data before to continue, since this script
  could erase all your partitions (deliberately of accidentally).

- Start your computer from a Live CD/USB and try the live system now (not the
  installer, since we are going to use our own method).
  
- Copy the directory [deploy](deploy/) from where you download it:

  ```
  $ rsync -av [Source]/deploy .
  ```
  
- Edit the file deploy.sh and change the options according to your preferences.

  **Note**: Encrypted Proxmox with no boot partition will means all the drive
  except the efi partition will be encrypted. That is possible since Proxmox
  keep the kernel in the EFI partition.
  
- as root, run deploy.sh and follow the instructions

  ```
  $ cd deploy
  $ sudo ./deploy.sh
  ```

- Once the system is deployed, a copy of this script will remain in
  `/home/$USERNAME/deploy/` to perform maintenance tasks, reconfiguration or
  fixes.  Don't update it without considering that the file system layout could
  change in newer versions of the script.

  If you need to perform a maintenance task, run the live-CD up to the previous
  step and execute:

  ```
  $ sudo ./deploy.sh rescue
  ```

  That will chroot into the installed system so that you can perform some
  maintenance/repair tasks, for instance, if the initramfs is broken and you
  need to rebuild it:

  ```
  # update-intramfs -c -k all
  ```
