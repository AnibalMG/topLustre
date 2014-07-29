#!/usr/bin/perl

use warnings;
use strict;
use Getopt::Long;
use Term::ANSIColor qw(:constants);
use Term::ReadKey;
use Socket;

#################################################
#                                             	#
#                Top Lustre	              	#
#                                             	#
#  "top" para ver la actividad de los clientes	#
#  de Lustre (bandwidth & iops).	      	#
#                                             	#
#      (C) Anibal Moreno, 2013 BSC            	#
#     						# 
#      Version:					#
#						#
#      0.1 -> Bandwidth "top"			#
#      0.2 -> Added "top 5" at the buttom	#
#      0.3 -> Added iops "top"			#
#      0.4 -> Two filesystem bandwidth		#
#      1.0 -> Lustre uncleaned statistics	#
#      	      get new stat + diff old stat	#
#						#
#						#
#################################################

$Term::ANSIColor::AUTORESET = 1;
my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();

# Info del entorno
my $bin_pdsh="/usr/bin/pdsh";
my $OSS_scratch="cn[2003-2006]";
my $OSS_project="cn[2007-2010]";
my $MDS_scratch="cn2002";
my $MDS_project="cn2001";

# Global vars
my $nodos1;
my $nodos2;
my $fs;
my $num=10;
my $iter=10;
my (%top5_cli, %top5_cli2);
my (%top5_oss, %top5_oss2);
my $HIGH=9999999;
my $MEDIUM=6291888;
my $LOW=3145944;
my $op;

##### add from topOpLustre
my $hosts;
my $sec=3;

my $low_val=100;
my $med_val=1000;



# Functions

sub parm_process {

	if ( @ARGV > 0 ) {
       		GetOptions ('fs=s' => \$fs,
		    'op=s' => \$op,
                    'c:s' => \$iter,
		    'sec:s' => \$sec) or die("Error en los parametros\n\ttoplustre.pl -op (iops|bandwidth) -fs (project|scratch|all) [-sec seconds ] [-c counter ]\n");

	}
		if($fs eq "scratch") {
        		$nodos1=$OSS_scratch;
			$hosts=$MDS_scratch;
		} elsif ($fs eq "project") {
        		$nodos1=$OSS_project; 
			$hosts=$MDS_project;
		} elsif ($fs eq "all"){
        		$nodos1=$OSS_project;
                        $nodos2=$OSS_scratch; 
	} else {
        	print "Error en los parametros\n";
        	print "\ttoplustre.pl -op (iops|bandwidth) -fs (project|scratch|all) [-c seconds ]\n";
        	exit(1);
	}

	
}

sub print_col {

          my @list = @{$_[0]};
	  my $row = $_[1];

	  for(my $col = 0; $col < 3; $col++) {
		if ($col == 0) {
			  my $addr=$list[$row][$col];
			  chomp($addr);
			  $a = gethostbyaddr(inet_aton($addr), AF_INET);
			  chomp($a);
			  $a =~ s/-data.bullx//g;
			  $a =~ s/.bullx//g;
			  $a = "\t".$a;
		} else {
			  $a=$list[$row][$col];
		}

		if ($list[$row][2] <= $low_val){
			  print GREEN "$a\t";
		} elsif ($list[$row][2] <= $med_val){
			  print YELLOW "$a\t";
		} else {
			  print RED "$a\t";
		}
	}
	print "\n";

}


sub print_line {
	my @line = @{$_[0]};
	if ($line[2] <= $LOW){
		foreach (@line) {
			$_ =~ s/://g ;
			$_ =~ s/\@tcp//g ;
			print GREEN "$_\t";
		}
	} elsif ($line[2] <= $MEDIUM){
		foreach (@line) {
			$_ =~ s/://g ;
			$_ =~ s/\@tcp//g ;
			print BLUE "$_\t";
		}
	} elsif ($line[2] <= $HIGH){
		foreach (@line) {
			$_ =~ s/://g ;
			$_ =~ s/\@tcp//g ;
			print YELLOW "$_\t";
		}
	} else {
		foreach (@line) {
			$_ =~ s/://g ;
			$_ =~ s/\@tcp//g ;
			print RED "$_\t";
		}
	}
	if ($line[2] < 10000000){
		print "\t";
	}
}

sub array_substract {

        my @listaA = @{$_[0]};
        my @listaB = @{$_[1]};

	my @new;

        my $llcount=0;
        my $oldcount=0;
	my $newcount=0;

                while($oldcount < $#listaB+1 && $llcount < $#listaA+1) {
                        if ($listaB[$oldcount][1] ne $listaA[$llcount][1]){
                                $oldcount++;
				
                        } else {
                                if($listaB[$oldcount][0] eq $listaA[$llcount][0]){
                                        $new[$newcount][2] = $listaA[$llcount][2]-$listaB[$oldcount][2];
					$new[$newcount][0] = $listaA[$llcount][0];
					$new[$newcount][1] = $listaA[$llcount][1];
                                       	$newcount++; 
                                        $llcount++;
                                        $oldcount++;
                                } elsif($listaB[$oldcount][0] gt $listaA[$llcount][0]){
                                       	$new[$newcount][2] = $listaA[$llcount][2];
                                       	$new[$newcount][0] = $listaA[$llcount][0];
                                        $new[$newcount][1] = $listaA[$llcount][1]; 	
					$newcount++;
                                        $llcount++;
                                } elsif($listaB[$oldcount][0] lt $listaA[$llcount][0]){
                                        $oldcount++;
                                } #else {
                                  #      print "?!?!\n";
                                  #}
                        }
                }

        return @new;
}

sub delete_zero {

        my @array = @{$_[0]};
	my @new;
	my $i = 0;

        # Clear zero
        for ( my $index = $#array; $index >= 0; --$index ) {
                if ($array[$index][2] gt 0) {
                        $new[$i]= $array[$index];
			$i++;
                }
        }

	return @new;
}

sub print_data_traffic {

	system("clear");

	for(my $i = 1; $i < $iter; $i++) {
		my @output=`$bin_pdsh -w $nodos1 "cat /proc/sys/lnet/peers| grep -v nid" | sort -r -n -k 11 | awk '{ print \$1" "\$2" "\$11}'|  grep -v " 0\$"`;
		my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();

		print  "######################## TRAFFIC ########################\n";
		print  "\t$nodos1\n";

		for(my $j = 0; $j < $hchar-3;  $j++){
		
			if ($j < $#output){	
				my @line = split(' ',$output[$j]);
				print_line(\@line);
			}
			if($j == $hchar-4 && $j < $#output){ print "..more"; }
			print "\n";
	
		}
		sleep(1);
	}

}

sub print_data_traffic_double {

        system("clear");

        for(my $i = 1; $i < $iter; $i++) {
                my @output=`$bin_pdsh -w $nodos1 "cat /proc/sys/lnet/peers| grep -v nid" | sort -r -n -k 11 | awk '{ print \$1" "\$2" "\$11}'|  grep -v " 0\$"`;
		my @output2=`$bin_pdsh -w $nodos2 "cat /proc/sys/lnet/peers| grep -v nid" | sort -r -n -k 11 | awk '{ print \$1" "\$2" "\$11}'|  grep -v " 0\$"`;

                my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();

                print  "#################################################################################################\n";
                print  "####################################### TRAFIC ##################################################\n";
		print  "#################################################################################################\n";
                print CYAN "\t$nodos1\t\t\t"; 
		print CYAN "\t\t\t$nodos2\n";
		print CYAN "OSS\tCLIENT\t\tBytes Send/Queue";
		print CYAN "\t\tOSS\tCLIENT\t\tBytes Send/Queue\n";

                for(my $j = 0; $j < $hchar-14;  $j++){

                        if ($j < $#output){
                                #print "for j = $j\n";
                                my @line = split(' ',$output[$j]);

				if (exists  $top5_cli{$line[1]}){
                                         $top5_cli{$line[1]}=$top5_cli{$line[1]}+$line[2];
                                } else { $top5_cli{$line[1]}=$line[2]; }

                                if (exists  $top5_oss{$line[0]}){
                                         $top5_oss{$line[0]}=$top5_oss{$line[0]}+$line[2];
                                } else { $top5_oss{$line[0]}=$line[2]; }
			
				print_line(\@line);
                                
				if($j == $hchar-15 && ($j < $#output || $j < $#output2)){ print "..more"; }
				print "\t\t";
                        } else {
				if($j == $hchar-15 && ($j < $#output )){ print "..more"; }
				print "\t\t\t\t\t\t\t";
			}
			


                        if ($j < $#output2){
                                my @line = split(' ',$output2[$j]);

				if (exists  $top5_cli2{$line[1]}){
					 $top5_cli2{$line[1]}=$top5_cli2{$line[1]}+$line[2];
				} else { $top5_cli2{$line[1]}=$line[2]; }

				if (exists  $top5_oss2{$line[0]}){
                                         $top5_oss2{$line[0]}=$top5_oss2{$line[0]}+$line[2];
                                } else { $top5_oss2{$line[0]}=$line[2]; }

				print_line(\@line);

				if($j == $hchar-15 && ($j < $#output2 )){ print "\t..more"; }
                        }

                        print "\n";

                }

		print "\n\t\t\t\t######## TOP 5 ########\n";

		#for(my $j = 0; $j < 5;  $j++){

		my (@v1,@v2);
		
		my $count=0;
	
		foreach my $value (sort {$top5_cli{$b} <=> $top5_cli{$a} } 
			keys %top5_cli) 
		{	
			if($count >= 5 ) { last; 
			} else {
     				#print "$value\t$top5_cli{$value}\n";
				my $value2 = $value;
				$value2 =~ s/\@tcp//g ;
				$v1[$count]="$value2\t$top5_cli{$value}  ";
				$count++;
			}
			
		}	

		$count=0;
                foreach my $value (sort {$top5_cli2{$b} <=> $top5_cli2{$a} }
                        keys %top5_cli2)
                {
                        if($count >= 5 ) { last;
                        } else {
                                #print "$value\t$top5_cli2{$value}\n";
				my $value2 = $value;
				$value2 =~ s/\@tcp//g ;
				$v2[$count] = "$value2\t$top5_cli2{$value}";
                                $count++;
                        }

                }

		for(my $k = 0; $k <= 5 ; $k++){
			if($k<$#v1+1) {	
				print "\t\t$v1[$k]\t";
			} else {
				print "\t\t\t\t\t\t";
			}

			if ($k<$#v2+1) {
                                        print "$v2[$k]";
			} #else {
				print "\n";
			#}
			
		}

		sleep(1)
        }

}

sub print_ops {

	my @old_list;

	for(my $k = 0; $k < $iter; $k++) {
		
		my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();

		my @list = `ssh $hosts grep -v snapshot_time /proc/fs/lustre/mdt/$fs-MDT0000/exports/*/stats`;
	
		# format clean
		my (@clean_list,@last_list);

		for(my $i = 0; $i< $#list ; $i++){
			$list[$i] =~ s/\/proc\/fs\/lustre\/mdt\/$fs-MDT0000\/exports\///g;
			$list[$i] =~ s/\@tcp\/stats:/ /g;
			$list[$i] =~ s/samples \[reqs\]//g;
			@{$clean_list[$i]} = split(' ',$list[$i]);
		}

		# Sort by iop type, nodename
		my @sort_list = sort { $a->[1] cmp $b->[1] || $a->[0] cmp $b->[0] } @clean_list;
	
                # LIST FORMAT sample:
		#
                #       node1	read	111
                #	node2	read 	321
		# 	node10	read	50
                #	node3	write	123
		#	node9	write	657
		# 	node1	unlink	123
		#	node3	unlink	456
                #       
	

		if ($k == 0) { 
			@old_list = @sort_list; 
			@last_list = @sort_list;	
		} else {
			@last_list = array_substract(\@sort_list,\@old_list);
			@last_list = delete_zero(\@last_list);
			@last_list = sort { $a->[1] cmp $b->[1] || $a->[0] cmp $b->[0] } @last_list;		
		}

		@old_list = sort { $a->[1] cmp $b->[1] || $a->[0] cmp $b->[0] } @clean_list;
		
		# Sort by iop type and count. To the best print.
		my @print_list = sort { $a->[1] cmp $b->[1] || $b->[2] <=> $a->[2] }@last_list;		

		my ($old,$new);	
		my $count=6;

		system("clear");
		system("date");

                if ($#print_list == -1) {
			print CYAN "\n\n\t\t==== Ops List ==== \n\n";
                        print "\t\tNo iops right now\n";
                        sleep $sec;
                        next;
                }


		print CYAN "\n\t\t==== Top 5 Ops ====\n\n";
		for(my $row = 0; $row < $#print_list ; $row++) {
		
			if ($row == 0) { 
				$old=$print_list[$row][1];
			}
			$new=$print_list[$row][1];

			if($old ne $new ){ 
				print "\t-----------------\n";
				print_col(\@print_list,$row);
				$count=5; 
			} elsif (($old eq $new) && ($count > 1)){ 
				print_col(\@print_list,$row);
				$count--; 
			}

			$old=$new;
		}

		# Print count IOps
		my %accumulate;
	
		print CYAN "\n\n\t\t==== Ops List ==== \n\n";

		for(my $row = 0; $row < $#print_list; $row++) { 
                        $accumulate{$print_list[$row][1]} += $print_list[$row][2];
                }

		my $total;
		foreach my $key (keys %accumulate){

                        if ($accumulate{$key} <= $low_val){
                        	print GREEN "\t$key\t=> $accumulate{$key}\n";
                        } elsif ($accumulate{$key} <= $med_val){
                                print YELLOW "\t$key\t=> $accumulate{$key}\n";
                        } else {
                                print RED "\t$key\t=> $accumulate{$key}\n";
                        }

			$total += $accumulate{$key};
		}

		my $totalp = $total;
		$totalp =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
		print "\n\t\tTotal ops => $totalp";
		my $total2 = $total/10;
		$total2 =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
		print "\n\t\tTotal ops per second => $total2 \n";

		print "count = $k, waiting $sec sec\n";
                sleep $sec;
	}
	
}



# MAIN

parm_process();

if($op eq "iops") { 
	if ($fs eq "all"){
		print "Option not implemented.\n";
		exit(1);
	} else {
		print_ops(); 
	}
} elsif($op eq "bandwidth"){
	if($fs eq "all"){ print_data_traffic_double(); }
	else { print_data_traffic();}
} else {
	print "Error en los parametros\n";
        print " toplustre.pl -op (iops|bandwidth) -fs (project|scratch|all) [-sec seconds ] [-c counter ] \n";
        exit(1);
}


