#!/usr/bin/perl

# Grabber for overwriting data by Loxone data

# Copyright 2016-2018 Michael Schlenstedt, michael@loxberry.de
# 			Christian Fenzl, christian@loxberry.de
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
use LoxBerry::IO;
#use LWP::UserAgent;
#use JSON qw( decode_json ); 
use File::Copy;
use Getopt::Long;
use Time::Piece;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = "4.5.0.1";

my $currentnametmp = "$lbplogdir/current.dat.tmp";
my $currentname    = "$lbplogdir/current.dat";

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_loxone',
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

LOGSTART "Weather4Lox GRABBER_LOXONE process started";
LOGDEB "This is $0 Version $version";


LOGINF "Fetching weather data from Loxone Miniserver";

my %lox_response;
my %lox_weather_vi;
my @lox_weather_arr;
my $response_success;

# VI-Name => ColNr.
# ColNr beginning with 0
# See data/current.format
%lox_weather_vi = (
	"w4l_cur_tt" => 11,
	"w4l_cur_tt_fl" => 12,
	"w4l_cur_hu" => 13,
	"w4l_cur_w_dir" => 15,
	"w4l_cur_w_sp" => 16,
	"w4l_cur_w_gu" => 17,
	"w4l_cur_w_ch" => 18,
	"w4l_cur_pr" => 19,
	"w4l_cur_dp" => 20,
	"w4l_cur_sr" => 22,
	"w4l_cur_we_code" => 28
);

# Generate VI array from hash
@lox_weather_arr = ( keys %lox_weather_vi );

LOGDEB "VI's to request: " . join(', ', @lox_weather_arr);

# Fetching data from Miniserver
my $msno = defined $pcfg->param("SERVER.MSNO") ? $pcfg->param("SERVER.MSNO") : 1;
LOGINF "Using Miniserver no. $msno";
%lox_response = LoxBerry::IO::mshttp_get($msno, @lox_weather_arr);

# Checking the response - if nothing is OK, no patching of current.dat required
foreach my $resp (keys %lox_response) {
    # print STDERR "Object $resp has value " . $lox_response{$resp};
	if($lox_response{$resp}) {
		$response_success = 1;
		last;
	}
}

if( !$response_success ) {
	LOGINF "No Miniserver VI responded with data. Quitting.";
	exit 0;
};

LOGDEB "Copying current.dat to current.dat.tmp";
copy($currentname, $currentnametmp);

LOGINF "Reading current.dat.tmp";

my $datafile_str = LoxBerry::System::read_file($currentnametmp);
chomp($datafile_str);

LOGDEB "Old line: $datafile_str";

my @values = split /\|/, $datafile_str;

foreach my $resp (keys %lox_response) {
    # print STDERR "Object $resp has value " . $lox_response{$resp};
	if($lox_response{$resp} and $lox_weather_vi{$resp} ) {
		my $col = $lox_weather_vi{$resp};
		$values[$col] = $lox_response{$resp};
		$values[$col] =~ s/^([-\d\.]+).*/$1/g;
		LOGDEB "  Response from $resp (value $values[$col]) is set to column $col";
	}
}

# Joining line
my $newline = join('|', @values);

LOGDEB "New line: $newline";

# Write patched file
eval {
	open(my $fh, ">$currentnametmp");
	#binmode $fh, ':encoding(UTF-8)';
	print $fh $newline;
	close $fh;
} 
or do {
    LOGCRIT "Could not write $currentnametmp: $@";
	exit 2;
};

# Test file
my $currentsize = -s ($currentnametmp);
if ($currentsize > 100) {
        move($currentnametmp, $currentname);
} else {
	LOGCRIT "File size below 100 bytes - no new file created: $currentnametmp";
	exit 2;
}

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}
