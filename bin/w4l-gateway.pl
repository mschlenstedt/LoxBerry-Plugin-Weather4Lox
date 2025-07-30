#!/usr/bin/perl

# Copyright 2016-2025 Michael Schlenstedt, michael@loxberry.de
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

##########################################################################
# Modules
##########################################################################

use LoxBerry::System;
use LoxBerry::IO;
use LoxBerry::Log;
use Getopt::Long;
use DateTime;
use Time::HiRes;
use Data::Dumper;
use LoxBerry::JSON;

##########################################################################
# Read settings
##########################################################################

my $version = LoxBerry::System::pluginversion();

my $pcfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $topic = $pcfg->param("SERVER.TOPIC");

my $jsonobjhistory = LoxBerry::JSON->new();
my $history = $jsonobjhistory->open(filename => "$lbplogdir/history.json", lockexclusive => 1);

my $jsonobjdata = LoxBerry::JSON->new();
my $data = $jsonobjdata->open(filename => "$lbplogdir/weatherdata.json", lockexclusive => 1);

# Global vars

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'w4l-gateway',
	logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
        $log->stdout(1);
        $log->loglevel(7);
}

LOGSTART "Weather4Lox Gateway started";
LOGDEB "This is $0 Version $version";

##########################################################################
# Main program
##########################################################################

# MQTT
LOGINF "Starting MQTT COnnection";
my $mqtt = mqtt_connect();
if ($@ || !$mqtt) {
	my $error = $@ || 'Unknown failure';
	LOGERR "An error occurred - $error";
	exit (2);
};

$mqtt->run(
    "sensors/+/temperature" => sub {
        my ($topic, $message) = @_;
        die "The building's on fire" if $message > 150;
    },
    "#" => sub {
        my ($topic, $message) = @_;
        print "[$topic] $message\n";
    },
);

while(1) {
    print "Looping 1 sec.";
    $mqtt->tick();
}

##########################################################################
# Subs
##########################################################################

sub mean
{
	#print Dumper @_;
	my (@data) = @_;
	my $sum;
	foreach (@data) {
		$sum += $_;
	}
	return ( $sum / @data );
}

END
{
	$jsonobjhistory->write();
	$jsonobjdata->write();

	LOGEND;
}
