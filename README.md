# Wireguard Tests

2 test sets are done:
- Imitation of creating/removing/lookups from wireguard index hashtable/rhashtable
- Workload testing with iperf and 1-200 peers

A script to generate configurations is in [genpeers-k8s-sts.sh](genpeers-k8s-sts.sh)
which uses a container image from this repository and [Dockerfile](Dockerfile).

The reason of using containers is to be able to scale up/down the number of "real" Wireguard peers without
much overhead of full VMs.

## Imitation of creating/removing/lookups from wireguard index hashtable/rhashtable

This test is performed via building a kernel module which just runs in a loop the operations on init.

The code is here:
- [peers/RHashtables](peers/test-rhashtable.c)
- [peers/Hashtables](peers/test-hashtable.c)
- [Makefile](peers/Makefile)

The code of the tests is of low quality, sorry for that.
The files should be put in `drivers/net/wireguard/` which will break building of the normal wireguard module,
so not for production builds.

The tests were run by a [peers/run-test.sh](peers/run-test.sh) script, raw results are in [peers/wireguard-rhashtable-tests.txt](peers/wireguard-rhashtable-tests.txt).
These tests are performed to see if there is a noticeable change in the time to insert a new peer in `index_hashtable`.
From the tests, there is no clear increase/decrease of the measured time.

## Workload testing with iperf and 1-200 peers

The same version of Linux kernel was tested to see if there is a performance drop (speed, retransmits etc) between
the original Wireguard implementation and the RHashtables. Only 1 peer for a Wireguard interface:

`VM with the tested kernel + Iperf3` <=> `IPerf3 peer`.

The raw data is in [peers/wireguard-performance-tests.txt](peers/wireguard-performance-tests.txt). No obvious performance degradation was observed.

In addition, tests were performed to see if there is a performance degradation with the number of peers. Unfortunately, I could not get more compute resources to test with 2-8 thousands peers.

Network topology is:

`VM with the tested kernel + Iperf3` <=> `IPerf3 peer`, `N peers to create more connections`.

The `N peers to create more connections` are containers which were not producing load except periodic keepalives (5 seconds). All the tests were between the IPerf3 peers.

The raw data is in [peers/wireguard-peers-tests.txt](peers/wireguard-peers-tests.txt).
Overall, no obvious difference between the current implementation and RHashtables.
