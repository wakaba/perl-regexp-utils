#!/bin/sh
rootdir=`dirname $0`/../..
echo "1..1"

(QUERY_STRING="" $rootdir/perl visualizer/regexp.cgi > /dev/null || echo "not ok 1 # die") && echo "ok 1"
