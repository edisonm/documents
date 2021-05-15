# Installing Debian on Dell XPS 15 (9500) new version

- Disable Secure Bios and Intel RAID in the BIOS.  Since this will cause Windows
  boot to fail, disable Intel RAID on Windows beforehand, however I got this
  information too late, and ended up factory resetting my laptop.

- Install Debian using the non-graphical installer, since the kernel that comes
  by default is not yet fully compatible with this laptop.  Once installed, you
  should update the Kernel at least to 5.11 version, in my case I installed
  Proxmox latest version, which already provides such kernel.

- Consider to use Ventoy to create the USB installer:
  https://www.ventoy.net/en/index.html

- The system will not be usable after the installation, most of the tutorials on
  Internet cover such issues, but they where incomplete when applied to this new
  model, therefore I will point at those fixes that I have to figure out by
  myself:

## Fixing LXDE HiDPI

The reason I am switching from XFCE to LXDE, is because XFCE 1.12 shipped with
Debian 10 doesn't support HiDPI. Cinnamon was not an option either since it has
a bug that makes it consume CPU resources like crazy (maybe udisks2 related).

- follow this tutorial (works for Debian too):

  https://code.luasoftware.com/tutorials/linux/enable-hidpi-scaling-on-lubuntu/

- Fixing menu icon sizes:

  https://bbs.archlinux.org/viewtopic.php?id=208319

  Make (or edit) the file ~/.gtkrc-2.0.mine and add the line:

  ```
  gtk-icon-sizes = "gtk-menu=48,48"
  ```

  If the file ~/.gtkrc-2.0 doesn't exist, run lxappearance which will create
  it. That file will source the ~/.gtkrc-2.0.mine file.

  You can make it take effect without logging out with:

  ```
  lxpanelctl restart
  ```

  This will make the menu icons in most any GTK2 app that size. To change just
  the lxpanel menu plugin icon size you would have to recompile lxpanel after
  changing the GTK_ICON_SIZE_MENU in plugins/menu.c. I don't know what you would
  change it to, however.

- Fix mouse cursor size: 

  https://www.reddit.com/r/linux4noobs/comments/64nj3y/increasing_cursor_size_arch_lxde/

  To change the size of your mouse cursor, go to:

  ```
  /home/USERNAME/.config/lxsession/LXDE/desktop.conf
  ```

  find this line and change the value:

  ```
  iGtk/CursorThemeSize=42
  ```

  42 works well for the UHD screen

## Fixing WIFI
  
  From https://medium.com/@tomas.heiskanen/dell-xps-15-9500-wifi-on-ubuntu-20-04-d5f1c218e78a

  I figured out that the kernel (>5.11) already supports the WIFI, but there
  where some missing firmware files that are needed:

  - Clone the firmware
    ```
    git clone https://github.com/kvalo/ath11k-firmware.git
    ```
    
  - Copy the missing firmware files to the right directory

    ```
    cd ath11k-firmware
    sudo cp QCA6390/hw2.0/1.0.1/WLAN.HST.1.0.1–01740-QCAHSTSWPLZ_V2_TO_X86–1/*.bin /lib/firmware/ath11k/QCA6390/hw2.0/
    ```
    
## Fixing Bluetooth

  **Important**: I realize that if the Bluetooth firmware is not installed in
  Linux, it could cause this device to fail in Windows, it looks like a failed
  attempt to use it on Linux interfere in other OS, be aware of this.

  In Debian you should install the package firmware-atheros, but in proxmox, due
  to a conflict, you should get the file htbtfw20.tlv and copy it to
  /lib/firmware/qca/ by hand.  It can be found here:

  https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git

  The way I figured it out was by looking at dmesg:

  ```
  Bluetooth: hci0: QCA controller version 0x02000200
  Bluetooth: hci0: QCA Downloading qca/htbtfw20.tlv
  Bluetooth: hci0: QCA Failed to request file: qca/htbtfw20.tlv (-2)
  Bluetooth: hci0: QCA Failed to download patch (-2)
  ```
  
- Customizing LXDE Keyboard

  If you are using your own keyboard mapping, you need to follow the next
  instructions to make it available on LXDE and on the console. Keyboard
  mappings are defined in /usr/share/X11/xkb/. In this example I created a
  customized variant of us called emacs:

  - On ~/.config/autostart/, create a file called xmodmap.desktop, containing:

  ```
  [Desktop Entry]
  Type=Application
  Name=xmodmap wrapper
  Exec=/home/edison/apps/keyboard/xmodmap.sh
  Terminal=false
  ```

  xmodmap.sh contains a sleep 2 at the begining, for some reason we need to
  wait, may be due to a race condition:

  ```
  #!/bin/sh
  sleep 2
  /usr/bin/setxkbmap -layout "us,us,es" -variant "emacs,intl,"
  ```

  - modify /etc/default/keyboard:

  ```
  # KEYBOARD CONFIGURATION FILE

  # Consult the keyboard(5) manual page.

  XKBMODEL="pc105"
  XKBLAYOUT="us"
  XKBVARIANT="emacs"
  XKBOPTIONS=""

  BACKSPACE="guess"
  ```
  
- Restart the computer

## Problems that still remains:

- *NVIDIA Driver*: The new drivers are still not available as a debian package,
  since is not urgent for me I prefer to wait until they are available.

- No sound when using USB-C to HDMI output. May be related to the NVIDIA driver,
  we will see.
