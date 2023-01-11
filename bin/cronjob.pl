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
my $service = $pcfg->param("SERVER.WEATHERSERVICE");
my $servicedfc;
my $servicehfc;
# check if "Alternative Weather Service for Daily Forecast" is enabled
if ( $pcfg->param("SERVER.USEALTERNATEDFC") ) {
	$servicedfc = $pcfg->param("SERVER.WEATHERSERVICEDFC");
}
# check if "Alternative Weather Service for Hourly Forecast" is enabled
if ( $pcfg->param("SERVER.USEALTERNATEHFC") ) {
	$servicehfc = $pcfg->param("SERVER.WEATHERSERVICEHFC");
}

# sample may not work
my $command_opt = ""
if ( $timestamp % ( $cron * 60 ) eq 0 ){
    $command_opt .= ' --current'
}
if ( $timestamp % ( $cron_forecast * 60 ) eq 0 ){
    $command_opt .= ' --daily --hourly'
}

if ( $command_opt ne "" ){

	system ("$lbpbindir/fetch.pl --cronjob $command_opt >/dev/null 2>&1");
	return ("0");

}


# TODO:
# Programmieren, dass jede Abfrage den Einstellungen entspricht. z.B. current alle 5 minuten, hourly alle 15 minuten

## on update delete all old cron links
#unlink ("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
#unlink ("$lbhomedir/system/cron/cron.03min/$lbpplugindir");
#unlink ("$lbhomedir/system/cron/cron.05min/$lbpplugindir");
#unlink ("$lbhomedir/system/cron/cron.10min/$lbpplugindir");
#unlink ("$lbhomedir/system/cron/cron.15min/$lbpplugindir");
#unlink ("$lbhomedir/system/cron/cron.30min/$lbpplugindir");
#unlink ("$lbhomedir/system/cron/cron.hourly/$lbpplugindir");
