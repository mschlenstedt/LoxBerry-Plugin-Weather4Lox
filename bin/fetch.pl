#!/usr/bin/perl

# fetch.pl
# fetches weather data (current and forecast) from Weather Services

# Copyright 2016-2023 Michael Schlenstedt, michael@loxberry.de
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
my $version = LoxBerry::System::pluginversion();

my $pcfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $service = $pcfg->param("SERVER.WEATHERSERVICE");
my $servicedfc;
my $servicehfc;
if ( $pcfg->param("SERVER.USEALTERNATEDFC") ) {
	$servicedfc = $pcfg->param("SERVER.WEATHERSERVICEDFC");
}
if ( $pcfg->param("SERVER.USEALTERNATEHFC") ) {
	$servicehfc = $pcfg->param("SERVER.WEATHERSERVICEHFC");
}

# Commandline options
my $verbose = '';
my $cronjob = '';
my $default = '';
my $alternate = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            'cronjob' => \$cronjob,
            'default' => \$default,
            'alternate' => \$alternate);

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'fetch',
	logdir => "$lbplogdir",
	filename => "$lbplogdir/weather4lox.log",
	append => 1,
);

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
my $verbose_opt = '';
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
	$verbose_opt = "-v";
}

LOGSTART "Weather4Lox FETCH process";
LOGDEB "This is $0 Version $version";

# execute when fetch.pl is called directly or with cronjob and default flag
if( !$cronjob || ( $cronjob && $default ) ){
	LOGINF "Fetch default weather data";
	# Which grabber should grab which weather data?
	my $service_opt = "--current";

	if ( ($servicedfc && $servicedfc eq $service) || !$servicedfc ) {
		$service_opt .= " --daily";
	}
	if ( ($servicehfc && $servicehfc eq $service) || !$servicehfc ) {
		$service_opt .= " --hourly";
	}

	if (-e "$lbpbindir/grabber_$service.pl") {
		LOGINF "Starting Grabber grabber_$service.pl $service_opt $verbose_opt";
		$log->close;
		system ("$lbpbindir/grabber_$service.pl $service_opt $verbose_opt");
	} else {
		LOGCRIT "Cannot find grabber script for service $service.";
		exit (1);
	}
	$log->open;
}

# execute when fetch.pl is called directly or with cronjob and alternate flag
if( !$cronjob || ( $cronjob && $alternate ) ){
	LOGINF "Fetch alternate weather data";
	# Grab alternate DFC / HFC
	if ( $servicedfc && $servicedfc eq $servicehfc ) {
		if (-e "$lbpbindir/grabber_$servicedfc.pl") {
			LOGINF "Starting Grabber grabber_$servicedfc.pl --daily --hourly $verbose_opt";
			$log->close;
			system ("$lbpbindir/grabber_$servicedfc.pl --daily --hourly $verbose_opt");
		} else {
			LOGCRIT "Cannot find grabber script for service $servicedfc.";
			exit (1);
		}
	} elsif ( $servicedfc && $servicedfc ne $servicehfc ) {
		if (-e "$lbpbindir/grabber_$servicedfc.pl") {
			LOGINF "Starting Grabber grabber_$servicedfc.pl --daily $verbose_opt";
			$log->close;
			system ("$lbpbindir/grabber_$servicedfc.pl --daily $verbose_opt");
		} else {
			LOGCRIT "Cannot find grabber script for service $servicedfc.";
			exit (1);
		}
	}
	$log->open;

	if ( $servicehfc && $servicehfc ne $servicedfc ) {
		if (-e "$lbpbindir/grabber_$servicehfc.pl") {
			LOGINF "Starting Grabber grabber_$servicehfc.pl --hourly $verbose_opt";
			$log->close;
			system ("$lbpbindir/grabber_$servicehfc.pl --hourly $verbose_opt");
		} else {
			LOGCRIT "Cannot find grabber script for service $servicehfc.";
			exit (1);
		}
	}
	$log->open;
}

# Grab some data from Wunderground
if ( $pcfg->param("SERVER.WUGRABBER") ) {
	LOGINF "Starting Grabber grabber_wu.pl";
	$log->close;
	system ("$lbpbindir/grabber_wu.pl $verbose_opt");
	$log->open;
}

# Grab some data from FOSHKplugin
if ( $pcfg->param("SERVER.FOSHKGRABBER") ) {
	LOGINF "Starting Grabber grabber_foshk.pl";
	$log->close;
	system ("$lbpbindir/grabber_foshk.pl $verbose_opt");
	$log->open;
}

# Grab some data from PWSCatchUpload
if ( $pcfg->param("SERVER.PWSCATCHUPLOADGRABBER") ) {
	LOGINF "Starting Grabber grabber_pwscatchupload.pl";
	$log->close;
	system ("$lbpbindir/grabber_pwscatchupload.pl $verbose_opt");
	$log->open;
}

# Grab some data from Loxone Miniserver
if ( $pcfg->param("SERVER.LOXGRABBER") ) {
	LOGINF "Starting Grabber grabber_loxone.pl";
	$log->close;
	system ("$lbpbindir/grabber_loxone.pl $verbose_opt");
	$log->open;
}

# Data to Loxone
LOGINF "Starting script datatoloxone.pl";
$log->close;
system ("$lbpbindir/datatoloxone.pl $verbose_opt");
$log->open;

exit;

END
{
	LOGOK "Done";
	LOGEND;
}
