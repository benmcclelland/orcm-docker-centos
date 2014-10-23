#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use File::Spec;
use File::Path ();
use File::Copy ();
use Pod::Usage;
use POSIX;

our($conf, $image, $nodes);
our($opt_nodb, $opt_clean, $opt_dryrun, $opt_dbcli, $opt_help);

GetOptions(
    "conf:s"  => \$conf,
    "image:s" => \$image,
    "nodes:s" => \$nodes,
    "nodb"    => \$opt_nodb,
    "dbcli"   => \$opt_dbcli,
    "clean"   => \$opt_clean,
    "dryrun"  => \$opt_dryrun,
    "help"    => \$opt_help, "h" => \$opt_help
);

if ($opt_help) {
    pod2usage();
}

# defaults
$conf  ||= "/var/tmp/orcm-site.xml";
$image ||= "benmcclelland/orcm-centos";
our $docker = "/usr/bin/docker";
my @args;

if ($opt_clean) {
    my @containers = `$docker ps -a -q`;
    # dupe STDERR, to be restored later
    open(my $stderr, ">&", \*STDERR) 
        or do { print "Can't dupe STDERR: $!\n"; exit; };

    close(STDERR) or die "Can't close STDERR: $!\n";

    # redirect STDERR to in-memory scalar
    my $err;
    open(STDERR, '>', \$err) 
        or do { print "Can't redirect STDERR: $!\n"; exit; };

    my @result;
    foreach (@containers) {
        @result = `$docker stop $_`;
        @result = `$docker rm $_`;

    }
    # restore original STDERR
    open(STDERR, ">&", $stderr) or do { print "Can't restore STDERR: $!\n"; exit; };
    exit;
}

if ($opt_dbcli) {
    print "$docker run -it --rm --link db:db $image psql -U orcmuser -d orcmdb -h db\n";
    exit;
}

# refresh image
@args = ($docker, "pull", $image);
if($opt_dryrun) {
    print "@args \n";
} else {
    system(@args) == 0
        or die "refresh failed";
}

# start db
my $pgcmd = "sudo -u postgres /usr/pgsql-9.3/bin/postmaster -p 5432 -D /var/lib/pgsql/9.3/data";
my @dockerdb = ($docker, "run", "-d", "--name", "db", "-h", "db", $image);
@args = (@dockerdb, split(" ", $pgcmd));

if($opt_dryrun) {
    print "@args \n";
} else {
    system(@args) == 0
        or die "start db failed";
}

# start scheduler
my $scdcmd = "/opt/open-rcm/bin/orcmsched";
my @dockerscd = ($docker, "run", "-d", "--name", "master", "-h", "master", "--link", "db:db", $image);
@args = (@dockerscd, split(" ", $scdcmd));

if($opt_dryrun) {
    print "@args \n";
} else {
    system(@args) == 0
        or die "start scheduler failed";
}

# start aggregator
my $aggcmd = "/opt/open-rcm/bin/orcmd -mca db_odbc_dsn orcmdb_psql -mca db_odbc_user orcmuser:orcmpassword -mca db_odbc_table data_sample -mca sensor heartbeat,sigar";
my @dockeragg = ($docker, "run", "-d", "--name", "agg01", "-h", "agg01", "--link", "db:db", "--link", "master:master", $image);
@args = (@dockeragg, split(" ", $aggcmd));

if($opt_dryrun) {
    print "@args \n";
} else {
    system(@args) == 0
        or die "start aggregator failed";
}

# start nodes
if ($nodes) {
    my $nodecmd;
    my @dockernode;
    my $node;
    for (my $i = 1; $i <= $nodes; $i++) {
        $node = sprintf "node%03d", $i;
        $nodecmd = "/opt/open-rcm/bin/orcmd -mca sensor heartbeat,sigar";
        @dockernode = ($docker, "run", "-d", "--name", $node, "-h", $node, "--link", "agg01:agg01", $image);
        @args = (@dockernode, split(" ", $nodecmd));

        if($opt_dryrun) {
            print "@args \n";
        } else {
            system(@args) == 0
                or die "start node failed";
        }
    }
}
