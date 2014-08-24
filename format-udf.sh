#!/bin/bash

# format-udf.sh
#
# Bash script to format a block drive (hard drive or Flash drive) in UDF format.  The output is a drive that can be used for reading/writing across multiple operating system families:  Windows, OS X, and Linux.  This script should be capable of running in OS X or in Linux.
#
# Version 1.0.0
#
# Copyright (C) 2014 Jonathan Elchison <JElchison@gmail.com>
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

#######################################
# Prints script usage to stderr
# Arguments:
#   None
# Returns:
#   None
#######################################
print_usage() {
    echo "Usage:    $0 <drive> <label>" >&2
    echo "Example:  $0 sda \"My External Drive\"" >&2
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
   [[ ! -x $(which dd) ]]; then
    echo "[-] Dependencies unmet.  Please verify that the following are installed, executable, and in the PATH:  cat, grep, egrep, mount, test, true, false, awk, dd" >&2
    exit 1
fi


# ensure have required drive listing tool
echo -n "[+] Looking for drive listing tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_LSHW=$(which lshw) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_DISKUTIL=$(which diskutil) || true
if [[ ! -x $TOOL_LSHW ]] && [[ ! -x $TOOL_DISKUTIL ]]; then
    echo
    echo "[-] Dependencies unmet.  Please verify that at least one of the following are installed, executable, and in the PATH:  lshw, diskutil" >&2
    exit 1
fi
# select drive listing tool
if [[ -n "$TOOL_LSHW" ]]; then
    TOOL_DRIVE_LISTING=$TOOL_LSHW
elif [[ -n "$TOOL_DISKUTIL" ]]; then
    TOOL_DRIVE_LISTING=$TOOL_DISKUTIL
else
    echo
    echo "[-] Internal error 1" >&2
    exit 1
fi
echo " using $TOOL_DRIVE_LISTING"


# ensure have required unmount tool
echo -n "[+] Looking for unmount tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_UMOUNT=$(which umount) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_DISKUTIL=$(which diskutil) || true
if [[ ! -x $TOOL_UMOUNT ]] && [[ ! -x $TOOL_DISKUTIL ]]; then
    echo
    echo "[-] Dependencies unmet.  Please verify that at least one of the following are installed, executable, and in the PATH:  umount, diskutil" >&2
    exit 1
fi
# select unmount tool.  prefer 'diskutil' if available, as it's required on OS X (even if 'umount' is present).
if [[ -n "$TOOL_DISKUTIL" ]]; then
    TOOL_UNMOUNT=$TOOL_DISKUTIL
elif [[ -n "$TOOL_UMOUNT" ]]; then
    TOOL_UNMOUNT=$TOOL_UMOUNT
else
    echo
    echo "[-] Internal error 2" >&2
    exit 1
fi
echo " using $TOOL_UNMOUNT"


# ensure have required UDF tool
echo -n "[+] Looking for UDF tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_MKUDFFS=$(which mkudffs) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_NEWFS_UDF=$(which newfs_udf) || true
if [[ ! -x $TOOL_MKUDFFS ]] && [[ ! -x $TOOL_NEWFS_UDF ]]; then
    echo
    echo "[-] Dependencies unmet.  Please verify that at least one of the following are installed, executable, and in the PATH:  mkudffs, newfs_udf" >&2
    exit 1
fi
# select UDF tool
if [[ -n "$TOOL_MKUDFFS" ]]; then
    TOOL_UDF=$TOOL_MKUDFFS
elif [[ -n "$TOOL_NEWFS_UDF" ]]; then
    TOOL_UDF=$TOOL_NEWFS_UDF
else
    echo
    echo "[-] Internal error 3" >&2
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
# TODO not sure why the following is required on bash 3.2.51(1) on OS X (doesn't exit with `false` even with 'set -e')
RET=$?; if [[ $RET -ne 0 ]]; then
    exit $RET
fi

# verify this is a device, not just a file
# `true` is so that a failure to unmount doesn't cause entire script to exit prematurely
mount /dev/$DEVICE 2>/dev/null || true
(test -b /dev/$DEVICE) || (echo "[-] <device> either doesn't exists or is not block special" >&2 && false)
# TODO not sure why the following is required on bash 3.2.51(1) on OS X (doesn't exit with `false` even with 'set -e')
RET=$?; if [[ $RET -ne 0 ]]; then
    exit $RET
fi


###############################################################################
# verify with user
###############################################################################

echo "[+] Gathering drive information..."
if [[ $TOOL_DRIVE_LISTING = $TOOL_LSHW ]]; then
    sudo lshw -short -quiet | grep /dev/$DEVICE
elif [[ $TOOL_DRIVE_LISTING = $TOOL_DISKUTIL ]]; then
    diskutil list $DEVICE
else
    echo "[-] Internal error 4" >&2
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
# gather information
###############################################################################

echo "[+] Detecting native sector size..."
SECTOR_PATH=/sys/block/$DEVICE/queue/hw_sector_size
if [[ -r $SECTOR_PATH ]]; then
    SECTORSIZE=$(cat /sys/block/$DEVICE/queue/hw_sector_size)
elif [[ -x $TOOL_DISKUTIL ]]; then
    SECTORSIZE=$(diskutil info $DEVICE | grep -i 'Block Size' | awk -F ':' '{print $2}' | awk '{print $1}')
else
    echo "[-] Cannot detect native sector size" >&2
    exit 1
fi

# validate that $SECTORSIZE is numeric > 0
echo "[+] Validating detected sector size..."
(echo "$SECTORSIZE" | egrep -q '^[0-9]+$') || (echo "[-] Could not detect valid sector size.  Exiting without changes to /dev/$DEVICE." >&2 && false)
# TODO not sure why the following is required on bash 3.2.51(1) on OS X (doesn't exit with `false` even with 'set -e')
RET=$?; if [[ $RET -ne 0 ]]; then
    exit $RET
fi
if [[ $SECTORSIZE -le 0 ]]; then
    echo "[-] Could not detect valid sector size.  Exiting without changes to /dev/$DEVICE." >&2
    exit 1
fi


###############################################################################
# unmount drive (if mounted)
###############################################################################

echo "[+] Unmounting drive..."
if [[ $TOOL_UNMOUNT = $TOOL_UMOUNT ]]; then
    # `true` is so that a failure to unmount doesn't cause entire script to exit prematurely
    sudo umount /dev/$DEVICE || true
elif [[ $TOOL_UNMOUNT = $TOOL_DISKUTIL ]]; then
    # `true` is so that a failure to unmount doesn't cause entire script to exit prematurely
    sudo diskutil unmount /dev/$DEVICE || true
else
    echo "[-] Internal error 5" >&2
    exit 1
fi


###############################################################################
# zero partition table
###############################################################################

echo "[+] Zeroing out any existing partition table on drive..."
# 4096 was arbitratily chosen to be "big enough" to delete first chunk of disk
sudo dd if=/dev/zero of=/dev/$DEVICE bs=$SECTORSIZE count=4096

# no need to re-partition, UDF explicitly doesn't use a partition table.


###############################################################################
# format drive
###############################################################################

echo "[+] Formatting /dev/$DEVICE ..."
if [[ $TOOL_UDF = $TOOL_MKUDFFS ]]; then
    # --blocksize  - the size of blocks in bytes. should be the same as the drive's native sector size.
    # --udfrev     - the udf revision to use.  2.01 is the latest revision available that supports writing in Linux.
    # --lvid       - logical volume identifier
    # --vid        - volume identifier
    # --media-type - "hd" type covers both hard drives and USB drives
    # --utf8       - encode file names in UTF8
    (sudo mkudffs --blocksize=$SECTORSIZE --udfrev=0x0201 --lvid="$LABEL" --vid="$LABEL" --media-type=hd --utf8 /dev/$DEVICE) || (echo "[-] Format failed!" >&2 && false)
    # TODO not sure why the following is required on bash 3.2.51(1) on OS X (doesn't exit with `false` even with 'set -e')
    RET=$?; if [[ $RET -ne 0 ]]; then
        exit $RET
    fi
elif [[ $TOOL_UDF = $TOOL_NEWFS_UDF ]]; then
    # -b    - the size of blocks in bytes. should be the same as the drive's native sector size.
    # -m    - "blk" type covers both hard drives and USB drives
    # -t    - "overwrite" access type
    # -r    - the udf revision to use.  2.01 is the latest revision available that supports writing in Linux.
    # -v    - volume identifier
    # --enc - encode volume name in UTF8
    (sudo newfs_udf -b $SECTORSIZE -m blk -t ow -r 2.01 -v "$LABEL" --enc utf8 /dev/$DEVICE) || (echo "[-] Format failed!" >&2 && false)
    # TODO not sure why the following is required on bash 3.2.51(1) on OS X (doesn't exit with `false` even with 'set -e')
    RET=$?; if [[ $RET -ne 0 ]]; then
        exit $RET
    fi
else
    echo "[-] Internal error 6" >&2
    exit 1
fi


###############################################################################
# report status
###############################################################################

# following call to blkid sometimes exits with failure, even though the drive is formatted properly.
# `true` is so that a failure here doesn't cause entire script to exit prematurely
SUMMARY=$(sudo blkid -c /dev/null /dev/$DEVICE 2>/dev/null) || true
echo "[*] Successfully formatted $SUMMARY"

# TODO find a way to auto-mount (`sudo mount -a` doesn't work).  in the meantime...
echo "Please disconnect/reconnect your drive now."
