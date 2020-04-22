#!/usr/bin/perl

# grabber for fetching data from Weatherbit.io
# fetches weather data (current and forecast) from Weatherbit.io

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
use LWP::UserAgent;
use JSON qw( decode_json ); 
use File::Copy;
use Getopt::Long;
use Time::Piece;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = "4.7.0.0";

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url          = $pcfg->param("OPENWEATHER.URL");
my $apikey       = $pcfg->param("OPENWEATHER.APIKEY");
my $lang         = $pcfg->param("OPENWEATHER.LANG");
my $stationid    = "lat=" . $pcfg->param("OPENWEATHER.COORDLAT") . "&lon=" . $pcfg->param("OPENWEATHER.COORDLONG");
my $city         = $pcfg->param("OPENWEATHER.STATION");
my $country      = $pcfg->param("OPENWEATHER.COUNTRY");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_openweather',
	logdir => "$lbplogdir",
	#filename => "$lbplogdir/weather4lox.log",
	#append => 1,
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';
GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            'current' => \$current,
            'daily' => \$daily,
            'hourly' => \$hourly);

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_OPENWEATHER process started";
LOGDEB "This is $0 Version $version";


# Get data from Weatherbit Server (API request) for current conditions
my $queryurlcr = "$url/onecall?appid=$apikey&$stationid&lang=$lang&units=metric";

my $error = 0;
LOGINF "Fetching Current Data for Location $stationid";
LOGDEB "URL: $queryurlcr";

my $ua = new LWP::UserAgent;
my $res = $ua->get($queryurlcr);
my $json = $res->decoded_content();

# Check status of request
my $urlstatus = $res->status_line;
my $urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch data for $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Data fetched successfully for $stationid";
}

# Decode JSON response from server
my $decoded_json = decode_json( "$json" );

my $t;
my $weather;
my $icon;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;
 
#
# Fetch current data
#

if ( $current ) { # Start current

# Write location data into database
$t = localtime($decoded_json->{current}->{dt});
LOGINF "Saving new Data for Timestamp $t to database.";

# Saving new current data...
$error = 0;
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F "$decoded_json->{current}->{dt}|";
	my $date = qx(date -R -d "\@$decoded_json->{current}->{dt}");
	chomp ($date);
	print F "$date|";
	my $tz_short = qx(TZ='$decoded_json->{timezone}' date +%Z);
	chomp ($tz_short);
	print F "$tz_short|";
	print F "$decoded_json->{timezone}|";
	my $tz_offset = qx(TZ="$decoded_json->{timezone}" date +%z);
	chomp ($tz_offset);
	print F "$tz_offset|";
	$city = Encode::decode("UTF-8", $city);
	print F "$city|";
	$country = Encode::decode("UTF-8", $country);
	print F "$country|";
	print F "-9999|";
	print F "$decoded_json->{lat}|";
	print F "$decoded_json->{lon}|";
	print F "-9999|";
	print F sprintf("%.1f",$decoded_json->{current}->{temp}), "|";
	print F sprintf("%.1f",$decoded_json->{current}->{feels_like}), "|";
	print F "$decoded_json->{current}->{humidity}|";
	$wdir = $decoded_json->{current}->{wind_deg};
	if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
	if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
	if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
	if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
	if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
	if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
	if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
	if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	print F "$wdirdes|";
	print F "$decoded_json->{current}->{wind_deg}|";
	print F sprintf("%.1f",$decoded_json->{current}->{wind_speed} * 3.6), "|";
	print F sprintf("%.1f",$decoded_json->{current}->{wind_speed} * 3.6), "|";
	print F sprintf("%.1f",$decoded_json->{current}->{feels_like}), "|";
	print F sprintf("%.0f",$decoded_json->{current}->{pressure}), "|";
	print F "$decoded_json->{current}->{dew_point}|";
	print F sprintf("%.0f",$decoded_json->{current}->{visibility} / 1000), "|";
	print F "-9999|";
	print F "-9999|";
	print F sprintf("%.2f",$decoded_json->{current}->{uvi}),"|";
	print F "-9999|";
	if ( $decoded_json->{current}->{rain}->{'1h'} ) {
		print F sprintf("%.2f",$decoded_json->{current}->{rain}->{'1h'}), "|";
	} else {
		print F "0|";
	}	 
	# Convert Weather string into Weather Code and convert icon name
	$weather = $decoded_json->{current}->{weather}->[0]->{id};
	$icon = "";
	if ($weather eq "200") { $icon = "tstorms" };
	if ($weather eq "201") { $icon = "tstorms" };
	if ($weather eq "202") { $icon = "tstorms" };
	if ($weather eq "210") { $icon = "tstorms" };
	if ($weather eq "211") { $icon = "tstorms" };
	if ($weather eq "212") { $icon = "tstorms" };
	if ($weather eq "221") { $icon = "tstorms" };
	if ($weather eq "230") { $icon = "tstorms" };
	if ($weather eq "231") { $icon = "tstorms" };
	if ($weather eq "232") { $icon = "tstorms" };
	if ($weather eq "233") { $icon = "tstorms" };
	if ($weather eq "300") { $icon = "chancerain" };
	if ($weather eq "301") { $icon = "chancerain" };
	if ($weather eq "302") { $icon = "chancerain" };
	if ($weather eq "310") { $icon = "chancerain" };
	if ($weather eq "311") { $icon = "chancerain" };
	if ($weather eq "312") { $icon = "chancerain" };
	if ($weather eq "313") { $icon = "chancerain" };
	if ($weather eq "314") { $icon = "chancerain" };
	if ($weather eq "321") { $icon = "chancerain" };
	if ($weather eq "500") { $icon = "rain" };
	if ($weather eq "501") { $icon = "rain" };
	if ($weather eq "502") { $icon = "rain" };
	if ($weather eq "503") { $icon = "rain" };
	if ($weather eq "504") { $icon = "rain" };
	if ($weather eq "511") { $icon = "sleet" };
	if ($weather eq "520") { $icon = "rain" };
	if ($weather eq "521") { $icon = "rain" };
	if ($weather eq "522") { $icon = "rain" };
	if ($weather eq "531") { $icon = "rain" };
	if ($weather eq "600") { $icon = "snow" };
	if ($weather eq "601") { $icon = "snow" };
	if ($weather eq "602") { $icon = "snow" };
	if ($weather eq "611") { $icon = "sleet" };
	if ($weather eq "612") { $icon = "sleet" };
	if ($weather eq "613") { $icon = "sleet" };
	if ($weather eq "615") { $icon = "sleet" };
	if ($weather eq "616") { $icon = "sleet" };
	if ($weather eq "620") { $icon = "sleet" };
	if ($weather eq "621") { $icon = "sleet" };
	if ($weather eq "622") { $icon = "sleet" };
	if ($weather eq "701") { $icon = "fog" };
	if ($weather eq "711") { $icon = "fog" };
	if ($weather eq "721") { $icon = "hazy" };
	if ($weather eq "731") { $icon = "fog" };
	if ($weather eq "741") { $icon = "fog" };
	if ($weather eq "751") { $icon = "fog" };
	if ($weather eq "761") { $icon = "fog" };
	if ($weather eq "762") { $icon = "fog" };
	if ($weather eq "771") { $icon = "fog" };
	if ($weather eq "781") { $icon = "fog" };
	if ($weather eq "800") { $icon = "clear" };
	if ($weather eq "801") { $icon = "mostlysunny" };
	if ($weather eq "802") { $icon = "mostlycloudy" };
	if ($weather eq "803") { $icon = "cloudy" };
	if ($weather eq "804") { $icon = "overcast" };
	if (!$icon) { $icon = "clear" };
	print F "$icon|"; 
	my $code = "";
	if ($weather eq "200") { $code = "15" };
	if ($weather eq "201") { $code = "15" };
	if ($weather eq "202") { $code = "15" };
	if ($weather eq "210") { $code = "15" };
	if ($weather eq "211") { $code = "15" };
	if ($weather eq "212") { $code = "15" };
	if ($weather eq "221") { $code = "15" };
	if ($weather eq "230") { $code = "15" };
	if ($weather eq "231") { $code = "15" };
	if ($weather eq "232") { $code = "15" };
	if ($weather eq "300") { $code = "12" };
	if ($weather eq "301") { $code = "12" };
	if ($weather eq "302") { $code = "12" };
	if ($weather eq "310") { $code = "12" };
	if ($weather eq "311") { $code = "12" };
	if ($weather eq "312") { $code = "12" };
	if ($weather eq "313") { $code = "12" };
	if ($weather eq "314") { $code = "12" };
	if ($weather eq "321") { $code = "12" };
	if ($weather eq "500") { $code = "13" };
	if ($weather eq "501") { $code = "13" };
	if ($weather eq "502") { $code = "13" };
	if ($weather eq "503") { $code = "13" };
	if ($weather eq "504") { $code = "13" };
	if ($weather eq "511") { $code = "19" };
	if ($weather eq "520") { $code = "10" };
	if ($weather eq "521") { $code = "11" };
	if ($weather eq "522") { $code = "11" };
	if ($weather eq "531") { $code = "11" };
	if ($weather eq "600") { $code = "20" };
	if ($weather eq "601") { $code = "21" };
	if ($weather eq "602") { $code = "21" };
	if ($weather eq "611") { $code = "19" };
	if ($weather eq "612") { $code = "19" };
	if ($weather eq "613") { $code = "19" };
	if ($weather eq "615") { $code = "19" };
	if ($weather eq "616") { $code = "19" };
	if ($weather eq "620") { $code = "19" };
	if ($weather eq "621") { $code = "19" };
	if ($weather eq "622") { $code = "19" };
	if ($weather eq "701") { $code = "6" };
	if ($weather eq "711") { $code = "6" };
	if ($weather eq "721") { $code = "5" };
	if ($weather eq "731") { $code = "6" };
	if ($weather eq "741") { $code = "6" };
	if ($weather eq "751") { $code = "6" };
	if ($weather eq "761") { $code = "6" };
	if ($weather eq "762") { $code = "6" };
	if ($weather eq "771") { $code = "6" };
	if ($weather eq "781") { $code = "6" };
	if ($weather eq "800") { $code = "1" };
	if ($weather eq "801") { $code = "2" };
	if ($weather eq "802") { $code = "3" };
	if ($weather eq "803") { $code = "4" };
	if ($weather eq "804") { $code = "4" };
	if (!$code) { $code = "1" };
	print F "$code|";
	print F "$decoded_json->{current}->{weather}->[0]->{description}|";
	print F "-9999|";
	print F "-9999|";
	print F "-9999|";
	print F "-9999|";
	$t = localtime($decoded_json->{current}->{sunrise});
	print F sprintf("%02d", $t->hour), "|";
	print F sprintf("%02d", $t->min), "|";
	$t = localtime($decoded_json->{current}->{sunset});
	print F sprintf("%02d", $t->hour), "|";
	print F sprintf("%02d", $t->min), "|";
	print F "-9999|";
	print F "$decoded_json->{current}->{clouds}|";
	print F "-9999|";
	if ($decoded_json->{current}->{snow}->{'1h'}) {
		print F sprintf("%.2f",$decoded_json->{current}->{snow}->{'1h'} / 10), "|";
	} else {
		print F "0|";
	}
	print F "\n";
  flock(F,8);
close(F);

LOGOK "Saving current data to $lbplogdir/current.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/current.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

} # End current

#
# Fetch daily data
#

if ( $daily ) { # Start daily

# Saving new daily forecast data...

open(F,">$lbplogdir/dailyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/dailyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	my $i = 1;
	for my $results( @{$decoded_json->{daily}} ){
		print F "$i|";
		$i++;
		print F $results->{dt}, "|";

		$t = localtime($results->{dt});
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		print F sprintf("%.1f",$results->{temp}->{max}), "|";
		print F sprintf("%.1f",$results->{temp}->{min}), "|";
		print F "-9999|";
		if ($results->{rain}) {
			print F sprintf("%.2f",$results->{rain}), "|";
		} else {
			print F "0|";
		}
		if ($results->{snow}) {
			print F sprintf("%.2f",$results->{snow} / 10), "|";
		} else {
			print F "0|";
		}
		print F "-9999|";
		$wdir = $results->{wind_deg};
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		print F "$wdirdes|";
		print F "$results->{wind_deg}|";
		print F sprintf("%.1f",$results->{wind_speed} * 3.6), "|";
		print F "$wdirdes|";
		print F "$results->{wind_deg}|";
		print F "$results->{humidity}|";
		print F "$results->{humidity}|";
		print F "$results->{humidity}|";
		# Convert Weather string into Weather Code and convert icon name
		$weather = $results->{weather}->[0]->{id};
		$icon = "";
		if ($weather eq "200") { $icon = "tstorms" };
		if ($weather eq "201") { $icon = "tstorms" };
		if ($weather eq "202") { $icon = "tstorms" };
		if ($weather eq "210") { $icon = "tstorms" };
		if ($weather eq "211") { $icon = "tstorms" };
		if ($weather eq "212") { $icon = "tstorms" };
		if ($weather eq "221") { $icon = "tstorms" };
		if ($weather eq "230") { $icon = "tstorms" };
		if ($weather eq "231") { $icon = "tstorms" };
		if ($weather eq "232") { $icon = "tstorms" };
		if ($weather eq "233") { $icon = "tstorms" };
		if ($weather eq "300") { $icon = "chancerain" };
		if ($weather eq "301") { $icon = "chancerain" };
		if ($weather eq "302") { $icon = "chancerain" };
		if ($weather eq "310") { $icon = "chancerain" };
		if ($weather eq "311") { $icon = "chancerain" };
		if ($weather eq "312") { $icon = "chancerain" };
		if ($weather eq "313") { $icon = "chancerain" };
		if ($weather eq "314") { $icon = "chancerain" };
		if ($weather eq "321") { $icon = "chancerain" };
		if ($weather eq "500") { $icon = "rain" };
		if ($weather eq "501") { $icon = "rain" };
		if ($weather eq "502") { $icon = "rain" };
		if ($weather eq "503") { $icon = "rain" };
		if ($weather eq "504") { $icon = "rain" };
		if ($weather eq "511") { $icon = "sleet" };
		if ($weather eq "520") { $icon = "rain" };
		if ($weather eq "521") { $icon = "rain" };
		if ($weather eq "522") { $icon = "rain" };
		if ($weather eq "531") { $icon = "rain" };
		if ($weather eq "600") { $icon = "snow" };
		if ($weather eq "601") { $icon = "snow" };
		if ($weather eq "602") { $icon = "snow" };
		if ($weather eq "611") { $icon = "sleet" };
		if ($weather eq "612") { $icon = "sleet" };
		if ($weather eq "613") { $icon = "sleet" };
		if ($weather eq "615") { $icon = "sleet" };
		if ($weather eq "616") { $icon = "sleet" };
		if ($weather eq "620") { $icon = "sleet" };
		if ($weather eq "621") { $icon = "sleet" };
		if ($weather eq "622") { $icon = "sleet" };
		if ($weather eq "701") { $icon = "fog" };
		if ($weather eq "711") { $icon = "fog" };
		if ($weather eq "721") { $icon = "hazy" };
		if ($weather eq "731") { $icon = "fog" };
		if ($weather eq "741") { $icon = "fog" };
		if ($weather eq "751") { $icon = "fog" };
		if ($weather eq "761") { $icon = "fog" };
		if ($weather eq "762") { $icon = "fog" };
		if ($weather eq "771") { $icon = "fog" };
		if ($weather eq "781") { $icon = "fog" };
		if ($weather eq "800") { $icon = "clear" };
		if ($weather eq "801") { $icon = "mostlysunny" };
		if ($weather eq "802") { $icon = "mostlycloudy" };
		if ($weather eq "803") { $icon = "cloudy" };
		if ($weather eq "804") { $icon = "overcast" };
		if (!$icon) { $icon = "clear" };
		print F "$icon|"; 
		my $code = "";
		if ($weather eq "200") { $code = "15" };
		if ($weather eq "201") { $code = "15" };
		if ($weather eq "202") { $code = "15" };
		if ($weather eq "210") { $code = "15" };
		if ($weather eq "211") { $code = "15" };
		if ($weather eq "212") { $code = "15" };
		if ($weather eq "221") { $code = "15" };
		if ($weather eq "230") { $code = "15" };
		if ($weather eq "231") { $code = "15" };
		if ($weather eq "232") { $code = "15" };
		if ($weather eq "300") { $code = "12" };
		if ($weather eq "301") { $code = "12" };
		if ($weather eq "302") { $code = "12" };
		if ($weather eq "310") { $code = "12" };
		if ($weather eq "311") { $code = "12" };
		if ($weather eq "312") { $code = "12" };
		if ($weather eq "313") { $code = "12" };
		if ($weather eq "314") { $code = "12" };
		if ($weather eq "321") { $code = "12" };
		if ($weather eq "500") { $code = "13" };
		if ($weather eq "501") { $code = "13" };
		if ($weather eq "502") { $code = "13" };
		if ($weather eq "503") { $code = "13" };
		if ($weather eq "504") { $code = "13" };
		if ($weather eq "511") { $code = "19" };
		if ($weather eq "520") { $code = "10" };
		if ($weather eq "521") { $code = "11" };
		if ($weather eq "522") { $code = "11" };
		if ($weather eq "531") { $code = "11" };
		if ($weather eq "600") { $code = "20" };
		if ($weather eq "601") { $code = "21" };
		if ($weather eq "602") { $code = "21" };
		if ($weather eq "611") { $code = "19" };
		if ($weather eq "612") { $code = "19" };
		if ($weather eq "613") { $code = "19" };
		if ($weather eq "615") { $code = "19" };
		if ($weather eq "616") { $code = "19" };
		if ($weather eq "620") { $code = "19" };
		if ($weather eq "621") { $code = "19" };
		if ($weather eq "622") { $code = "19" };
		if ($weather eq "701") { $code = "6" };
		if ($weather eq "711") { $code = "6" };
		if ($weather eq "721") { $code = "5" };
		if ($weather eq "731") { $code = "6" };
		if ($weather eq "741") { $code = "6" };
		if ($weather eq "751") { $code = "6" };
		if ($weather eq "761") { $code = "6" };
		if ($weather eq "762") { $code = "6" };
		if ($weather eq "771") { $code = "6" };
		if ($weather eq "781") { $code = "6" };
		if ($weather eq "800") { $code = "1" };
		if ($weather eq "801") { $code = "2" };
		if ($weather eq "802") { $code = "3" };
		if ($weather eq "803") { $code = "4" };
		if ($weather eq "804") { $code = "4" };
		if (!$code) { $code = "1" };
		print F "$code|";
		print F "$results->{weather}->[0]->{description}|";
		print F "-9999|";
		# Save today's moon phase to include it in current.dat
		#if ($i eq "2") {
		#	$moonpercent = sprintf("%.0f",$results->{moon_phase}*100);
		#}
		print F sprintf("%.1f",$results->{dew_point}), "|";
		print F sprintf("%.0f",$results->{pressure}), "|";
		print F sprintf("%.1f",$results->{uvi}),"|";
		$t = localtime($results->{sunrise});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		$t = localtime($results->{sunset});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F "-9999";
		print F "\n";
	}
  flock(F,8);
close(F);

LOGOK "Saving daily forecast data to $lbplogdir/dailyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/dailyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

} # End daily

#
# Fetch hourly data
#

if ( $hourly ) { # Start hourly

# Saving new hourly forecast data...

$error = 0;
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	$i = 1;
	my $n = 0;
	for my $results( @{$decoded_json->{hourly}} ){
		# Skip first dataset (eq to current)
		if ($n eq "0") {
			$n++;
			next;
		} 
		print F "$i|";
		$i++;
		print F $results->{dt}, "|";
		$t = localtime($results->{dt});
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		print F sprintf("%.1f",$results->{temp}), "|";
		print F sprintf("%.1f",$results->{feels_like}), "|";
		print F "-9999|";
		print F "$results->{humidity}|";
		$wdir = $results->{wind_deg};
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		print F "$wdirdes|";
		print F "$results->{wind_deg}|";
		print F sprintf("%.1f",$results->{wind_speed} * 3.6), "|";
		print F sprintf("%.1f",$results->{feels_like}), "|";
		print F sprintf("%.0f",$results->{pressure}), "|";
		print F sprintf("%.1f",$results->{dew_point}), "|";
		print F "$results->{clouds}|";
		print F "-9999|";
		print F "-9999|";
		if ($results->{rain}->{'1h'}) {
			print F sprintf("%.2f",$results->{rain}->{'1h'}), "|";
		} else {
			print F "0|";
		}
		if ($results->{snow}->{'1h'}) {
			print F sprintf("%.2f",$results->{snow}->{'1h'}), "|";
		} else {
			print F "0|";
		}
		print F "-9999|";
		# Convert Weather string into Weather Code and convert icon name
		$weather = $results->{weather}->[0]->{id};
		my $code = "";
		if ($weather eq "200") { $code = "15" };
		if ($weather eq "201") { $code = "15" };
		if ($weather eq "202") { $code = "15" };
		if ($weather eq "210") { $code = "15" };
		if ($weather eq "211") { $code = "15" };
		if ($weather eq "212") { $code = "15" };
		if ($weather eq "221") { $code = "15" };
		if ($weather eq "230") { $code = "15" };
		if ($weather eq "231") { $code = "15" };
		if ($weather eq "232") { $code = "15" };
		if ($weather eq "300") { $code = "12" };
		if ($weather eq "301") { $code = "12" };
		if ($weather eq "302") { $code = "12" };
		if ($weather eq "310") { $code = "12" };
		if ($weather eq "311") { $code = "12" };
		if ($weather eq "312") { $code = "12" };
		if ($weather eq "313") { $code = "12" };
		if ($weather eq "314") { $code = "12" };
		if ($weather eq "321") { $code = "12" };
		if ($weather eq "500") { $code = "13" };
		if ($weather eq "501") { $code = "13" };
		if ($weather eq "502") { $code = "13" };
		if ($weather eq "503") { $code = "13" };
		if ($weather eq "504") { $code = "13" };
		if ($weather eq "511") { $code = "19" };
		if ($weather eq "520") { $code = "10" };
		if ($weather eq "521") { $code = "11" };
		if ($weather eq "522") { $code = "11" };
		if ($weather eq "531") { $code = "11" };
		if ($weather eq "600") { $code = "20" };
		if ($weather eq "601") { $code = "21" };
		if ($weather eq "602") { $code = "21" };
		if ($weather eq "611") { $code = "19" };
		if ($weather eq "612") { $code = "19" };
		if ($weather eq "613") { $code = "19" };
		if ($weather eq "615") { $code = "19" };
		if ($weather eq "616") { $code = "19" };
		if ($weather eq "620") { $code = "19" };
		if ($weather eq "621") { $code = "19" };
		if ($weather eq "622") { $code = "19" };
		if ($weather eq "701") { $code = "6" };
		if ($weather eq "711") { $code = "6" };
		if ($weather eq "721") { $code = "5" };
		if ($weather eq "731") { $code = "6" };
		if ($weather eq "741") { $code = "6" };
		if ($weather eq "751") { $code = "6" };
		if ($weather eq "761") { $code = "6" };
		if ($weather eq "762") { $code = "6" };
		if ($weather eq "771") { $code = "6" };
		if ($weather eq "781") { $code = "6" };
		if ($weather eq "800") { $code = "1" };
		if ($weather eq "801") { $code = "2" };
		if ($weather eq "802") { $code = "3" };
		if ($weather eq "803") { $code = "4" };
		if ($weather eq "804") { $code = "4" };
		if (!$code) { $code = "1" };
		print F "$code|";
		$icon = "";
		if ($weather eq "200") { $icon = "tstorms" };
		if ($weather eq "201") { $icon = "tstorms" };
		if ($weather eq "202") { $icon = "tstorms" };
		if ($weather eq "210") { $icon = "tstorms" };
		if ($weather eq "211") { $icon = "tstorms" };
		if ($weather eq "212") { $icon = "tstorms" };
		if ($weather eq "221") { $icon = "tstorms" };
		if ($weather eq "230") { $icon = "tstorms" };
		if ($weather eq "231") { $icon = "tstorms" };
		if ($weather eq "232") { $icon = "tstorms" };
		if ($weather eq "233") { $icon = "tstorms" };
		if ($weather eq "300") { $icon = "chancerain" };
		if ($weather eq "301") { $icon = "chancerain" };
		if ($weather eq "302") { $icon = "chancerain" };
		if ($weather eq "310") { $icon = "chancerain" };
		if ($weather eq "311") { $icon = "chancerain" };
		if ($weather eq "312") { $icon = "chancerain" };
		if ($weather eq "313") { $icon = "chancerain" };
		if ($weather eq "314") { $icon = "chancerain" };
		if ($weather eq "321") { $icon = "chancerain" };
		if ($weather eq "500") { $icon = "rain" };
		if ($weather eq "501") { $icon = "rain" };
		if ($weather eq "502") { $icon = "rain" };
		if ($weather eq "503") { $icon = "rain" };
		if ($weather eq "504") { $icon = "rain" };
		if ($weather eq "511") { $icon = "sleet" };
		if ($weather eq "520") { $icon = "rain" };
		if ($weather eq "521") { $icon = "rain" };
		if ($weather eq "522") { $icon = "rain" };
		if ($weather eq "531") { $icon = "rain" };
		if ($weather eq "600") { $icon = "snow" };
		if ($weather eq "601") { $icon = "snow" };
		if ($weather eq "602") { $icon = "snow" };
		if ($weather eq "611") { $icon = "sleet" };
		if ($weather eq "612") { $icon = "sleet" };
		if ($weather eq "613") { $icon = "sleet" };
		if ($weather eq "615") { $icon = "sleet" };
		if ($weather eq "616") { $icon = "sleet" };
		if ($weather eq "620") { $icon = "sleet" };
		if ($weather eq "621") { $icon = "sleet" };
		if ($weather eq "622") { $icon = "sleet" };
		if ($weather eq "701") { $icon = "fog" };
		if ($weather eq "711") { $icon = "fog" };
		if ($weather eq "721") { $icon = "hazy" };
		if ($weather eq "731") { $icon = "fog" };
		if ($weather eq "741") { $icon = "fog" };
		if ($weather eq "751") { $icon = "fog" };
		if ($weather eq "761") { $icon = "fog" };
		if ($weather eq "762") { $icon = "fog" };
		if ($weather eq "771") { $icon = "fog" };
		if ($weather eq "781") { $icon = "fog" };
		if ($weather eq "800") { $icon = "clear" };
		if ($weather eq "801") { $icon = "mostlysunny" };
		if ($weather eq "802") { $icon = "mostlycloudy" };
		if ($weather eq "803") { $icon = "cloudy" };
		if ($weather eq "804") { $icon = "overcast" };
		if (!$icon) { $icon = "clear" };
		print F "$icon|"; 
		print F "$results->{weather}->[0]->{description}|";
		print F "-9999|";
		print F "-9999|";
		print F "-9999|";
		print F "\n";
	}
  flock(F,8);
close(F);

# OpenWeatherMap only offers 48h in the free account. Interpolate with 3-hours data to have more entries for the weather emulator
if ($i < 168) {

	# Get data from OPenWeatherMap Server (API request) for current conditions
	$queryurlcr = "$url/forecast?appid=$apikey&$stationid&lang=$lang&units=metric&cnt=40";

	LOGINF "Fetching additional 3-Hourly Forecat Data for Location $stationid to interpolite hourly data";
	LOGDEB "URL: $queryurlcr";

	$ua = new LWP::UserAgent;
	$res = $ua->get($queryurlcr);
	$json = $res->decoded_content();

	# Check status of request
	$urlstatus = $res->status_line;
	$urlstatuscode = substr($urlstatus,0,3);

	LOGDEB "Status: $urlstatus";

	if ($urlstatuscode ne "200") {
	  LOGCRIT "Failed to fetch data for $stationid\. Status Code: $urlstatuscode";
	  exit 2;
	} else {
	  LOGOK "Data fetched successfully for $stationid";
	}

	# Decode JSON response from server
	$decoded_json = decode_json( "$json" );

	$error = 0;
	open(F,"+<$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;;
	  if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	  }
	  flock(F,2);
	  binmode F, ':encoding(UTF-8)';

		my @olddata = <F>;
		#  seek(F,0,0);
		#  truncate(F,0);
		# Last entry in hourly database
		my $lastline;
		my $newline;
		foreach (@olddata){
			$lastline = $_;
			#print "Lastline is: $_\n";
		}
		for my $results( @{$decoded_json->{list}} ){
			my @oldfields = split(/\|/,$lastline);
			my $i = $oldfields[0] + 1;
			if ($oldfields[1] >= $results->{dt}) {
				next;
			} 

			# Step to last entry (normally 3 hours)
			my $delta = ($results->{dt} - $oldfields[1]) / 3600;

			# Create new interpolated entry
			for (my $step=1; $step <= $delta; $step++) {
				$newline = $i + $step - 1;
				$newline .= "|";
				$newline .= $oldfields[1] + ($step * 3600);
				$newline .= "|";
				$t = localtime($oldfields[1] + ($step * 3600));
				$newline .= sprintf("%02d", $t->mday);
				$newline .= "|";
				$newline .= sprintf("%02d", $t->mon);
				$newline .= "|";
				my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
				$t->mon_list(@month);
				$newline .= $t->monname;
				$newline .= "|";
				@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
				$t->mon_list(@month);
				$newline .=  $t->monname;
				$newline .= "|";
				$newline .= $t->year;
				$newline .= "|";
				$newline .= sprintf("%02d", $t->hour);
				$newline .= "|";
				$newline .= sprintf("%02d", $t->min);
				$newline .= "|";
				my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
				$t->day_list(@days);
				$newline .= $t->wdayname;
				$newline .= "|";
				@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
				$t->day_list(@days);
				$newline .= $t->wdayname;
				$newline .= "|";
				$newline .= sprintf( "%.1f", $oldfields[11] + ( $step * ( ($results->{main}->{temp} - $oldfields[11]) / $delta ) ) );
				$newline .= "|";
				$newline .= sprintf( "%.1f", $oldfields[12] + ( $step * ( ($results->{main}->{feels_like} - $oldfields[12]) / $delta ) ) );
				$newline .= "|";
				$newline .= "-9999|";
				$newline .= sprintf( "%.0f", $oldfields[14] + ( $step * ( ($results->{main}->{humidity} - $oldfields[14]) / $delta ) ) );
				$newline .= "|";
				$wdir = sprintf( "%.0f", $oldfields[16] + ( $step * ( ($results->{wind}->{deg} - $oldfields[16]) / $delta ) ) );
				if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
				if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
				if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
				if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
				if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
				if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
				if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
				if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
				if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
				$newline .= "$wdirdes|";
				$newline .= sprintf( "%.0f", $wdir );
				$newline .= "|";
				$newline .= sprintf( "%.1f", $oldfields[17] + ( $step * ( ( (3.6 * $results->{wind}->{speed}) - $oldfields[17]) / $delta ) ) );
				$newline .= "|";
				$newline .= sprintf( "%.1f", $oldfields[12] + ( $step * ( ($results->{main}->{feels_like} - $oldfields[12]) / $delta ) ) );
				$newline .= "|";
				$newline .= sprintf( "%.0f", $oldfields[19] + ( $step * ( ($results->{main}->{pressure} - $oldfields[19]) / $delta ) ) );
				$newline .= "|";
				$newline .= "-9999|";
				$newline .= sprintf( "%.0f", $oldfields[21] + ( $step * ( ($results->{clouds}->{all} - $oldfields[21]) / $delta ) ) );
				$newline .= "|";
				$newline .= "-9999|";
				$newline .= "-9999|";
				if ($results->{rain}->{'3h'}) {
					$newline .= sprintf( "%.2f", $oldfields[24] + ( $step * ( ($results->{rain}->{'3h'} - $oldfields[24]) / $delta ) ) );
				} else {
					$newline .= "0";
				}
				$newline .= "|";
				if ($results->{snow}->{'3h'}) {
					$newline .= sprintf( "%.2f", $oldfields[25] + ( $step * ( ($results->{main}->{snow} - $oldfields[25]) / $delta ) ) );
				} else {
					$newline .= "0";
				}
				$newline .= "|";
				$newline .= "-9999|";
				if ($step eq "1") {
					$newline .= $oldfields[27];
					$newline .= "|";
					$newline .= $oldfields[28];
					$newline .= "|";
					$newline .= $oldfields[29];
					$newline .= "|";
				} else {
					# Convert Weather string into Weather Code and convert icon name
					$weather = $results->{weather}->[0]->{id};
					my $code = "";
					if ($weather eq "200") { $code = "15" };
					if ($weather eq "201") { $code = "15" };
					if ($weather eq "202") { $code = "15" };
					if ($weather eq "210") { $code = "15" };
					if ($weather eq "211") { $code = "15" };
					if ($weather eq "212") { $code = "15" };
					if ($weather eq "221") { $code = "15" };
					if ($weather eq "230") { $code = "15" };
					if ($weather eq "231") { $code = "15" };
					if ($weather eq "232") { $code = "15" };
					if ($weather eq "300") { $code = "12" };
					if ($weather eq "301") { $code = "12" };
					if ($weather eq "302") { $code = "12" };
					if ($weather eq "310") { $code = "12" };
					if ($weather eq "311") { $code = "12" };
					if ($weather eq "312") { $code = "12" };
					if ($weather eq "313") { $code = "12" };
					if ($weather eq "314") { $code = "12" };
					if ($weather eq "321") { $code = "12" };
					if ($weather eq "500") { $code = "13" };
					if ($weather eq "501") { $code = "13" };
					if ($weather eq "502") { $code = "13" };
					if ($weather eq "503") { $code = "13" };
					if ($weather eq "504") { $code = "13" };
					if ($weather eq "511") { $code = "19" };
					if ($weather eq "520") { $code = "10" };
					if ($weather eq "521") { $code = "11" };
					if ($weather eq "522") { $code = "11" };
					if ($weather eq "531") { $code = "11" };
					if ($weather eq "600") { $code = "20" };
					if ($weather eq "601") { $code = "21" };
					if ($weather eq "602") { $code = "21" };
					if ($weather eq "611") { $code = "19" };
					if ($weather eq "612") { $code = "19" };
					if ($weather eq "613") { $code = "19" };
					if ($weather eq "615") { $code = "19" };
					if ($weather eq "616") { $code = "19" };
					if ($weather eq "620") { $code = "19" };
					if ($weather eq "621") { $code = "19" };
					if ($weather eq "622") { $code = "19" };
					if ($weather eq "701") { $code = "6" };
					if ($weather eq "711") { $code = "6" };
					if ($weather eq "721") { $code = "5" };
					if ($weather eq "731") { $code = "6" };
					if ($weather eq "741") { $code = "6" };
					if ($weather eq "751") { $code = "6" };
					if ($weather eq "761") { $code = "6" };
					if ($weather eq "762") { $code = "6" };
					if ($weather eq "771") { $code = "6" };
					if ($weather eq "781") { $code = "6" };
					if ($weather eq "800") { $code = "1" };
					if ($weather eq "801") { $code = "2" };
					if ($weather eq "802") { $code = "3" };
					if ($weather eq "803") { $code = "4" };
					if ($weather eq "804") { $code = "4" };
					if (!$code) { $code = "1" };
					$newline .= $code;
					$newline .= "|";
					$icon = "";
					if ($weather eq "200") { $icon = "tstorms" };
					if ($weather eq "201") { $icon = "tstorms" };
					if ($weather eq "202") { $icon = "tstorms" };
					if ($weather eq "210") { $icon = "tstorms" };
					if ($weather eq "211") { $icon = "tstorms" };
					if ($weather eq "212") { $icon = "tstorms" };
					if ($weather eq "221") { $icon = "tstorms" };
					if ($weather eq "230") { $icon = "tstorms" };
					if ($weather eq "231") { $icon = "tstorms" };
					if ($weather eq "232") { $icon = "tstorms" };
					if ($weather eq "233") { $icon = "tstorms" };
					if ($weather eq "300") { $icon = "chancerain" };
					if ($weather eq "301") { $icon = "chancerain" };
					if ($weather eq "302") { $icon = "chancerain" };
					if ($weather eq "310") { $icon = "chancerain" };
					if ($weather eq "311") { $icon = "chancerain" };
					if ($weather eq "312") { $icon = "chancerain" };
					if ($weather eq "313") { $icon = "chancerain" };
					if ($weather eq "314") { $icon = "chancerain" };
					if ($weather eq "321") { $icon = "chancerain" };
					if ($weather eq "500") { $icon = "rain" };
					if ($weather eq "501") { $icon = "rain" };
					if ($weather eq "502") { $icon = "rain" };
					if ($weather eq "503") { $icon = "rain" };
					if ($weather eq "504") { $icon = "rain" };
					if ($weather eq "511") { $icon = "sleet" };
					if ($weather eq "520") { $icon = "rain" };
					if ($weather eq "521") { $icon = "rain" };
					if ($weather eq "522") { $icon = "rain" };
					if ($weather eq "531") { $icon = "rain" };
					if ($weather eq "600") { $icon = "snow" };
					if ($weather eq "601") { $icon = "snow" };
					if ($weather eq "602") { $icon = "snow" };
					if ($weather eq "611") { $icon = "sleet" };
					if ($weather eq "612") { $icon = "sleet" };
					if ($weather eq "613") { $icon = "sleet" };
					if ($weather eq "615") { $icon = "sleet" };
					if ($weather eq "616") { $icon = "sleet" };
					if ($weather eq "620") { $icon = "sleet" };
					if ($weather eq "621") { $icon = "sleet" };
					if ($weather eq "622") { $icon = "sleet" };
					if ($weather eq "701") { $icon = "fog" };
					if ($weather eq "711") { $icon = "fog" };
					if ($weather eq "721") { $icon = "hazy" };
					if ($weather eq "731") { $icon = "fog" };
					if ($weather eq "741") { $icon = "fog" };
					if ($weather eq "751") { $icon = "fog" };
					if ($weather eq "761") { $icon = "fog" };
					if ($weather eq "762") { $icon = "fog" };
					if ($weather eq "771") { $icon = "fog" };
					if ($weather eq "781") { $icon = "fog" };
					if ($weather eq "800") { $icon = "clear" };
					if ($weather eq "801") { $icon = "mostlysunny" };
					if ($weather eq "802") { $icon = "mostlycloudy" };
					if ($weather eq "803") { $icon = "cloudy" };
					if ($weather eq "804") { $icon = "overcast" };
					if (!$icon) { $icon = "clear" };
					$newline .= $icon;
					$newline .= "|";
					$newline .= $results->{weather}->[0]->{description};
					$newline .= "|";
				}
				$newline .= "-9999|";
				$newline .= "-9999|";
				$newline .= "-9999|";
				#$newline .= "Schritt: $step Vor: $oldfields[11] Ziel: $results->{temp} Schrittweite: ";
				#$newline .= ( ($results->{temp} - $oldfields[11]) / $delta );
				#$newline .= "|";
				# Save new data
				print F "$newline\n";
				$lastline = $newline;
			}
		}
	  flock(F,8);
	close (F);
}

LOGOK "Saving hourly forecast data to $lbplogdir/hourlyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/hourlyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

} # end hourly

# Clean Up Databases

if ( $current ) {

LOGINF "Cleaning $lbplogdir/current.dat.tmp";
open(F,"+<$lbplogdir/current.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);
my $currentname = "$lbplogdir/current.dat.tmp";
my $currentsize = -s ($currentname);
if ($currentsize > 100) {
        move($currentname, "$lbplogdir/current.dat");
}

}

if ( $daily ) {

LOGINF "Cleaning $lbplogdir/dailyforecast.dat.tmp";
open(F,"+<$lbplogdir/dailyforecast.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);
my $dailyname = "$lbplogdir/dailyforecast.dat.tmp";
my $dailysize = -s ($dailyname);
if ($dailysize > 100) {
        move($dailyname, "$lbplogdir/dailyforecast.dat");
}

}

if ( $hourly ) {

LOGINF "Cleaning $lbplogdir/hourlyforecast.dat.tmp";
open(F,"+<$lbplogdir/hourlyforecast.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);
my $hourlyname = "$lbplogdir/hourlyforecast.dat.tmp";
my $hourlysize = -s ($hourlyname);
if ($hourlysize > 100) {
        move($hourlyname, "$lbplogdir/hourlyforecast.dat");
}

}

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}

