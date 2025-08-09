# Note: all the non commented out options are compulsory

# UUID of volumes containing storage volumes (zfs, luks, btrfs), intended to be removable medias

# Example:
# volumes="2533ff7a-de7e-4c21-b926-541a2be9c81a \
#          cba45c0a-e776-453c-9374-9ed5451316fc \
#          5fa34059-96fb-4ec3-8a0a-12ff3176e514 \
#          594f1c70-ad60-4be2-8744-ebdef9794e68 \
#          f46569cf-8290-4284-b947-67254e9a85e1 \
#          c08a3242-6e2d-4eee-9c03-0e7ae19d6c5d"

volumes=""

# Format of the receiving media Pool:Format, where Pool is the media pool
# and Format can be:
# - clone: The same filesystem of the source (default).
# - zdump: A raw file containing the output of zfs/btrfs send
# recvformat="hdump:clone hpool:zdump"
recvformats=""

# Use zdumpext to control the compression of the raw files.  Also
# specifies the extension of the raw files to help to identify them
# - raz: The file will be compressed via lrz
# - rat: The file will be compressed via zstd
# - raw: No compression is applied

declare -A zdumpext

# zdumpext[pool]=raz
# zdumpext[pool]=raw
zdumpext[back4]=rat

# Temporary cache's to speed-up the backup, usually in fixed SSD drives, that is
# why we can index them by [mediahost,media_pool]
declare -A caches

# Example:
# caches[host2,apool,cache]="3a1857ff-a9d7-42e7-8488-c5ba2cac07d1"
# caches[host2,hpool,log]="a621b8c2-5845-4b16-844c-b0f304ac1c75"

# hosts to search for removable medias.  This allows a machine to send the
# backup to a remote receiver where the medias are plugged.
# Trick: ; means localhost

# Example:
# mediahosts="tbak1 tbak2"

mediahosts=""

# zfs   pools   and fs
# btrfs volumes and subvolumes

# Note: In btrfs, volume labels will be zfs pool equivalents, but to avoid
# ambiguities, we should add the uuid of such volume. In zfs, the uuid is just
# used to double-check if is the right pool

# Example:
# backjobs="tbak1;zpool;tank;/ROOT;;;/TST11 \
#           tbak1;zpool;tank@18072502666171926021;/ROOT;tbak2;tank;/TST12 \
#           tbak1;btrfs;boot@f1f9009a-ea57-43c2-a650-34f9a57e30af;;;;/TST13 \
#           tbak1;btrfs;root@c797ec3f-4807-4b16-a32f-aecf0a76feac;/@;;;/TST14 \
#           tbak1;btrfs;root@c797ec3f-4807-4b16-a32f-aecf0a76feac;/@home;;;/TST15 \
#           tbak2;zpool;tank;/ROOT;;;/TST2"

backjobs=""

# snapshots to clean up
# Example:
# dropsnaps="22051009 23010309"

# dropsnaps=""

# Enable smart retention policy:

# 1 backup per hour for 1 day,
# 1 backup per day for 1 week,
# 1 backup per week for 1 month,
# 1 backup per month for 1 year,
# 1 backup per year

smartretp=1

# TODO: apply this at the end of a new backup (for instance, over pool set1):
# for i in `df 2>/dev/null|grep set1|awk '{print $1}'`; do sudo zfs set canmount=off $i ; done
