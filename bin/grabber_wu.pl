#!/usr/bin/perl

# Grabber for overwriting data by WeatherUnderground data

# Copyright 2016-2023 Michael Schlenstedt, michael@loxberry.de
# 			          Christian Fenzl, christian@loxberry.de
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
use LWP::UserAgent;
use JSON qw( decode_json ); 
use File::Copy;
use Getopt::Long;
use Time::Piece;
#use Data::Dumper;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg		= new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $wuurl		= $pcfg->param("WUNDERGROUND.URL");
my $stationid		= $pcfg->param("WUNDERGROUND.STATIONID");
my $currentnametmp 	= "$lbplogdir/current.dat.tmp";
my $currentname    	= "$lbplogdir/current.dat";

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new ( 	
	package => 'weather4lox',
	name => 'grabber_wu',
	logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Due to a bug in the Logging routine, set the loglevel fix to 3
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_WUNDERGROUND process started";
LOGDEB "This is $0 Version $version";

# Get the public API key from the WU website
#curl -Ss https://www.wunderground.com/dashboard/pws/ISACHSEN347 | grep apiKey | sed -r 's/.*apiKey=([0-9a-z]*)\&.*/\1/g'
#$content = qx(curl -Ss https://www.wunderground.com/dashboard/pws/ISACHSEN347 | grep apiKey);
my $url = "https://www.wunderground.com/dashboard/pws/$stationid";

LOGINF "Getting public API key from Wunderground Website";
LOGDEB "URL: $url";

my $ua = new LWP::UserAgent;
my $resp = $ua->get($url);

# Check status of request
my $urlstatus = $resp->status_line;
my $urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

my $apikey;
if ($urlstatuscode ne "200") {
	LOGCRIT "Failed to fetch data\. Status Code: $urlstatuscode";
	exit 2;
} else {
	LOGOK "Data fetched successfully.";
	$apikey = $resp->decoded_content;
	$apikey =~ s/\n//g;
	$apikey =~ s/.*apiKey=([0-9a-z]*)\&.*/$1/g;
	LOGDEB "Public API Key is: $apikey";
}

# Get data from Wunderground Server (API request) for current conditions
my $wgqueryurlcr = "$wuurl?apiKey=$apikey&stationId=$stationid&format=json&units=m&numericPrecision=decimal";

LOGINF "Fetching Data for Station $stationid";
LOGDEB "URL: $wgqueryurlcr";

$ua = new LWP::UserAgent;
$resp = $ua->get($wgqueryurlcr);
my $json = $resp->decoded_content();

# Check status of request
$urlstatus = $resp->status_line;
$urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch data for $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Data fetched successfully for $stationid";
}

# Decode JSON response from server
my $decoded_json = decode_json( $json );
#print Dumper $decoded_json;

# Write location data into database
my $t = localtime($decoded_json->{observations}->[0]->{epoch});
LOGINF "Saving new Data for Timestamp $t to database.";

my %wu_weather;
my @wu_weather_arr;
my %wu_response;

# ColNr beginning with 0
# See data/current.format
%wu_weather = (
	"cur_tt" => 11,
	"cur_tt_fl" => 12,
	"cur_hu" => 13,
	"cur_w_dirdes" => 14,
	"cur_w_dir" => 15,
	"cur_w_sp" => 16,
	"cur_w_gu" => 17,
	"cur_w_ch" => 18,
	"cur_pr" => 19,
	"cur_dp" => 20,
	"cur_sr" => 22,
	"cur_uvi" => 24,
	"cur_prec_today" => 25,
	"cur_prec_1hr" => 26
);

# Generate array from hash
@wu_weather_arr = ( keys %wu_weather );

LOGDEB "Data to request: " . join(', ', @wu_weather_arr);

# Convert anglo JSON data from WU to metric
$wu_response{cur_tt} = sprintf("%.1f",$decoded_json->{observations}->[0]->{metric}->{temp}) if ($decoded_json->{observations}->[0]->{metric}->{temp} ne "-9999");
$wu_response{cur_tt_fl}	= sprintf("%.1f",$decoded_json->{observations}->[0]->{metric}->{windChill}) if ($decoded_json->{observations}->[0]->{metric}->{windChill} ne "-9999");
$wu_response{cur_hu} = $decoded_json->{observations}->[0]->{humidity} if ($decoded_json->{observations}->[0]->{humidity} ne "-9999");
$wu_response{cur_w_dir}	= $decoded_json->{observations}->[0]->{winddir} if ($decoded_json->{observations}->[0]->{winddir} ne "-9999");
my $wdir = $wu_response{cur_w_dir};
my $wdirdes;
if ($wu_response{cur_w_dir} ne "-9999") {
	if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
	if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
	if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
	if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
	if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
	if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
	if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
	if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	$wu_response{cur_w_dirdes} = $wdirdes;
}
$wu_response{cur_w_sp} = $decoded_json->{observations}->[0]->{metric}->{windSpeed} if ($decoded_json->{observations}->[0]->{metric}->{windSpeed} ne "-9999");
$wu_response{cur_w_gu} = $decoded_json->{observations}->[0]->{metric}->{windGust} if ($decoded_json->{observations}->[0]->{metric}->{windGust} ne "-9999");
$wu_response{cur_w_ch} = sprintf("%.1f",$decoded_json->{observations}->[0]->{metric}->{windChill}) if ($decoded_json->{observations}->[0]->{metric}->{windChill} ne "-9999");
$wu_response{cur_pr} = $decoded_json->{observations}->[0]->{metric}->{pressure} if ($decoded_json->{observations}->[0]->{metric}->{pressure} ne "-9999");
$wu_response{cur_dp} = $decoded_json->{observations}->[0]->{metric}->{dewpt} if ($decoded_json->{observations}->[0]->{metric}->{dewpt} ne "-9999");
$wu_response{cur_sr} = sprintf("%.0f",$decoded_json->{observations}->[0]->{solarRadiation}) if ($decoded_json->{observations}->[0]->{solarRadiation} ne "-9999");
$wu_response{cur_uvi} = $decoded_json->{observations}->[0]->{uv} if ($decoded_json->{observations}->[0]->{uv} ne "-9999");
$wu_response{cur_prec_today} = $decoded_json->{observations}->[0]->{metric}->{precipTotal} if ($decoded_json->{observations}->[0]->{metric}->{precipTotal} ne "-9999");
$wu_response{cur_prec_1hr} = $decoded_json->{observations}->[0]->{metric}->{precipRate} if ($decoded_json->{observations}->[0]->{metric}->{precipRate} ne "-9999");

LOGDEB "Copying current.dat to current.dat.tmp";
copy($currentname, $currentnametmp);

LOGINF "Reading current.dat.tmp";

my $datafile_str = LoxBerry::System::read_file($currentnametmp);
chomp($datafile_str);

LOGDEB "Old line: $datafile_str";

my @values = split /\|/, $datafile_str;

foreach my $resp (keys %wu_weather ) {
	#print STDERR "Object $resp has value " . $wu_response{$resp} . "\n";
	if( defined($wu_response{$resp}) and $wu_response{$resp} ne "-9999") {
		my $col = $wu_weather{$resp};
		$values[$col] = $wu_response{$resp};
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
LOGOK "Current Data saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}
