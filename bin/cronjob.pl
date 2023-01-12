#!/usr/bin/perl

# cronjob.pl
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
my $version = LoxBerry::System::pluginversion();

my $pcfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $cron = $pcfg->param("SERVER.CRON");
my $cron_forecast = $pcfg->param("SERVER.CRON_FORECAST");

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'cronjob',
	logdir => "$lbplogdir",
	#filename => "$lbplogdir/weather4lox.log",
	#append => 1,
);

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
my $verbose_opt;
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
	$verbose_opt = "-v";
}

LOGSTART "Weather4Lox CRONJOB process";
LOGDEB "This is $0 Version $version";

# calculate time
my $timestamp = time();
my $timestamp_minute_round_down = int($timestamp / 60);

# sample may not work
my $command_opt = "";

LOGDEB "$timestamp_minute_round_down / $cron = " . ($timestamp_minute_round_down / $cron);
if ( $timestamp_minute_round_down % $cron eq 0 ){
	LOGINF "Fetch interval ($cron) for current weather data reached";
    $command_opt .= ' --current'
} else {
	LOGINF "Fetch interval ($cron) for current weather data NOT reached";
}

LOGDEB "$timestamp_minute_round_down / $cron_forecast = " . ($timestamp_minute_round_down / $cron_forecast);
if ( $timestamp_minute_round_down % $cron_forecast eq 0 ){
	LOGINF "Fetch interval ($cron_forecast) for daily and hourly weather data reached";
    $command_opt .= ' --daily --hourly'
} else {
	LOGINF "Fetch interval ($cron_forecast) for daily and hourly weather data NOT reached";
}

if ( $command_opt ne "" ){
	LOGDEB "Fetch data with following command: fetch.pl $command_opt";
	system ("$lbpbindir/fetch.pl --cronjob $command_opt >/dev/null 2>&1");
	return ("0");
}

exit;

END
{
	LOGOK "Done";
	LOGEND;
}
