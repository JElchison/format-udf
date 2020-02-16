#!/bin/bash

# format-udf.sh
#
# Bash script to format a block device (hard drive or Flash drive) in UDF. The output is a drive that can be used for reading/writing across multiple operating system families: Windows, macOS, and Linux. This script should be capable of running in macOS or in Linux.
#
# Copyright (C) 2020 Jonathan Elchison <JElchison@gmail.com>
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


# handle following scenarios:
#   * unprivileged user (i.e. not root, sudo not used)
#   * privileged user (i.e. not root, sudo used)
#   * root user (i.e. sudo not used)
SUDO=''
if [[ $(id -u) -ne 0 ]]; then
    # verify that 'sudo' is present before assuming we can use it
    if ! hash sudo 2>/dev/null; then
        echo "[-] Dependencies unmet.  Please verify that 'sudo' is installed, executable, and in the PATH." >&2
        echo "Alternatively, you may also re-run this script as root." >&2
        exit 1
    fi

    SUDO='sudo'
fi


###############################################################################
# constants
###############################################################################

# version of this script
VERSION=1.7.1
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
    cat <<EOF >&2
Bash script to format a block device (hard drive or Flash drive) in UDF.
The output is a drive that can be used for reading/writing across multiple
operating system families: Windows, macOS, and Linux.
This script should be capable of running in macOS or in Linux.

Usage:  $0 [-b BLOCK_SIZE] [-f] [-p PARTITION_TYPE] [-w WIPE_METHOD] device label
        $0 -v
        $0 -h

    -b BLOCK_SIZE
        Block size to be used during format operation.
        If absent, defaults to value reported by blockdev/diskutil.
        This is an expert-only option.  Please consult the README for details.

    -f
        Forces non-interactive mode.  Useful for scripting.
        Please use with caution, as no user confirmation is given.

    -h
        Display help information and exit.

    -p PARTITION_TYPE
        Partition type to set during format operation.
        Currently supported types include:  mbr, none
            mbr  - Master boot record (default)
            none - Do not modify partitions
        If absent, defaults to 'mbr'.
        See also:
            https://github.com/JElchison/format-udf#why

    -v
        Display version information and exit.

    -w WIPE_METHOD
        Wipe method to be used before format operation.
        Currently supported types include:  quick, zero, scrub
            quick - Quick method (default)
            zero  - Write zeros to the entire device
            scrub - Iteratively writes patterns on device
                    to make retrieving the data more difficult.
                    Requires 'scrub' to be executable and in the PATH.
                    See also http://linux.die.net/man/1/scrub
        If absent, defaults to 'quick'.
        Note:  'zero' and 'scrub' methods will take a long time.

    device
        Device to format.  Examples:
          * /dev/sdx   (Linux, where 'x' is a letter) or
          * /dev/diskN (macOS, where 'N' is a number)

    label
        Label to apply to formatted device.

Example:  $0 /dev/sdg "My UDF External Drive"
EOF
}


# Prints hex representation of CHS (cylinder-head-sector) to stdout
# Arguments:
#   Logical block address (LBA)
# Returns:
#   None
function lba_to_chs {
    LBA=$1
    C=$(((LBA/(HPC*SPT)) % (2**10)))
    C_HI=$(((C>>8) % (2**2)))
    C_LO=$((C % (2**8)))
    H=$((((LBA/SPT) % HPC) % (2**8)))
    S=$((((LBA % SPT) + 1) % (2**6)))
    printf "%02x%02x%02x" $H $(((C_HI<<6)|S)) $C_LO
}


# Prints hex representation of value in host byte order
# Arguments:
#   32-bit integer
# Returns:
#   None
function ntohl {
    if sed --version &> /dev/null; then
        # this box has GNU sed ('-r' for extended regex)
        printf "%08x" "$1" | tail -c 8 | sed -r 's/(..)/\1 /g' | awk '{print $4 $3 $2 $1}'
    else
        # this machine must have BSD sed ('-E' for extended regex)
        printf "%08x" "$1" | tail -c 8 | sed -E 's/(..)/\1 /g' | awk '{print $4 $3 $2 $1}'
    fi
}


# Prints hex representation of entire-disk partition entry.  Reference:
#   https://en.wikipedia.org/wiki/Master_boot_record
#   https://en.wikipedia.org/wiki/Cylinder-head-sector
#   https://en.wikipedia.org/wiki/Logical_block_addressing
# Arguments:
#   Device
# Returns:
#   None
function entire_disk_partition_entry {
    TOTAL_SIZE=$1
    LOGICAL_BLOCK_SIZE=$2
    MAX_LBA=$((TOTAL_SIZE/LOGICAL_BLOCK_SIZE))

    # status / physical drive (bit 7 set: active / bootable, old MBRs only accept 80h), 00h: inactive, 01h–7Fh: invalid)
    echo -n "00"
    # CHS address of first absolute sector in partition. The format is described by 3 bytes.
    lba_to_chs 0
    # Partition type = FAT32 with CHS addressing
    echo -n "0b"
    # CHS address of last absolute sector in partition. The format is described by 3 bytes.
    if [[ $MAX_LBA -ge $((1024*HPC*SPT-1)) ]]; then
        # From https://en.wikipedia.org/wiki/Master_boot_record#Partition_table_entries
        # When a CHS address is too large to fit into these fields, the tuple (1023, 254, 63) is typically used today
        echo -n "feffff"
    else
        # '-1' yields last usable sector
        lba_to_chs $((MAX_LBA-1))
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


# Prints message assuring user that $DEVICE_PATH has not been changed
# Arguments:
#   Device
# Returns:
#   None
function exit_with_no_changes {
    if [[ -n "$DEVICE_PATH" ]]; then
        echo "[*] Exiting without changes to $DEVICE_PATH"
    fi
}


###############################################################################
# set default options
###############################################################################

ARG_BLOCK_SIZE=
FORCE=
PARTITION_TYPE=mbr
WIPE_METHOD=quick

# reset in case getopts has been used previously in the shell
OPTIND=1


###############################################################################
# parse options
###############################################################################

while getopts ":b:fp:w:vh" opt; do
    case $opt in
        b)
            ARG_BLOCK_SIZE="$OPTARG"
            # no need to validate this here, as BLOCK_SIZE is validated below (before anything destructive happens)
            ;;
        f)
            FORCE=1
            ;;
        p)
            PARTITION_TYPE="$OPTARG"
            if [[ "$PARTITION_TYPE" != "mbr" ]] &&
               [[ "$PARTITION_TYPE" != "none" ]]; then
                echo "[-] Invalid partition type: $PARTITION_TYPE" >&2
                print_usage
                exit 1
            fi
            ;;
        w)
            WIPE_METHOD="$OPTARG"
            if [[ "$WIPE_METHOD" != "quick" ]] &&
               [[ "$WIPE_METHOD" != "zero" ]] &&
               [[ "$WIPE_METHOD" != "scrub" ]]; then
                echo "[-] Invalid wipe method: $WIPE_METHOD" >&2
                print_usage
                exit 1
            fi
            if [[ "$WIPE_METHOD" = "scrub" ]]; then
                if ! hash scrub 2>/dev/null; then
                    echo "[-] Dependencies unmet.  Please verify that the following are installed, executable, and in the PATH:  scrub" >&2
                    exit 1
                fi
            fi
            ;;
        v)
            echo "format-udf $VERSION"
            echo "https://github.com/JElchison/format-udf"
            echo "Copyright (C) 2018 Jonathan Elchison <JElchison@gmail.com>"
            exit 0
            ;;
        h)
            print_usage
            exit 0
            ;;
        \?)
            echo "[-] Invalid option '-$OPTARG'" >&2
            print_usage
            exit 1
            ;;
        :)
            echo "[-] Option '-$OPTARG' requires an argument" >&2
            print_usage
            exit 1
            ;;
    esac
done

shift $((OPTIND-1))
([[ "$1" = "--" ]] 2>/dev/null && shift) || true


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
DEVICE_ARG=$1
LABEL=$2

# if DEVICE_ARG doesn't appear to be an absolute path, prepend '/dev/' prefix
if echo "$DEVICE_ARG" | grep -q '^/'; then
    DEVICE_PATH=$DEVICE_ARG
else
    DEVICE_PATH=/dev/$DEVICE_ARG
fi

# verify this is a device, not just a file
# `true` is so that a failure here doesn't cause entire script to exit prematurely
mount "$DEVICE_PATH" 2>/dev/null || true
[[ -b "$DEVICE_PATH" ]] || (echo "[-] $DEVICE_PATH either doesn't exist or is not block special" >&2; false)

# resolve device symlinks.  this permits use on virtual block devices with Linux device mapper.
KERNEL_NAME=$(uname -s)
if [[ "$KERNEL_NAME" = "Linux" ]]; then
    KDEVICE_PATH=$(readlink -f "$DEVICE_PATH")
elif [[ "$KERNEL_NAME" = "Darwin" ]]; then
    KDEVICE_PATH=$(readlink "$DEVICE_PATH")
else
    echo "[-] Internal error 1" >&2
    exit 1
fi

# verify this is a device, not just a file
# `true` is so that a failure here doesn't cause entire script to exit prematurely
mount "$KDEVICE_PATH" 2>/dev/null || true
[[ -b "$KDEVICE_PATH" ]] || (echo "[-] $KDEVICE_PATH either doesn't exist or is not block special" >&2; false)

# remove '/dev/' prefix for use in this script
KDEVICE=${KDEVICE_PATH#/dev/}

# provide assuring exit message when exiting before making changes to the drive
trap exit_with_no_changes EXIT


###############################################################################
# test dependencies
###############################################################################

echo "[+] Testing dependencies..."
if ! hash cat 2>/dev/null ||
   ! hash grep 2>/dev/null ||
   ! hash mount 2>/dev/null ||
   ! hash test 2>/dev/null ||
   ! hash true 2>/dev/null ||
   ! hash false 2>/dev/null ||
   ! hash awk 2>/dev/null ||
   ! hash printf 2>/dev/null ||
   ! hash sed 2>/dev/null ||
   ! hash tr 2>/dev/null ||
   ! hash dd 2>/dev/null ||
   ! hash xxd 2>/dev/null; then
    echo "[-] Dependencies unmet.  Please verify that the following are installed, executable, and in the PATH:  cat, grep, mount, test, true, false, awk, printf, sed, tr, dd, xxd" >&2
    exit 1
fi


# ensure have required drive detail tool
echo -n "[+] Looking for drive detail tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_BLOCKDEV=$(command -v blockdev 2>/dev/null) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_IOREG=$(command -v ioreg 2>/dev/null) || true
if [[ -x "$TOOL_BLOCKDEV" ]]; then
    TOOL_DRIVE_DETAIL=$TOOL_BLOCKDEV
elif [[ -x "$TOOL_IOREG" ]]; then
    TOOL_DRIVE_DETAIL=$TOOL_IOREG
else
    echo
    echo "[-] Dependencies unmet.  Please verify that at least one of the following are installed, executable, and in the PATH:  blockdev, ioreg" >&2
    exit 1
fi
echo " using $TOOL_DRIVE_DETAIL"


# ensure have required drive listing tool
echo -n "[+] Looking for drive listing tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_BLOCKDEV=$(command -v blockdev 2>/dev/null) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_DISKUTIL=$(command -v diskutil 2>/dev/null) || true
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


# ensure have required drive info tool
echo -n "[+] Looking for drive info tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_LSBLK=$(command -v lsblk 2>/dev/null) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_DISKUTIL=$(command -v diskutil 2>/dev/null) || true
if [[ -x "$TOOL_LSBLK" ]]; then
    TOOL_DRIVE_INFO=$TOOL_LSBLK
elif [[ -x "$TOOL_DISKUTIL" ]]; then
    TOOL_DRIVE_INFO=$TOOL_DISKUTIL
else
    echo
    echo "[-] Dependencies unmet.  Please verify that at least one of the following are installed, executable, and in the PATH:  lsblk, diskutil" >&2
    exit 1
fi
echo " using $TOOL_DRIVE_INFO"


# ensure have drive summary tool
echo -n "[+] Looking for drive summary tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_BLKID=$(command -v blkid 2>/dev/null) || true
if [[ -x "$TOOL_BLKID" ]]; then
    TOOL_DRIVE_SUMMARY=$TOOL_BLKID
    echo " using $TOOL_DRIVE_SUMMARY"
else
    TOOL_DRIVE_SUMMARY=
    echo " using (none)"
fi


# ensure have required unmount tool
echo -n "[+] Looking for unmount tool..."
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_UMOUNT=$(command -v umount 2>/dev/null) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_DISKUTIL=$(command -v diskutil 2>/dev/null) || true
# prefer 'diskutil' if available, as it's required on macOS (even if 'umount' is present)
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
TOOL_MKUDFFS=$(command -v mkudffs 2>/dev/null) || true
# `true` is so that a failure here doesn't cause entire script to exit prematurely
TOOL_NEWFS_UDF=$(command -v newfs_udf 2>/dev/null) || true
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
# determine whether device is part or whole
###############################################################################

if [[ $TOOL_DRIVE_INFO = "$TOOL_LSBLK" ]]; then
    IS_WHOLE=$(lsblk -alo KNAME,TYPE | grep "$KDEVICE" | awk '{print $2}' | grep -Eiq '(loop|disk)' && echo Yes || echo No)
elif [[ $TOOL_DRIVE_INFO = "$TOOL_DISKUTIL" ]]; then
    IS_WHOLE=$(diskutil info "$KDEVICE_PATH" | grep -i '^[ \t]*Whole:' | awk '{print $2}')
else
    echo "[-] Internal error 2" >&2
    exit 1
fi

# is user attempting to format part?
if [[ "${IS_WHOLE,,}" = "no" ]]; then
    if [[ "$PARTITION_TYPE" != "none" ]]; then
        echo "[-] You are attempting to format a single partition (as opposed to entire device)." >&2
        echo "[-] Partition type '$PARTITION_TYPE' incompatible with single partition formatting." >&2
        echo "[-] Please specify an entire device or partition type of 'none'." >&2
        exit 1
    fi

    echo "You are attempting to format a single partition (as opposed to entire device)."
    echo "For maximal compatibility, the recommendation is to format the entire device."
    echo "If you continue, the resultant UDF partition will not be recognized on macOS."

    if [[ -z $FORCE ]]; then
        read -rp "Type 'yes' if you would like to continue anyway:  " YES_CASE
        YES=$(echo "$YES_CASE" | tr '[:upper:]' '[:lower:]')
        if [[ $YES != "yes" ]]; then
            exit 1
        fi
    fi
fi


###############################################################################
# gather information - logical block size
###############################################################################

echo "[+] Detecting logical block size..."
if [[ $TOOL_DRIVE_LISTING = "$TOOL_BLOCKDEV" ]]; then
    LOGICAL_BLOCK_SIZE=$($SUDO blockdev --getss "$KDEVICE_PATH")
elif [[ $TOOL_DRIVE_LISTING = "$TOOL_DISKUTIL" ]]; then
    LOGICAL_BLOCK_SIZE=$(diskutil info "$KDEVICE_PATH" | grep -i 'Device Block Size' | awk -F ':' '{print $2}' | awk '{print $1}')
else
    echo "[-] Internal error 3" >&2
    exit 1
fi

echo "[*] Detected logical block size of $LOGICAL_BLOCK_SIZE"

# validate that $LOGICAL_BLOCK_SIZE is numeric > 0 and multiple of 512
echo "[+] Validating detected logical block size..."
(echo "$LOGICAL_BLOCK_SIZE" | grep -Eq '^[0-9]+$') || (echo "[-] Could not detect logical block size" >&2; false)
[[ $LOGICAL_BLOCK_SIZE -gt 0 ]] || (echo "[-] Could not detect logical block size" >&2; false)
[[ $((LOGICAL_BLOCK_SIZE % 512)) -eq 0 ]] || (echo "[-] Could not detect logical block size" >&2; false)


###############################################################################
# gather information - physical block size
###############################################################################

echo "[+] Detecting physical block size..."
if [[ $TOOL_DRIVE_DETAIL = "$TOOL_BLOCKDEV" ]]; then
    PHYSICAL_BLOCK_SIZE=$($SUDO blockdev --getpbsz "$KDEVICE_PATH")
elif [[ $TOOL_DRIVE_DETAIL = "$TOOL_IOREG" ]]; then
    # TODO - the 'Physical Block Size' item isn't always present.  find a more reliable method on macOS.
    # `true` is so that a failure here doesn't cause entire script to exit prematurely
    PHYSICAL_BLOCK_SIZE=$(ioreg -c IOMedia -r -d 1 | tr '\n' '\0' | grep -Eao "\{\$[^\+]*$KDEVICE.*?    \}\$" | tr '\0' '\n' | grep 'Physical Block Size' | awk '{print $5}') || true
else
    echo "[-] Internal error 4" >&2
    exit 1
fi

if [[ -n $PHYSICAL_BLOCK_SIZE ]]; then
    echo "[*] Detected physical block size of $PHYSICAL_BLOCK_SIZE"

    # validate that $PHYSICAL_BLOCK_SIZE is numeric > 0 and multiple of 512
    echo "[+] Validating detected physical block size..."
    (echo "$PHYSICAL_BLOCK_SIZE" | grep -Eq '^[0-9]+$') || (echo "[-] Could not detect physical block size" >&2; false)
    [[ $PHYSICAL_BLOCK_SIZE -gt 0 ]] || (echo "[-] Could not detect physical block size" >&2; false)
    [[ $((PHYSICAL_BLOCK_SIZE % 512)) -eq 0 ]] || (echo "[-] Could not detect physical block size" >&2; false)


    ###############################################################################
    # check for Advanced Format drive
    ###############################################################################

    if [[ $LOGICAL_BLOCK_SIZE -ne 512 ]] || [[ $PHYSICAL_BLOCK_SIZE -ne 512 ]]; then
        echo "The device you have selected is an Advanced Format drive, with a logical block size"
        echo "of $LOGICAL_BLOCK_SIZE bytes and physical block size of $PHYSICAL_BLOCK_SIZE bytes."
        if [[ $LOGICAL_BLOCK_SIZE -eq 512 ]] && [[ $PHYSICAL_BLOCK_SIZE -eq 4096 ]]; then
            echo "This device is an '512 emulation' (512e) drive."
        elif [[ $LOGICAL_BLOCK_SIZE -eq 4096 ]] && [[ $PHYSICAL_BLOCK_SIZE -eq 4096 ]]; then
            echo "This device is an '4K native' (4Kn) drive."
        fi
        echo "As such, this drive will not be as compatible across operating systems as a standard"
        echo "drive having a logical block size of 512 bytes and a physical block size of 512 bytes."
        echo "For example, this drive will not be usable for read or write on Windows XP."
        echo "Please see the format-udf README for more information/limitations."

        if [[ -z $FORCE ]]; then
            read -rp "Type 'yes' if you would like to continue anyway:  " YES_CASE
            YES=$(echo "$YES_CASE" | tr '[:upper:]' '[:lower:]')
            if [[ $YES != "yes" ]]; then
                exit 1
            fi
        fi
    fi
fi


###############################################################################
# choose file system block size
###############################################################################

if [[ -z $ARG_BLOCK_SIZE ]]; then
    # Windows requires that the file system have a block size that matches logical block size
    FILE_SYSTEM_BLOCK_SIZE=$LOGICAL_BLOCK_SIZE
else
    echo "[+] Overriding detected logical block size..."
    FILE_SYSTEM_BLOCK_SIZE=$ARG_BLOCK_SIZE
fi

# validate that $FILE_SYSTEM_BLOCK_SIZE is numeric > 0 and multiple of 512
echo "[+] Validating file system block size..."
(echo "$FILE_SYSTEM_BLOCK_SIZE" | grep -Eq '^[0-9]+$') || (echo "[-] Invalid file system block size" >&2; false)
[[ $FILE_SYSTEM_BLOCK_SIZE -gt 0 ]] || (echo "[-] Invalid file system block size" >&2; false)
[[ $((FILE_SYSTEM_BLOCK_SIZE % 512)) -eq 0 ]] || (echo "[-] Invalid file system block size" >&2; false)

echo "[*] Using file system block size of $FILE_SYSTEM_BLOCK_SIZE"


###############################################################################
# gather information - total size
###############################################################################

echo "[+] Detecting total size..."
if [[ $TOOL_DRIVE_LISTING = "$TOOL_BLOCKDEV" ]]; then
    TOTAL_SIZE=$($SUDO blockdev --getsize64 "$KDEVICE_PATH")
elif [[ $TOOL_DRIVE_LISTING = "$TOOL_DISKUTIL" ]]; then
    TOTAL_SIZE=$(diskutil info "$KDEVICE_PATH" | grep -Ei '(Total|Disk) Size' | awk -F ':' '{print $2}' | grep -Eoi '\([0-9]+ B' | sed 's/[^0-9]//g')
else
    echo "[-] Internal error 5" >&2
    exit 1
fi

echo "[*] Detected total size of $TOTAL_SIZE"

# validate that $TOTAL_SIZE is numeric > 0
echo "[+] Validating detected total size..."
(echo "$TOTAL_SIZE" | grep -Eq '^[0-9]+$') || (echo "[-] Could not detect valid total size" >&2; false)
[[ $TOTAL_SIZE -gt 0 ]] || (echo "[-] Could not detect valid total size" >&2; false)

# verify entire drive capacity can be used
if [[ $((TOTAL_SIZE/LOGICAL_BLOCK_SIZE)) -ge $(((2**32)-1)) ]]; then
    echo "The device you have selected is larger than can be fully utilized by UDF."
    echo "Only the first 2^32 logical blocks on the device will be usable on the resultant UDF drive,"
    echo "and the remainder of the drive will not be used."
    echo "The maximum UDF file system capacity on this device is $((LOGICAL_BLOCK_SIZE/256)) TiB."
    echo "Please see the format-udf README for more information."

    if [[ -z $FORCE ]]; then
        read -rp "Type 'yes' if you would like to continue anyway:  " YES_CASE
        YES=$(echo "$YES_CASE" | tr '[:upper:]' '[:lower:]')
        if [[ $YES != "yes" ]]; then
            exit 1
        fi
    fi
fi


###############################################################################
# user's last chance before the drive is modified
###############################################################################

echo "[+] Gathering drive information..."
if [[ $TOOL_DRIVE_SUMMARY = "$TOOL_BLKID" ]] && [[ $TOOL_DRIVE_LISTING = "$TOOL_BLOCKDEV" ]]; then
    $SUDO blkid -c /dev/null "$KDEVICE_PATH" || true
    cat "/sys/block/$KDEVICE/device/model" || true
    $SUDO blockdev --report | grep -E "(Device|$KDEVICE_PATH)"
elif [[ $TOOL_DRIVE_LISTING = "$TOOL_DISKUTIL" ]]; then
    diskutil list "$KDEVICE_PATH"
else
    echo "[-] Internal error 6" >&2
    exit 1
fi

if [[ -z $FORCE ]]; then
    echo "The above-listed device (and partitions, if any) will be completely erased."

    read -rp "Type 'yes' if this is what you intend:  " YES_CASE
    YES=$(echo "$YES_CASE" | tr '[:upper:]' '[:lower:]')
    if [[ $YES != "yes" ]]; then
        exit 1
    fi
fi


###############################################################################
# unmount device (if mounted)
###############################################################################

echo "[+] Unmounting device..."
if [[ $TOOL_UNMOUNT = "$TOOL_UMOUNT" ]]; then
    # `true` is so that a failure here doesn't cause entire script to exit prematurely
    $SUDO umount "$KDEVICE_PATH" || true
elif [[ $TOOL_UNMOUNT = "$TOOL_DISKUTIL" ]]; then
    # `true` is so that a failure here doesn't cause entire script to exit prematurely
    $SUDO diskutil unmountDisk "$KDEVICE_PATH" || true
else
    echo "[-] Internal error 7" >&2
    exit 1
fi


###############################################################################
# optionally wipe device
###############################################################################

# this is where we start making changes to the device
trap - EXIT

case $WIPE_METHOD in
    quick)
        # nothing to do
        ;;
    zero)
        echo "[+] Overwriting device with zeros.  This will likely take a LONG time..."
        $SUDO dd if=/dev/zero of="$KDEVICE_PATH" bs="$LOGICAL_BLOCK_SIZE" || true
        ;;
    scrub)
        echo "[+] Scrubbing device with random patterns.  This will likely take a LONG time..."
        $SUDO scrub -f "$KDEVICE_PATH"
        ;;
    *)
        echo "[-] Internal error 8" >&2
        exit 1
        ;;
esac


###############################################################################
# zero out partition table (required even without fake partition table)
###############################################################################

echo "[+] Zeroing out first chunk of device..."
# 4096 was arbitrarily chosen to be "big enough" to delete first chunk of device
$SUDO dd if=/dev/zero of="$KDEVICE_PATH" bs="$LOGICAL_BLOCK_SIZE" count=4096


###############################################################################
# format device
###############################################################################

echo "[+] Formatting $DEVICE_PATH ..."
if [[ $TOOL_UDF = "$TOOL_MKUDFFS" ]]; then
    # --utf8       - encode file names in UTF8 (since pali/udftools@52afdce, this must be specified as the first argument)
    # --blocksize  - the size of blocks in bytes. should be the same as the drive's physical block size.
    # --media-type - "hd" type covers both hard drives and USB drives (since pali/udftools@3aef271, this must be specified before --udfrev)
    # --udfrev     - the udf revision to use.  2.01 is the latest revision available that supports writing in Linux.
    # --lvid       - logical volume identifier
    # --vid        - volume identifier
    ($SUDO mkudffs --utf8 --blocksize="$FILE_SYSTEM_BLOCK_SIZE" --media-type=hd --udfrev=0x0201 --lvid="$LABEL" --vid="$LABEL" "$KDEVICE_PATH") || (echo "[-] Format failed!" >&2; false)
elif [[ $TOOL_UDF = "$TOOL_NEWFS_UDF" ]]; then
    # -b    - the size of blocks in bytes. should be the same as the drive's physical block size.
    # -m    - "blk" type covers both hard drives and USB drives
    # -t    - "overwrite" access type
    # -r    - the udf revision to use.  2.01 is the latest revision available that supports writing in Linux.
    # -v    - volume identifier
    # --enc - encode volume name in UTF8
    ($SUDO newfs_udf -b "$FILE_SYSTEM_BLOCK_SIZE" -m blk -t ow -r 2.01 -v "$LABEL" --enc utf8 "$KDEVICE_PATH") || (echo "[-] Format failed!" >&2; false)
else
    echo "[-] Internal error 9" >&2
    exit 1
fi


###############################################################################
# write fake partition table (for added compatibility on Windows)
###############################################################################

case $PARTITION_TYPE in
    none)
        # nothing to do
        ;;
    mbr)
        echo "[+] Writing fake MBR..."
        # first block has already been zero'd.  start by writing the (only) partition entry at its correct offset.
        entire_disk_partition_entry "$TOTAL_SIZE" "$LOGICAL_BLOCK_SIZE" | xxd -r -p | $SUDO dd of="$KDEVICE_PATH" bs=1 seek=446 count=16
        # Boot signature at the end of the block
        echo -n 55aa | xxd -r -p | $SUDO dd of="$KDEVICE_PATH" bs=1 seek=510 count=2
        ;;
    *)
        echo "[-] Internal error 10" >&2
        exit 1
        ;;
esac


###############################################################################
# report status
###############################################################################

# following call to blkid sometimes exits with failure, even though the device is formatted properly.
# `true` is so that a failure here doesn't cause entire script to exit prematurely
SUMMARY=$([[ $TOOL_DRIVE_SUMMARY = "$TOOL_BLKID" ]] && $SUDO blkid -c /dev/null "$KDEVICE_PATH" 2>/dev/null) || true
echo "[+] Successfully formatted $SUMMARY"

# TODO find a way to auto-mount (`$SUDO mount -a` doesn't work).  in the meantime...
echo "Please disconnect/reconnect your drive now."
