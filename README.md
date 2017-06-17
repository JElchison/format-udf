format-udf
==========

Bash script to format a block device (hard drive or Flash drive) in UDF. The output is a drive that can be used for reading/writing across multiple operating system families: Windows, macOS, and Linux. This script should be capable of running in macOS or in Linux.


# Features
* Formats a block device (hard drive or Flash drive) in <a href="https://en.wikipedia.org/wiki/Universal_Disk_Format">Universal Disk Format (UDF)</a>
    * UDF revision 2.01 used for maximal compatibility (see note on Linux support below)
* Resulting file system can be read/written across multiple operating system families (Windows, macOS, and Linux)
* Runs on any OS having a Bash environment
* Optionally wipes device before formatting
* Ability to override detected device block size
* Option to force non-interactive mode (useful for scripting)
* Writes a fake MBR for added compatibility on Windows (optionally disabled)

For the advanced user, format-udf is also capable of formatting a single existing partition, without modifying the partition table.  Beware that using this method will render the newly formatted UDF partition unusable on macOS (but still usable on Linux and Windows).  (See [#24](https://github.com/JElchison/format-udf/issues/24) for caveats.)  Because of this limitation, the recommendation is to format the entire device.


# UDF OS Support
Not all operating systems support UDF.  The following tables detail operating system support for UDF.  Data was adapted from https://en.wikipedia.org/wiki/Universal_Disk_Format#Compatibility (as retrieved on 2017-06-16).

### Natively Supported

Both read/write are supported unless otherwise listed below.

Operating System             |Read-only                                                                           |Note
-----------------------------|------------------------------------------------------------------------------------|----
Windows XP, Server 2003      |Read-only                                                                           |Write support available with third party utilities
Windows Vista, 7, 8, 10      |                                                                                    |Referred to by Microsoft as "Live File System"; Requires fake full-disk partition
Mac OS 9                     |                                                                                    |
Mac OS X 10.5 through 10.11  |                                                                                    |
macOS 10.12+                 |                                                                                    |
Linux 2.6+, 3.x              |UDF revisions 2.01 and before have read/write.  After UDF revision 2.01, read-only. | 
AIX 5.2, 5.3, 6.1            |                                                                                    |
BeOS, magnussoft ZETA, Haiku |                                                                                    |
DosBox                       |                                                                                    |
eComStation, OS/2            |                                                                                    |Additional-fee drivers on OS/2
NetBSD 5.0                   |                                                                                    |
Solaris 8, 9, 10             |                                                                                    |


### Supported with Third-Party Utilities

Operating System     |Note
---------------------|------------------------------
Windows 95 OSR2+, 98 |Utilities include DLA and InCD
Windows 2000, ME     |


### Not Supported

Operating System                    |Note
------------------------------------|-------------------------------------------------
DOS, FreeDOS, Windows 3.11 or older |Filesystems that have an ISO9660 backward compatibility structure can be read


# 4K Drive Support
Not all operating systems support 4K drives ([Advanced Format](https://en.wikipedia.org/wiki/Advanced_Format)).  If you operating system supports UDF, but not your 4K drive, you still may encounter issues using format-udf.

### Windows 4K Drive Support
The following tables detail Windows support for 4K drives.  Data was adapted from the [Microsoft support policy for 4K sector hard drives in Windows](https://support.microsoft.com/en-us/help/2510009/microsoft-support-policy-for-4k-sector-hard-drives-in-windows) (as retrieved on 2017-06-16).  Overlaid into this table are testing results from the format-udf community.  (Special thanks to [@pali](https://github.com/pali) for his [testing on XP](https://github.com/JElchison/format-udf/issues/13#issuecomment-302904564).)

Size / OS                                             |512-byte native                                                                                 |[512 emulation](https://en.wikipedia.org/wiki/Advanced_Format#512e)<br>(AKA "512e")                      |[4K native](https://en.wikipedia.org/wiki/Advanced_Format#4K_native)<br>(AKA "4Kn")
------------------------------------------------------|------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------
Logical block size                                    |512 bytes                                                                                       |512 bytes                                                                                                |4096 bytes
Physical block size                                   |512 bytes                                                                                       |4096 bytes                                                                                               |4096 bytes
**Maximum UDF file<br>system capacity**               |**2 TiB**                                                                                       |**2 TiB**                                                                                                |**16 TiB**
Windows XP                                            |Supported;<br>[Works](https://github.com/JElchison/format-udf/issues/13#issuecomment-302904564) |Unsupported;<br>[Doesn't work](https://github.com/JElchison/format-udf/issues/13#issuecomment-302904564) |Unsupported;<br>[Doesn't work](https://github.com/JElchison/format-udf/issues/13#issuecomment-302904564)
Windows XP Pro x64,<br>Server 2003,<br>Server 2003 R2 |Supported;<br>Likely works but untested                                                         |Unsupported                                                                                              |Unsupported
Windows Vista,<br>Server 2008                         |Supported;<br>Likely works but untested                                                         |Supported;<br>Likely works but untested                                                                  |Unsupported
Windows 7,<br>Server 2008 R2                          |Supported;<br>Likely works but untested                                                         |Supported;<br>Likely works but untested                                                                  |Unsupported
Windows 8,<br>Server 2012                             |Supported;<br>Likely works but untested                                                         |Supported;<br>Likely works but untested                                                                  |Supported;<br>Likely works but untested
Windows 8.1,<br>Server 2012 R2                        |Supported;<br>Likely works but untested                                                         |Unsupported                                                                                              |Unsupported
Windows 10,<br>Server 2016                            |Supported;<br>Likely works but untested                                                         |Unsupported                                                                                              |Supported;<br>Likely works but untested

If you have conducted testing and would like to update this table to benefit future users of format-udf, please send a pull request.  Please include a link to your raw data or testing results.


# Environment
* Any OS having a Bash environment
* The following tools must be installed, executable, and in the PATH:
    * printf
    * xxd
    * *One* of the following:  blockdev, diskutil
    * *One* of the following:  umount, diskutil
    * *One* of the following:  mkudffs, newfs_udf


# Prerequisites
To install necessary prerequisites on Ubuntu:

    sudo apt-get install udftools coreutils vim-common


# Installation
Simply copy format-udf.sh to a directory of your choosing.  Don't forget to make it executable:

    chmod +x format-udf.sh


# Usage
```
Usage:  ./format-udf.sh [-b BLOCK_SIZE] [-f] [-p PARTITION_TYPE] [-w WIPE_METHOD] device label

    -b BLOCK_SIZE
        Block size to be used during format operation.
        If absent, defaults to value reported by blockdev/diskutil.
        This is useful in light of the following Linux kernel bug:
            https://bugzilla.kernel.org/show_bug.cgi?id=102271

    -f
        Forces non-interactive mode.  Useful for scripting.
        Please use with caution, as no user confirmation is given.

    -p PARTITION_TYPE
        Partition type to set during format operation.
        Currently supported types include:  mbr, none
            mbr  - Master boot record (default)
            none - Do not modify partitions
        If absent, defaults to 'mbr'.
        See also:
            https://github.com/JElchison/format-udf#a-fake-partition-table-to-fake-out-windows

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
        Device to format.  Should be of the form:
          * sdx   (Linux, where 'x' is a letter) or
          * diskN (macOS, where 'N' is a number)

    label
        Label to apply to formatted device.

Example:  ./format-udf.sh sdg "My External Drive"
```


### Example usage
On Ubuntu:
```
user@computer:~$ ./format-udf.sh sdg "My UDF External Drive"
[+] Testing dependencies...
[+] Looking for drive listing tool... using /sbin/blockdev
[+] Looking for unmount tool... using /bin/umount
[+] Looking for UDF tool... using /usr/bin/mkudffs
[+] Parsing options...
[+] Validating arguments...
[+] Gathering drive information...
[sudo] password for user: 
/dev/sdg: LABEL="Old Drive" TYPE="udf" 
HTS721010G9SA00 
RO    RA   SSZ   BSZ   StartSec            Size   Device
rw   256   512  4096          0    100030242816   /dev/sdg
The above-listed device (and partitions, if any) will be completely erased.
Type 'yes' if this is what you intend:  yes
[+] Detecting total size...
[*] Using total size of 100030242816
[+] Validating detected total size...
[+] Detecting physical block size...
[*] Using block size of 512
[+] Validating detected block size...
[+] Unmounting device...
umount: /dev/sdg: not mounted
[+] Zeroing out first chunk of device...
4096+0 records in
4096+0 records out
2097152 bytes (2.1 MB) copied, 0.531167 s, 3.9 MB/s
[+] Formatting /dev/sdg ...
start=0, blocks=64, type=RESERVED 
start=64, blocks=12, type=VRS 
start=76, blocks=180, type=USPACE 
start=256, blocks=1, type=ANCHOR 
start=257, blocks=16, type=PVDS 
start=273, blocks=1, type=LVID 
start=274, blocks=195371037, type=PSPACE 
start=195371311, blocks=1, type=ANCHOR 
start=195371312, blocks=239, type=USPACE 
start=195371551, blocks=16, type=RVDS 
start=195371567, blocks=1, type=ANCHOR 
[+] Writing fake MBR...
16+0 records in
16+0 records out
16 bytes (16 B) copied, 0.00259109 s, 6.2 kB/s
2+0 records in
2+0 records out
2 bytes (2 B) copied, 0.000108835 s, 18.4 kB/s
[+] Successfully formatted /dev/sdg: LABEL="My UDF External Drive" TYPE="udf" 
Please disconnect/reconnect your drive now.
```

On macOS:
```
computer:~ user$ ./format-udf.sh disk2 "My UDF External Drive"
[+] Testing dependencies...
[+] Looking for drive listing tool... using /usr/sbin/diskutil
[+] Looking for unmount tool... using /usr/sbin/diskutil
[+] Looking for UDF tool... using /sbin/newfs_udf
[+] Parsing options...
[+] Validating arguments...
[+] Gathering drive information...
/dev/disk2
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:                            Old Drive              *100.0 GB   disk2
The above-listed device (and partitions, if any) will be completely erased.
Type 'yes' if this is what you intend:  yes
[+] Detecting total size...
[*] Using total size of 100030242816
[+] Validating detected total size...
[+] Detecting physical block size...
[*] Using block size of 512
[+] Validating detected block size...
[+] Unmounting device...
Password:
Unmount of all volumes on disk2 was successful
[+] Zeroing out first chunk of device...
4096+0 records in
4096+0 records out
2097152 bytes transferred in 0.592766 secs (3537908 bytes/sec)
[+] Formatting /dev/disk2 ...
write to block device: /dev/disk2  last written block address: 195371567
[+] Writing fake MBR...
16+0 records in
16+0 records out
16 bytes transferred in 0.044496 secs (360 bytes/sec)
2+0 records in
2+0 records out
2 bytes transferred in 0.000602 secs (3322 bytes/sec)
[+] Successfully formatted
Please disconnect/reconnect your drive now.
```

# Expected Behavior

As tested in the lab...

Device Type | Block Size | Formatted on | Inserted on Ubuntu                                                                 | Inserted on macOS
------------|------------|--------------|------------------------------------------------------------------------------------|-----------------
Flash       | 512        | Ubuntu 14.04 | Success                                                                            | Success
Flash       | 512        | macOS 10.11  | Success except label, see [#11](https://github.com/JElchison/format-udf/issues/11) | Success
HDD (USB)   | 512        | Ubuntu 14.04 | Success                                                                            | Success
HDD (USB)   | 512        | macOS 10.11  | Success except label, see [#11](https://github.com/JElchison/format-udf/issues/11) | Success

### Block Size

If's extremely important that format-udf.sh use the correct block size when formatting your drive.  format-udf will attempt to detect and use the correct (logical) block size.  However, in rare cases, Linux can [lie](https://bugzilla.kernel.org/show_bug.cgi?id=102271) about the block size.  macOS is known to report the incorrect block size in certain scenarios as well.  In these cases, the format-udf `-b BLOCK_SIZE` option can be used to explicitly override the detected block size value.

If the wrong block size is used while formatting (i.e. one that doesn't match the logical block size of your drive), the resultant drive will likely have OS compatibility issues and suffer from non-optimal performance issues.

In the same way, it's just as important that the resultant drive be mounted using the correct block size.  Many operating systems will only attempt one block size (usually whatever the mount utility defaults to).  For example, In order to mount a UDF device, Windows seems to require that the UDF file system use a block size equal to the logical block size.  If your block size isn't the OS's default, then auto-mounting likely will not work on your OS.  While a small nuisance, manual mounting attempts should still succeed for nonstandard block sizes.

Example of how to manually mount on Linux:
```
$ mount -t udf -o bs=4096 /dev/sdX /mnt/mount-point
```

Example of how to manually mount on macOS:
```
$ sudo mount_udf -b 4096 /dev/diskN /Volumes/MountPoint
```

Sadly, anything with block size different than 512 doesn't seem to mount on Windows XP.

For more info, see [#12](https://github.com/JElchison/format-udf/issues/12), [#16](https://github.com/JElchison/format-udf/issues/16), and [#31](https://github.com/JElchison/format-udf/issues/31).

### For Best Results

For maximal OS compatibility, use format-udf on a device having a logical block size of 512 bytes.  This will limit your total capacity to 2 TiB, but the resultant device should work on the most operating systems.

For maximal resultant UDF file system capacity, use use format-udf on a device having a logical block size of 4096 bytes.  This will increase your total capacity (from 2 TiB) to 16 TiB, but will limit the number/types of operating systems that will be able to mount/read/write the resultant device.  See compatibility tables above for more detail.

For a human-readable device label, use format-udf in one of the following configurations:
* Run format-udf on Linux
* Run format-udf on macOS, but modify the drive label using Linux or Windows


# A Fake Partition Table to Fake Out Windows

As mentioned by Pieter [here](https://web.archive.org/web/20151103171649/http://sipa.ulyssis.org/2010/02/filesystems-for-portable-disks/), Windows does not support hard disks without a partition table.  This is strange because Windows does not apply the same limitation to flash drives.

To make matters worse, macOS only uses UDF disks that utilize the full disk (not just a partition).

The solution, as suggested by Pieter, is to place a fake partition table (via [MBR](https://en.wikipedia.org/wiki/Master_boot_record)) in the first block of the drive, which lists a single entire-disk partition.  This works because UDF (perhaps intentionally) doesn't utilize the first block.  Unfortunately, there has been no easy way to do this, while juggling all of the other variables (such as device physical block size).

format-udf writes such a fake MBR for added compatibility on Windows.  If this is not what you desire, you can disable the MBR with `-p none`.

After installing GRUB2 on a partitionless drive, you can use `fdisk` to set the partition as active if your BIOS can't boot from partitionless drives. (Thanks to @tome- for the tip.)


# See Also

* [Sharing a Hard/Flash Drive Across Windows, macOS, and Linux with UDF](https://j0nam1el.wordpress.com/2015/02/20/sharing-a-hardflash-drive-across-windows-os-x-and-linux-with-udf/)
* [Universal Disk Format on Wikipedia](https://en.wikipedia.org/wiki/Universal_Disk_Format)
* [Wenguang's Introduction to Universal Disk Format (UDF)](https://sites.google.com/site/udfintro/)
