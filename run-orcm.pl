#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;

our($conf, $image, $nodes);
our($opt_nodb, $opt_clean, $opt_dryrun, $opt_dbcli, $opt_help, $opt_shell, $opt_nopull);

GetOptions(
    "conf:s"  => \$conf,
    "image:s" => \$image,
    "nodes:s" => \$nodes,
    "nodb"    => \$opt_nodb,
    "dbcli"   => \$opt_dbcli,
    "clean"   => \$opt_clean,
    "dryrun"  => \$opt_dryrun,
    "shell"   => \$opt_shell,
    "nopull"  => \$opt_nopull,
    "help"    => \$opt_help, "h" => \$opt_help
);

if ($opt_help) {
    pod2usage(-verbose => 1) && exit;
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

# Pull latest image
if (!$opt_nopull) {
    my $pullcmd = "$docker pull $image";
    @args = split(" ", $pullcmd);
    if($opt_dryrun) {
        print "@args \n";
    } else {
        system(@args);
    }
}


# DB CLI
if ($opt_dbcli) {
    my @dockerdbcli;
    my $dbclicmd = "psql -U orcmuser -d orcmdb -h db";
    if ($opt_nodb) {
        die "No DB CLI available with --nodb option!\n";
    } else {
        @dockerdbcli = ($docker, "run", "-it", "--rm", "--link", "db:db", $image);
    }
    @args = (@dockerdbcli, split(" ", $dbclicmd));

    if($opt_dryrun) {
        print "@args \n";
    } else {
        system(@args);
    }
    exit;
}

# SHELL
if ($opt_shell) {
    my @dockershell;
    my $shellcmd = "/bin/bash";
    if ($opt_nodb) {
        @dockershell = ($docker, "run", "-it", "--rm", "--link", "master:master", $image);
    } else {
        @dockershell = ($docker, "run", "-it", "--rm", "--link", "master:master", "--link", "db:db", $image);
    }
    @args = (@dockershell, split(" ", $shellcmd));

    if($opt_dryrun) {
        print "@args \n";
    } else {
        system(@args);
    }
    exit;
}

# start db
if (!$opt_nodb) {
    my $pgcmd = "sudo -u postgres /usr/pgsql-9.3/bin/postmaster -p 5432 -D /var/lib/pgsql/9.3/data";
    my @dockerdb = ($docker, "run", "-d", "--name", "db", "-h", "db", $image);
    @args = (@dockerdb, split(" ", $pgcmd));

    if($opt_dryrun) {
        print "@args \n";
    } else {
        system(@args) == 0
            or die "start db failed";
    }
}

# start scheduler
my @dockerscd;
my $scdcmd = "/opt/open-rcm/bin/orcmsched";
if ($opt_nodb) {
    @dockerscd = ($docker, "run", "-d", "--name", "master", "-h", "master", $image);
} else {
    @dockerscd = ($docker, "run", "-d", "--name", "master", "-h", "master", "--link", "db:db", $image);
}
@args = (@dockerscd, split(" ", $scdcmd));

if($opt_dryrun) {
    print "@args \n";
} else {
    system(@args) == 0
        or die "start scheduler failed";
}

# start aggregator
my $aggcmd;
my @dockeragg;

if($opt_nodb) {
    $aggcmd = "/opt/open-rcm/bin/orcmd -omca sensor heartbeat";
    @dockeragg = ($docker, "run", "-d", "--name", "agg01", "-h", "agg01", "--link", "master:master", $image);
} else {
    $aggcmd = "/opt/open-rcm/bin/orcmd -omca db_odbc_dsn orcmdb_psql -omca db_odbc_user orcmuser:orcmpassword -omca db_odbc_table data_sample -omca sensor heartbeat,sigar";
    @dockeragg = ($docker, "run", "-d", "--name", "agg01", "-h", "agg01", "--link", "db:db", "--link", "master:master", $image);
}
@args = (@dockeragg, split(" ", $aggcmd));

if($opt_dryrun) {
    print "@args \n";
} else {
    system(@args) == 0
        or die "start aggregator failed";
}

if ($nodes) {
    my $nodecmd;
    my @dockernode;
    my $node;
    for (my $i = 1; $i <= $nodes; $i++) {
        $node = sprintf "node%03d", $i;
        if($opt_nodb) {
            $nodecmd = "/opt/open-rcm/bin/orcmd -omca sensor heartbeat";
        } else {
            $nodecmd = "/opt/open-rcm/bin/orcmd -omca sensor heartbeat,sigar";
        }
        if ($i == 1) {
            @dockernode = ($docker, "run", "-d", "--name", $node, "-h", $node, "--link", "agg01:agg01", $image);
        } else {
            @dockernode = ($docker, "run", "-d", "--name", $node, "-h", $node, "--link", "agg01:agg01", "--link", "node001:node001", $image);
        }
        @args = (@dockernode, split(" ", $nodecmd));

        if($opt_dryrun) {
            print "@args \n";
        } else {
            system(@args) == 0
                or die "start aggregator failed";
        }
    }
}

=head1 NAME

 run-orcm.pl

=head1 SYNOPSIS

 run-orcm.pl [options]

=head1 DESCRIPTION

Convenience script for launching docker based orcm cluster
optionally launch db, dbcli, and shell

=head1 OPTIONS

 --conf      specifcy orcm-site.xml to bind into docker container
 --image     specify docker image
 --nodes [#] how many compute node containers to launch
 --nodb      disable database and db options
 --dbcli     run a container with the psql shell and connect to db
 --clean     stop and remove *ALL* containers
 --dryrun    only print commands that would be run, don't execute
 --shell     launch a container with a shell prompt
 --nopull    dont pull image
 --help|-h   this help

=cut
