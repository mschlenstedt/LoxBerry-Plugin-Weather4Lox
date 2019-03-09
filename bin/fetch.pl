#!/usr/bin/perl

# fetch.pl
# fetches weather data (current and forecast) from Wunderground

# Copyright 2016-2018 Michael Schlenstedt, michael@loxberry.de
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
use LoxBerry::Log;
use Getopt::Long;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = "4.5.0.0";

my $pcfg             = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $service          = $pcfg->param("SERVER.WEATHERSERVICE");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'fetch',
	logdir => "$lbplogdir",
	#filename => "$lbplogdir/weather4lox.log",
	#append => 1,
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

LOGSTART "Weather4Lox FETCH process started";
LOGDEB "This is $0 Version $version";

if (-e "$lbpbindir/grabber_$service.pl") {

  LOGINF "Starting Grabber grabber_$service.pl";
  $log->close;
  if ($verbose) { 
    system ("$lbpbindir/grabber_$service.pl -v");
  } else {
    system ("$lbpbindir/grabber_$service.pl");
  }

} else {

  LOGCRIT "Cannot find grabber script for service $service.";
  exit (1);

}

# Grab some data from Loxone Miniserver
if ( $pcfg->param("SERVER.LOXGRABBER") ) {
	if ($verbose) { 
		system ("$lbpbindir/grabber_loxone.pl -v");
	} else {
		system ("$lbpbindir/grabber_loxone.pl");
	}
}

# Data to Loxone
$log->open;
LOGINF "Starting script datatoloxone.pl";
$log->close;

if ($verbose) { 
	system ("$lbpbindir/datatoloxone.pl -v");
} else {
	system ("$lbpbindir/datatoloxone.pl");
}

# Exit
$log->open;
exit;

END
{
	LOGEND;
}

