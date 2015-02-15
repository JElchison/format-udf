format-udf
==========

Bash script to format a block drive (hard drive or Flash drive) in UDF.  The output is a drive that can be used for reading/writing across multiple operating system families:  Windows, OS X, and Linux.  This script should be capable of running in OS X or in Linux.


# Features
* Formats a block drive (hard drive or Flash drive) in <a href="https://en.wikipedia.org/wiki/Universal_Disk_Format">Universal Disk Format (UDF)</a>
    * UDF revision 2.01 used for maximal compatibility (see note on Linux support below)
* Resulting file system can be read/written across multiple operating system families (Windows, OS X, and Linux)
* Runs on any OS having a Bash environment


# OS Support
Following tables detail operating system support for UDF.  Data was adapted from https://en.wikipedia.org/wiki/Universal_Disk_Format#Compatibility (as retrieved on 2014-Aug-28).


### Natively Supported
Both read/write are supported unless otherwise listed below.

Operating System			|Read-only				|Note
----------------------------------------|---------------------------------------|----------------------------------------
Mac OS X 10.5, 10.6, 10.7, 10.8, 10.9	|					|
Windows Vista, 7, 8			|					|Referred to by Microsoft as "Live File System"
Windows XP, Server 2003			|Read-only				|Write support available with third party utilities.
Linux 2.6, 3.x				|UDF revisions 2.01 and before have read/write.  After 2.01, read-only.	| 
AIX 5.2, 5.3, 6.1			|					|
BeOS, magnussoft ZETA, Haiku		|					|
DosBox					|					|
eComStation, OS/2			|					|Additional fee drivers on OS/2
NetBSD 5.0				|					|


### Supported with Third-Party Utilities
Operating System			|Note
----------------------------------------|-----------------------------------
Windows 95 OSR2+, 98, ME		|Such utilities include DLA and InCD
Windows 2000				|


### Not Supported
Operating System			|Note
----------------------------------------|-------------------------------------------------
DOS, FreeDOS, Windows 3.11 or older	|Filesystems that have an ISO9660 backward compatibility structure can be read


# Environment
* Any OS having a Bash environment
* The following tools must be installed, executable, and in the PATH:
    * cat
    * grep
    * egrep
    * mount
    * test
    * true
    * false
    * awk
    * dd
    * xxd
    * *One* of the following:  blockdev, diskutil
    * *One* of the following:  umount, diskutil
    * *One* of the following:  mkudffs, newfs_udf


# Prerequisites
To install necessary prerequisites on Ubuntu:

    sudo apt-get install udftools


# Installation
Simply copy format-udf.sh to a directory of your choosing.  Don't forget to make it executable:

    chmod +x format-udf.sh


# Usage
```
./format-udf.sh <drive> <label>
```
Example:
```
./format-udf.sh sda "My External Drive"
```


# Example usage
On Ubuntu:
```
user@computer:~$ ./format-udf.sh sdb "My External Drive"
[+] Testing dependencies...
[+] Looking for drive listing tool... using /sbin/blockdev
[+] Looking for unmount tool... using /bin/umount
[+] Looking for UDF tool... using /usr/bin/mkudffs
[+] Validating arguments...
[+] Gathering drive information...
Patriot Memory
[sudo] password for user: 
RO    RA   SSZ   BSZ   StartSec            Size   Device
rw   256   512  4096          0      4003463168   /dev/sdb
The above-listed drive (and partitions, if any) will be completely erased.
Type 'yes' if this is what you intend:  yes
[+] Detecting native sector size...
[+] Validating detected sector size...
[+] Unmounting drive...
umount: /dev/sdb: not mounted
[+] Zeroing out any existing partition table on drive...
4096+0 records in
4096+0 records out
2097152 bytes (2.1 MB) copied, 0.924472 s, 2.3 MB/s
[+] Formatting /dev/sdb ...
start=0, blocks=64, type=RESERVED 
start=64, blocks=12, type=VRS 
start=76, blocks=180, type=USPACE 
start=256, blocks=1, type=ANCHOR 
start=257, blocks=16, type=PVDS 
start=273, blocks=1, type=LVID 
start=274, blocks=7818733, type=PSPACE 
start=7819007, blocks=1, type=ANCHOR 
start=7819008, blocks=239, type=USPACE 
start=7819247, blocks=16, type=RVDS 
start=7819263, blocks=1, type=ANCHOR 
[*] Successfully formatted /dev/sdb: LABEL="My External Drive" TYPE="udf"
Please disconnect/reconnect your drive now.
```

On OS X:
```
computer:~ user$ ./format-udf.sh disk2 "My External Drive"
[+] Testing dependencies...
[+] Looking for drive listing tool... using /usr/sbin/diskutil
[+] Looking for unmount tool... using /usr/sbin/diskutil
[+] Looking for UDF tool... using /sbin/newfs_udf
[+] Validating arguments...
[+] Gathering drive information...
/dev/disk2
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:                            My External Drive      *4.0 GB     disk2
The above-listed drive (and partitions, if any) will be completely erased.
Type 'yes' if this is what you intend:  yes
[+] Detecting native sector size...
[+] Validating detected sector size...
[+] Unmounting drive...
Password:
Volume My External Drive on disk2 unmounted
[+] Zeroing out any existing partition table on drive...
4096+0 records in
4096+0 records out
2097152 bytes transferred in 2.710918 secs (773595 bytes/sec)
[+] Formatting /dev/disk2 ...
write to block device: /dev/disk2  last written block address: 7819263
[*] Successfully formatted 
Please disconnect/reconnect your drive now.
```

