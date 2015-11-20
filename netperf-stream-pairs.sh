#!/bin/bash
#
# netperf-stream-pairs.sh - script to run concurrent netperf streams between pairs of
# (sender, receiver) host IP addresses/names
#
# command line parameters:
#    #1 - sender list - list of hosts that will be sending data
#    #2 - receiver list - list of hosts that will be receiving data
#    #3 - thread count - optional - if supplied, only this many (sender, receiver) pairs will be used
#
# The host in the Nth row of the sender list 
# will send data to the host in the Nth row of the receiver list
#
# environment variables:
#    NETPERF_PGM_DIR - optional - directory where the netperf and netserver executables are located
#    TEST_TIME - optional - number of seconds to run the test (default 30)
#
# WARNING: DO NOT RUN THIS ON SYSTEM WHILE IT IS IN USE!!!
#
# example:
#   # (echo h1 ; echo h2) > snd.list ; (echo h3 ; echo h4) > rcv.list
#   # TEST_TIME=10 NETPERF_PGM_DIR=/root/netperf-2.4 ./netperf-stream-pairs.sh snd.list rcv.list 2
#
#   will run a test for 10 seconds using binaries in /root/netperf-2.4  between 2 pairs of hosts,
#   h1 => h3 , and h2 => h4
#   
SRC_NPDIR=${NETPERF_PGM_DIR:-/shared/benchmarks/netperf-2.4}

# you should not have to edit anything below this line

NOTOK=1
OK=0
MILLION=1000000
BITS_PER_BYTE=8
(( BYTES_PER_MEGABYTE = 1024 * 1024 ))
SSH="ssh -nx -o StrictHostKeyChecking=no "
SCP="scp -Bq -o StrictHostKeyChecking=no "

# introduce a slight pause so that we don't overdrive ssh and cause errors
function pace() {
	( echo import time ; echo "time.sleep(1.0/$1)" ) | python
}

function usage() {
  echo "usage: netperf-pairs.sh sender-list receiver-list thread-count"
  exit $NOTOK 
}

# parse command line inputs  and display test parameters

sender_list=$1
receiver_list=$2
if [ "$sender_list" = ""  -o "$receiver_list" = "" ] ; then usage ; fi

echo 'WARNING: DO NOT RUN THIS ON SYSTEM WHILE IT IS IN USE!!!'
if [ "$NPDIR" = "" ] ; then NPDIR=/root/netperf-2.4 ; fi
if [ "$TEST_TIME" = "" ] ; then TEST_TIME=30 ; fi
echo "test time = $TEST_TIME seconds"

list="`cat $sender_list`"
sender=( $list )
list="`cat $receiver_list`"
receiver=( $list )
count=${#sender[*]}
unique_receivers=`for n in ${receiver[*]} ; do echo $n ; done | sort -u`
#echo "netserver hosts in use: $unique_receivers"
unique_senders=`for n in ${sender[*]} ; do echo $n ; done | sort -u`
#echo "netperf hosts in use: $unique_senders"
if [ $3 -lt $count ] ; then count=$3 ; fi

# use this to clean up from error or caught signal

abort()
{
 i=0
 for h in $sender_list ; do 
	$SSH $h killall -INT netperf
 done

 if [ "$pids" != "" ] ; then
  kill -KILL $pids
 fi
}

trap abort 1 2 3

# prepare the test by copying executables and running netserver process

echo "ensuring netperf and netserver present on target systems ( /tmp/netperf-rsync.log ) "
for h in ${unique_receivers[*]} ${unique_senders[*]} ; do 
        echo -n " $h"
	rsync -ravu $SRC_NPDIR $h:`dirname $NPDIR`/ > /tmp/netperf-rsync.log
done
echo
echo "starting netservers where necessary "
for h in ${unique_receivers[*]} ; do
        echo -n " $h"
	$SSH $h "$NPDIR/netperf -l 1 -L ${h} -H ${h} > /tmp/np$$.log || $NPDIR/netserver -L ${h} > /tmp/netserver.$$.log 2>&1"  &
	netserver_pids="$netserver_pids $!"
	pace 5
done
echo -n " ..."
for p in $netserver_pids ; do 
  wait $p
done
echo "  done"

(cd /tmp ; rm -f netperf*.log netperf-all.log n.tmp sum.tmp sum_MBps.tmp)

echo "starting netperf threads at `date`"
i=0
s=0
thrd_per_sec=10
(( sleeptime = 2 + ($count / $thrd_per_sec) ))
echo "takes $sleeptime sec to launch all threads"
while [ $i -lt $count ] ; do
	next_receiver=${receiver[$i]}
	next_sender=${sender[$i]}
	echo "starting up netperf on sender $next_sender to receiver $next_receiver"
	logfn="/tmp/netperf_${i}_from_${next_sender}_to_$next_receiver.log"
	netperf_cmd="$NPDIR/netperf -l $TEST_TIME -L ${next_sender} -H ${next_receiver}"
	echo "launching: $netperf_cmd"
	$SSH $next_sender "sleep $sleeptime ; $netperf_cmd; date" > $logfn &
	pids="$pids $!"
	(( i = $i + 1 ))
	(( s = $s + 1 ))
	if [ $s -ge 10 ] ; then 
		((sleeptime = $sleeptime - 1)) 
		s=0
	fi
	pace $thrd_per_sec
done

echo "waiting for netperfs to complete at `date`  ..."
result=$OK
for p in $pids ; do
	wait $p
	r=$?
	if [ $r != 0 ] ; then
		echo "pid $p exit status $r"
		result=$r
	fi
done
if [ $result != $OK ] ; then 
	echo "ERROR: one of clients did not complete successfully, check logs"
	exit $NOTOK
fi

echo "netperfs all done at `date`"
echo "per-client results are:"
for f in /tmp/netperf_*_from_*_to_*.log ; do 
  ( echo "" ; echo $f ; cat $f ) >> /tmp/netperf-all.log
done
cd /tmp
cat netperf-all.log

# extract each netperf's transfer rate in millions of bits / second

for f in netperf_*_from_*_to_*.log ; do grep "$TEST_TIME\.0" $f | tail -2  ; done > n.tmp

# add them together to get aggregate transfer rate in millions of bits/second

awk '{ sum = sum + $NF ; print sum }' n.tmp | tail -1 > sum.tmp
if [ "`cat sum.tmp`" = 0 ] ; then
	echo "netperf processes did not run"
	exit $NOTOK
fi

# convert to megabytes/sec

echo "print `cat sum.tmp`*${MILLION}/$BITS_PER_BYTE/$BYTES_PER_MEGABYTE" | python > sum_MBps.tmp
echo 
echo "--- aggregate throughput = `cat sum_MBps.tmp` megabytes/sec ---"
