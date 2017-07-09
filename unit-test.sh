#!/bin/bash

# setup Bash environment
set -eufx -o pipefail


TESTDATA_FILE=testdata.bin
TESTDATA_SIZE=$((1024*10))
TESTDATA_DIR=testdir
IMAGE_FILE=image.img


# cleanup
rm -fv $IMAGE_FILE $TESTDATA_FILE || true

# generate our test data
head -c $TESTDATA_SIZE /dev/urandom > $TESTDATA_FILE

# create image file
dd if=/dev/zero of=$IMAGE_FILE iflag=fullblock bs=1M count=100
sync

##################

# create loop device
sudo losetup -f $IMAGE_FILE
# get path to new loop device
losetup -h
DEVICE=$(sudo losetup -a -l | grep $IMAGE_FILE | head -n 1 | awk '{print $1}' | sed -r 's|^/dev/||')


# perform the UDF format.
# always use a logical block size of 512 for the purpose of testing.
# always force non-interactive mode for the purpose of testing.
./format-udf.sh -b 512 -f "$DEVICE" "UDF Loop Test"


# delete loop device
sudo losetup -d "/dev/$DEVICE"
DEVICE=

##################

# create loop device
sudo losetup -f $IMAGE_FILE
# get path to new loop device
DEVICE=$(sudo losetup -a | grep $IMAGE_FILE | head -n 1 | awk '{print $1}' | sed -r 's|^/dev/||')

# mount image
udisksctl mount -b "/dev/$DEVICE"
# ensure udf
mount | grep "$DEVICE" | grep udf
# find where mounted
LOCATION=$(mount | grep "$DEVICE" | sed -r 's/^.* on (.+) type udf .*$/\1/')


# create a directory on the UDF file system
mkdir "$LOCATION/$TESTDATA_DIR"
# copy a file to the UDF file system
cp -fv $TESTDATA_FILE "$LOCATION/$TESTDATA_DIR/"


# unmount image
umount "/dev/$DEVICE"

# delete loop device
sudo losetup -d "/dev/$DEVICE"
DEVICE=
LOCATION=

##################

# create loop device
sudo losetup -f $IMAGE_FILE
# get path to new loop device
DEVICE=$(sudo losetup -a | grep $IMAGE_FILE | head -n 1 | awk '{print $1}' | sed -r 's|^/dev/||')

# mount image
udisksctl mount -b /dev/loop0
# ensure udf
mount | grep "$DEVICE" | grep udf
# find where mounted
LOCATION=$(mount | grep "$DEVICE" | sed -r 's/^.* on (.+) type udf .*$/\1/')


# verify the file still readable after having remounted
diff -s $TESTDATA_FILE "$LOCATION/$TESTDATA_DIR/$TESTDATA_FILE"


# unmount image
umount "/dev/$DEVICE"

# delete loop device
sudo losetup -d "/dev/$DEVICE"
DEVICE=
LOCATION=

##################

# cleanup
rm -fv $IMAGE_FILE $TESTDATA_FILE

# print success
echo "Test succeeded"
