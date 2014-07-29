
Description:

	There is a little perl script to monitoring on real time the Lustre file system status.
	After thousands of Lustre crashes I developed this program to see the real cause of the overload which collapse the file system.

Requirements:

	- Perl (tested on v5.10) 
		- Getopt::Long 
		- Term::ANSIColor
		- Term::ReadKey 
		- Socket 
	- Parallel Distributed Shell (pdsh)

First steps:

	- Install pdsh
	- Try the connectivity with the Lustreo MDS/OSS.

	== OSS ==

	pdsh -w <OSS_list> "cat /proc/sys/lnet/peers| grep -v nid" | sort -r -n -k 11 | awk '{ print \$1" "\$2" "\$11}'|  grep -v " 0\$"
	(In some cases I need the option -R ssh on pdsh)

	
	== MDS ==
	ssh <MDS> grep -v snapshot_time /proc/fs/lustre/mdt/<FSNAME>-MDT0000/exports/*/stats;


Future features:

	- IOPs view for two file systems at the same time (like bandwidth "all" option)
	- Others Lustre statistics files:

		OSS /proc/fs/lustre/ost/OSS/ost_io/stats ost_read 
		OSS /proc/fs/lustre/obdfilter/<fsname>-OST<ost_num>/stats
		OSS /proc/fs/lustre/obdfilter/<fsname>-OST<ost_num>/brw_stats
