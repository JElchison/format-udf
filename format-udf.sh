#!/bin/bash

# format-udf.sh
#
# Bash script to format a block drive (hard drive or Flash drive) in UDF.  The output is a drive that can be used for reading/writing across multiple operating system families:  Windows, OS X, and Linux.  This script should be capable of running in OS X or in Linux.
#
# Version 1.1.2
#
# Copyright (C) 2015 Jonathan Elchison <JElchison@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


# setup Bash environment
set -euf -o pipefail


###############################################################################
# constants
###############################################################################

# maximum number of heads per cylinder
HPC=255
# maximum number of sectors per track
SPT=63


###############################################################################
# functions
###############################################################################

# Prints script usage to stderr
# Arguments:
#   None
# Returns:
#   None
print_usage() {
    echo "Usage:    $0 <drive> <label>" >&2
    echo "Example:  $0 sda \"My External Drive\"" >&2
}

# Prints hex representation of CHS (cylinder-head-sector) to stdout
# Arguments:
#   Logical block address (LBA)
# Returns:
#   None
function lba_to_chs {
    LBA=$1
    C=$((($LBA/($HPC*$SPT)) % (2**10)))
    C_HI=$((($C>>8) % (2**2)))
    C_LO=$(($C % (2**8)))
    H=$(((($LBA/$SPT) % $HPC) % (2**8)))
    S=$(((($LBA % $SPT) + 1) % (2**6)))
    printf "%02x%02x%02x" $H $((($C_HI<<6)|$S)) $C_LO
}

# Prints hex representation of value in host byte order
# Arguments:
#   32-bit integer
# Returns:
#   None
function ntohl {
    if sed --version &> /dev/null; then
        # this box has GNU sed ('-r' for extended regex)
        printf "%08x" $1 | tail -c 8 | sed -r 's/(..)/\1 /g' | awk '{print $4 $3 $2 $1}'
    else
        # this machine must have BSD sed ('-E' for extended regex)
        printf "%08x" $1 | tail -c 8 | sed -E 's/(..)/\1 /g' | awk '{print $4 $3 $2 $1}'
    fi
}

# Prints hex representation of entire-disk partition entry.  Reference:
# https://en.wikipedia.org/wiki/Master_boot_record
# https://en.wikipedia.org/wiki/Cylinder-head-sector
# https://en.wikipedia.org/wiki/Logical_block_addressing
# Arguments:
#   Device
# Returns:
#   None
function entire_disk_partition_entry {
    TOTAL_SIZE=$1
    BLOCK_SIZE=$2
    MAX_LBA=$(($TOTAL_SIZE/$BLOCK_SIZE))

    # status / physical drive (bit 7 set: active / bootable, old MBRs only accept 80h), 00h: inactive, 01h–7Fh: invalid)
    echo -n "00"
    # CHS address of first absolute sector in partition. The format is described by 3 bytes.
    lba_to_chs 0
    # Partition type = FAT32 with CHS addressing
    echo -n "0b"
    # CHS address of last absolute sector in partition. The format is described by 3 bytes.
    if [[ $MAX_LBA -ge $((1024*$HPC*$SPT-1)) ]]; then
        # From https://en.wikipedia.org/wiki/Master_boot_record#Partition_table_entries
        # When a CHS address is too large to fit into these fields, the tuple (1023, 254, 63) is typically used today
        echo -n "feffff"
    else
        # '-1' yields last usable sector
        lba_to_chs $(($MAX_LBA-1))
    fi

    # LBA of first absolute sector in the partition.
    # This is the magic of what we're trying to accomplish.  We need this partition to be whole-disk.
    ntohl 0
    # Number of sectors in partition.
    # Note lack of '-1' here, as we're interested in number of sectors.
    if [[ $MAX_LBA -ge $(((2**32)-1)) ]]; then
        # Sadly, MBR type 0x0b caps this at a 32-bit value.
        # Using a different partition type wouldn't actually help, as UDF 2.01 itself has a limit of 2^32 blocks
        echo -n "ffffffff"
    else
        ntohl $MAX_LBA
    fi
}


###############################################################################
# test dependencies
###############################################################################

echo "[+] Testing dependencies..."
if [[ ! -x $(which cat) ]] ||
   [[ ! -x $(which grep) ]] ||
   [[ ! -x $(which egrep) ]] ||
   [[ ! -x $(which mount) ]] ||
   [[ ! -x $(which test) ]] ||
   [[ ! -x $(which true) ]] ||
   [[ ! -x $(which false) ]] ||
   [[ ! -x $(which awk) ]] ||
   [[ ! -x $(which printf) ]] ||
   [[ ! -x $(which sed) ]] ||
   [[ ! -x $(which dd) ]] ||
   [[ ! -x $(which xxd) ]]; then
    echo "[-] Dependencies unmet.  Please verify that the following are installed, executable, and in the PATH:  cat, grep, egrep, mount, test, true, false, awk, printf, sed, dd, xxd" >&2
    exit 1
fi


# ensure have required drive listing tool
echo -n "[+] Looking for drive listing tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_BLOCKDEV=$(which blockdev) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_DISKUTIL=$(which diskutil) || true
if [[ -x "$TOOL_BLOCKDEV" ]]; then
    TOOL_DRIVE_LISTING=$TOOL_BLOCKDEV
elif [[ -x "$TOOL_DISKUTIL" ]]; then
    TOOL_DRIVE_LISTING=$TOOL_DISKUTIL
else
    echo
    echo "[-] Dependencies unmet.  Please verify that at least one of the following are installed, executable, and in the PATH:  blockdev, diskutil" >&2
    exit 1
fi
echo " using $TOOL_DRIVE_LISTING"


# ensure have required unmount tool
echo -n "[+] Looking for unmount tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_UMOUNT=$(which umount) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_DISKUTIL=$(which diskutil) || true
# prefer 'diskutil' if available, as it's required on OS X (even if 'umount' is present)
if [[ -x "$TOOL_DISKUTIL" ]]; then
    TOOL_UNMOUNT=$TOOL_DISKUTIL
elif [[ -x "$TOOL_UMOUNT" ]]; then
    TOOL_UNMOUNT=$TOOL_UMOUNT
else
    echo
    echo "[-] Dependencies unmet.  Please verify that at least one of the following are installed, executable, and in the PATH:  umount, diskutil" >&2
    exit 1
fi
echo " using $TOOL_UNMOUNT"


# ensure have required UDF tool
echo -n "[+] Looking for UDF tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_MKUDFFS=$(which mkudffs) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_NEWFS_UDF=$(which newfs_udf) || true
if [[ -x "$TOOL_MKUDFFS" ]]; then
    TOOL_UDF=$TOOL_MKUDFFS
elif [[ -x "$TOOL_NEWFS_UDF" ]]; then
    TOOL_UDF=$TOOL_NEWFS_UDF
else
    echo
    echo "[-] Dependencies unmet.  Please verify that at least one of the following are installed, executable, and in the PATH:  mkudffs, newfs_udf" >&2
    exit 1
fi
echo " using $TOOL_UDF"


###############################################################################
# validate arguments
###############################################################################

echo "[+] Validating arguments..."

# require exactly 2 arguments
if [[ $# -ne 2 ]]; then
    print_usage
    exit 1
fi

# setup variables for arguments
DEVICE=$1
LABEL=$2

# verify that DEVICE doesn't have partition number on end, or that it's in OS X format
(echo "$DEVICE" | egrep -q '^([hs]d[a-z]|disk[0-9]+)$') || (echo "[-] <device> is of invalid form" >&2 && false)

# verify this is a device, not just a file
# `true` is so that a failure here doesn't cause entire script to exit prematurely
mount /dev/$DEVICE 2>/dev/null || true
[[ -b /dev/$DEVICE ]] || (echo "[-] /dev/$DEVICE either doesn't exist or is not block special" >&2 && false)


###############################################################################
# verify with user
###############################################################################

echo "[+] Gathering drive information..."
if [[ $TOOL_DRIVE_LISTING = $TOOL_BLOCKDEV ]]; then
    sudo blkid -c /dev/null /dev/$DEVICE || true
    cat /sys/block/$DEVICE/device/model
    sudo blockdev --report | egrep "(Device|$DEVICE)"
elif [[ $TOOL_DRIVE_LISTING = $TOOL_DISKUTIL ]]; then
    diskutil list $DEVICE
else
    echo "[-] Internal error 1" >&2
    exit 1
fi

# give the user a chance to realize his/her mistake
echo "The above-listed drive (and partitions, if any) will be completely erased."
# TODO add '-f' command-line option to bypass this interactive step
read -p "Type 'yes' if this is what you intend:  " YES_CASE
YES=$(echo $YES_CASE | tr '[:upper:]' '[:lower:]')
if [[ $YES != "yes" ]]; then
    echo "[-] Exiting without changes to /dev/$DEVICE." >&2
    exit 1
fi


###############################################################################
# gather information - total size
###############################################################################

echo "[+] Detecting total size..."
if [[ $TOOL_DRIVE_LISTING = $TOOL_BLOCKDEV ]]; then
    TOTAL_SIZE=$(sudo blockdev --getsize64 /dev/$DEVICE)
elif [[ -x $TOOL_DISKUTIL ]]; then
    TOTAL_SIZE=$(diskutil info $DEVICE | grep -i 'Total Size' | awk -F ':' '{print $2}' | egrep -oi '\([0-9]+ B' | sed 's/[^0-9]//g')
else
    echo "[-] Cannot detect total size" >&2
    exit 1
fi
echo "[*] Using total size of $TOTAL_SIZE"

# validate that $TOTAL_SIZE is numeric > 0
echo "[+] Validating detected total size..."
(echo "$TOTAL_SIZE" | egrep -q '^[0-9]+$') || (echo "[-] Could not detect valid total size.  Exiting without changes to /dev/$DEVICE." >&2 && false)
[[ $TOTAL_SIZE -gt 0 ]] || (echo "[-] Could not detect valid total size.  Exiting without changes to /dev/$DEVICE." >&2 && false)


###############################################################################
# gather information - physical block size
###############################################################################

echo "[+] Detecting physical block size..."
if [[ $TOOL_DRIVE_LISTING = $TOOL_BLOCKDEV ]]; then
    BLOCK_SIZE=$(sudo blockdev --getpbsz /dev/$DEVICE)
elif [[ -x $TOOL_DISKUTIL ]]; then
    BLOCK_SIZE=$(diskutil info $DEVICE | grep -i 'Device Block Size' | awk -F ':' '{print $2}' | awk '{print $1}')
else
    echo "[-] Cannot detect physical block size" >&2
    exit 1
fi
echo "[*] Using block size of $BLOCK_SIZE"

# validate that $BLOCK_SIZE is numeric > 0
echo "[+] Validating detected block size..."
(echo "$BLOCK_SIZE" | egrep -q '^[0-9]+$') || (echo "[-] Could not detect valid block size.  Exiting without changes to /dev/$DEVICE." >&2 && false)
[[ $BLOCK_SIZE -gt 0 ]] || (echo "[-] Could not detect valid block size.  Exiting without changes to /dev/$DEVICE." >&2 && false)


###############################################################################
# unmount drive (if mounted)
###############################################################################

echo "[+] Unmounting drive..."
if [[ $TOOL_UNMOUNT = $TOOL_UMOUNT ]]; then
    # `true` is so that a failure here doesn't cause entire script to exit prematurely
    sudo umount /dev/$DEVICE || true
elif [[ $TOOL_UNMOUNT = $TOOL_DISKUTIL ]]; then
    # `true` is so that a failure here doesn't cause entire script to exit prematurely
    sudo diskutil unmountDisk /dev/$DEVICE || true
else
    echo "[-] Internal error 2" >&2
    exit 1
fi


###############################################################################
# zero out partition table
###############################################################################

echo "[+] Zeroing out any existing partition table on drive..."
# 4096 was arbitrarily chosen to be "big enough" to delete first chunk of disk
sudo dd if=/dev/zero of=/dev/$DEVICE bs=$BLOCK_SIZE count=4096


###############################################################################
# format drive
###############################################################################

echo "[+] Formatting /dev/$DEVICE ..."
if [[ $TOOL_UDF = $TOOL_MKUDFFS ]]; then
    # --blocksize  - the size of blocks in bytes. should be the same as the drive's physical block size.
    # --udfrev     - the udf revision to use.  2.01 is the latest revision available that supports writing in Linux.
    # --lvid       - logical volume identifier
    # --vid        - volume identifier
    # --media-type - "hd" type covers both hard drives and USB drives
    # --utf8       - encode file names in UTF8
    (sudo time sh -c "mkudffs --blocksize=$BLOCK_SIZE --udfrev=0x0201 --lvid="$LABEL" --vid="$LABEL" --media-type=hd --utf8 /dev/$DEVICE) || (echo "[-] Format failed!" >&2 && false)"
elif [[ $TOOL_UDF = $TOOL_NEWFS_UDF ]]; then
    # -b    - the size of blocks in bytes. should be the same as the drive's physical block size.
    # -m    - "blk" type covers both hard drives and USB drives
    # -t    - "overwrite" access type
    # -r    - the udf revision to use.  2.01 is the latest revision available that supports writing in Linux.
    # -v    - volume identifier
    # --enc - encode volume name in UTF8
    (sudo time sh -c "newfs_udf -b $BLOCK_SIZE -m blk -t ow -r 2.01 -v "$LABEL" --enc utf8 /dev/$DEVICE) || (echo "[-] Format failed!" >&2 && false)"
else
    echo "[-] Internal error 3" >&2
    exit 1
fi


###############################################################################
# write fake MBR (for added compatibility on Windows)
###############################################################################

echo "[+] Writing fake MBR..."
# first block has already been zero'd.  start by writing the (only) partition entry at its correct offset.
entire_disk_partition_entry $TOTAL_SIZE $BLOCK_SIZE | xxd -r -p | sudo dd of=/dev/$DEVICE bs=1 seek=446 count=16
# Boot signature at the end of the block
echo -n 55aa | xxd -r -p | sudo dd of=/dev/$DEVICE bs=1 seek=510 count=2


###############################################################################
# report status
###############################################################################

# following call to blkid sometimes exits with failure, even though the drive is formatted properly.
# `true` is so that a failure here doesn't cause entire script to exit prematurely
SUMMARY=$(sudo blkid -c /dev/null /dev/$DEVICE 2>/dev/null) || true
echo "[*] Successfully formatted $SUMMARY"

# TODO find a way to auto-mount (`sudo mount -a` doesn't work).  in the meantime...
echo "Please disconnect/reconnect your drive now."
