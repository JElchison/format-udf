#!/bin/bash

# setup Bash environment
set -eufx -o pipefail

# the only parameter passed in should be of the form:  'disk4'
DEVICE=$1

./format-udf.sh -v
./format-udf.sh -h
./format-udf.sh -b 512 -f "/dev/$DEVICE" "UDF Manual Test"
./format-udf.sh -b 512 -f "$DEVICE" "UDF Manual Test"
./format-udf.sh -b 512 -f -p mbr "$DEVICE" "UDF Manual Test"
./format-udf.sh -b 512 -f -p none "$DEVICE" "UDF Manual Test"
./format-udf.sh -b 512 -f -w quick "$DEVICE" "UDF Manual Test"
./format-udf.sh -b 512 -f -w zero "$DEVICE" "UDF Manual Test"
./format-udf.sh -b 512 -f -w scrub "$DEVICE" "UDF Manual Test"

