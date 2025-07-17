#!/usr/bin/perl

# grabber for fetching data from openweathermap.org
# fetches weather data (current and forecast) from openweathermap.org

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
use LWP::UserAgent;
use JSON qw( decode_json );
use File::Copy;
use Getopt::Long;
use Time::Piece;
use Astro::MoonPhase;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url          = $pcfg->param("VISUALCROSSING.URL");
my $apikey       = $pcfg->param("VISUALCROSSING.APIKEY");
my $lang         = $pcfg->param("VISUALCROSSING.LANG");
my $stationid    = $pcfg->param("VISUALCROSSING.COORDLAT") . "," . $pcfg->param("VISUALCROSSING.COORDLONG");
my $city         = $pcfg->param("VISUALCROSSING.STATION");
my $country      = $pcfg->param("VISUALCROSSING.COUNTRY");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_visualcrossing',
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

LOGSTART "Weather4Lox GRABBER_VISUALCROSSING process started";
LOGDEB "This is $0 Version $version";


# Get data from www.visualcrossing.com (API request) for current conditions
my $queryurlcr = "$url/$stationid?unitGroup=metric&lang=$lang&iconSet=icons2&include=days,hours,current&key=$apikey&contentType=json";

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
my $code;
my $icon;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;
my $currentepoche = 0;

#
# Fetch current data
#

if ( $current ) { # Start current

# Write location data into database
$currentepoche = $decoded_json->{currentConditions}->{datetimeEpoch}; # Needed during hourly forecast
$t = localtime($decoded_json->{currentConditions}->{datetimeEpoch});
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
	print F "$decoded_json->{currentConditions}->{datetimeEpoch}|";
	my $date = qx(date -R -d "\@$decoded_json->{currentConditions}->{datetimeEpoch}");
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
	print F "$decoded_json->{latitude}|";
	print F "$decoded_json->{longitude}|";
	print F "-9999|";
	print F sprintf("%.1f",$decoded_json->{currentConditions}->{temp}), "|";
	print F sprintf("%.1f",$decoded_json->{currentConditions}->{feelslike}), "|";
	print F "$decoded_json->{currentConditions}->{humidity}|";
	$wdir = $decoded_json->{currentConditions}->{winddir};
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
	print F "$decoded_json->{currentConditions}->{winddir}|";
	print F sprintf("%.1f",$decoded_json->{currentConditions}->{windspeed}), "|";
	if ( $decoded_json->{currentConditions}->{windgust} ) {
		print F sprintf("%.1f",$decoded_json->{currentConditions}->{windgust}), "|";
	} else {
		print F "0|";
	}
	print F sprintf("%.1f",$decoded_json->{currentConditions}->{feelslike}), "|";
	print F sprintf("%.0f",$decoded_json->{currentConditions}->{pressure}), "|";
	print F "$decoded_json->{currentConditions}->{dew}|";
	print F sprintf("%.1f",$decoded_json->{currentConditions}->{visibility}), "|";
	print F sprintf("%.1f",$decoded_json->{currentConditions}->{solarradiation}), "|";
	print F "-9999|";
	print F sprintf("%.2f",$decoded_json->{currentConditions}->{uvindex}),"|";
	print F "-9999|";
	if ( $decoded_json->{currentConditions}->{precip} ) {
		print F sprintf("%.2f",$decoded_json->{currentConditions}->{precip}), "|";
	} else {
		print F "0|";
	}
	# Convert Weather string into Weather Code and convert icon name
	# Weather conditions: https://openweathermap.org/weather-conditions
	$weather = $decoded_json->{currentConditions}->{icon};
	$weather =~ s/\-night|\-day//; # No -night and -day
	$weather =~ s/\-//; # No -
	$weather =~ tr/A-Z/a-z/; # All Lowercase
	$code = "";
	$icon = "";
	if ($weather eq "clear") { $code = "1"; $icon = "clear" };
	if ($weather eq "snow") { $code = "21"; $icon = "snow" };
	if ($weather eq "snowshowers") { $code = "19"; $icon = "sleet" };
	if ($weather eq "thunderrain") { $code = "15"; $icon = "tstorms" };
	if ($weather eq "thundershowsers") { $code = "15"; $icon = "tstorms" };
	if ($weather eq "rain") { $code = "13"; $icon = "rain" };
	if ($weather eq "showsers") { $code = "11"; $icon = "rain" };
	if ($weather eq "fog") { $code = "6"; $icon = "fog" };
	if ($weather eq "wind") { $code = "22"; $icon = "wind" };
	if ($weather eq "cloudy") { $code = "4"; $icon = "cloudy" };
	if ($weather eq "partlycloudy") { $code = "2"; $icon = "partlycloudy" };
	if (!$icon) { $icon = "clear" };
 	if (!$code) { $code = "1" };
	print F "$icon|";
	print F "$code|";
	print F  $decoded_json->{currentConditions}->{conditions} . "|";
	my ( $moonphase,
	  $moonillum,
	  $moonage,
	  $moondist,
	  $moonang,
	  $sundist,
	  $sunang ) = phase();
	print F sprintf("%.2f",$moonillum*100), "|";
	print F sprintf("%.2f",$moonage), "|";
	print F sprintf("%.2f",$moonphase*100), "|";
	print F "-9999|";
#	# See https://github.com/mschlenstedt/LoxBerry-Plugin-Weather4Lox/issues/37
#	my $moonphase = $decoded_json->{currentConditions}->{moonphase};
#	my $moonpercent = 0;
#	if ($moonphase le "0.5") {
#		$moonpercent = $moonphase * 2 * 100;
#	} else {
#		$moonpercent = (1 - $moonphase) * 2 * 100;
#	}
#	print F "$moonpercent|";
#	print F "-9999|";
#	print F sprintf("%.0f",$moonphase*100), "|";
#	print F "-9999|";
	$t = localtime($decoded_json->{currentConditions}->{sunriseEpoch});
	print F sprintf("%02d", $t->hour), "|";
	print F sprintf("%02d", $t->min), "|";
	$t = localtime($decoded_json->{currentConditions}->{sunsetEpoch});
	print F sprintf("%02d", $t->hour), "|";
	print F sprintf("%02d", $t->min), "|";
	print F "-9999|";
	print F "$decoded_json->{currentConditions}->{cloudcover}|";
	print F "$decoded_json->{currentConditions}->{precipprob}|";
	print F sprintf("%.2f",$decoded_json->{currentConditions}->{snow}), "|";
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
	for my $results( @{$decoded_json->{days}} ){
		print F "$i|";
		$i++;
		print F $results->{datetimeEpoch}, "|";
		$t = localtime($results->{datetimeEpoch});
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
		print F sprintf("%.1f",$results->{tempmax}), "|";
		print F sprintf("%.1f",$results->{tempmin}), "|";
		print F sprintf("%.1f",$results->{precipprob}), "|";
		print F sprintf("%.2f",$results->{precip}), "|";
		print F sprintf("%.2f",$results->{snow}), "|";
		print F sprintf("%.2f",$results->{windgust}), "|";
		print F "-9999|";
		print F "-9999|";
		print F sprintf("%.1f",$results->{windspeed}), "|";
		$wdir = $results->{winddir};
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
		print F "$results->{winddir}|";
		print F "$results->{humidity}|";
		print F "-9999|";
		print F "-9999|";
		# Convert Weather string into Weather Code and convert icon name
		$weather = $results->{icon};
		$weather =~ s/\-night|\-day//; # No -night and -day
		$weather =~ s/\-//; # No -
		$weather =~ tr/A-Z/a-z/; # All Lowercase
		$code = "";
		$icon = "";
		if ($weather eq "clear") { $code = "1"; $icon = "clear" };
		if ($weather eq "snow") { $code = "21"; $icon = "snow" };
		if ($weather eq "snowshowers") { $code = "19"; $icon = "sleet" };
		if ($weather eq "thunderrain") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "thundershowsers") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "rain") { $code = "13"; $icon = "rain" };
		if ($weather eq "showsers") { $code = "11"; $icon = "rain" };
		if ($weather eq "fog") { $code = "6"; $icon = "fog" };
		if ($weather eq "wind") { $code = "22"; $icon = "wind" };
		if ($weather eq "cloudy") { $code = "4"; $icon = "cloudy" };
		if ($weather eq "partlycloudy") { $code = "2"; $icon = "partlycloudy" };
		if (!$icon) { $icon = "clear" };
 	 	if (!$code) { $code = "1" };
		print F "$icon|";
		print F "$code|";
		print F "$results->{description}|";
		print F "-9999|";
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($results->{datetimeEpoch});
		print F sprintf("%.2f",$moonillum*100), "|";
		#print F sprintf("%.0f",$results->{moonphase}*100),"|";
		print F sprintf("%.1f",$results->{dew}), "|";
		print F sprintf("%.1f",$results->{pressure}), "|";
		print F sprintf("%.1f",$results->{uvindex}),"|";
		$t = localtime($results->{sunriseEpoch});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		$t = localtime($results->{sunsetEpoch});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F sprintf("%.1f",$results->{visibility}),"|";
		print F sprintf("%.2f",$moonage), "|";
		print F sprintf("%.2f",$moonphase*100), "|";
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
	for my $resultsdays ( @{$decoded_json->{days}} ){
		for my $results( @{$resultsdays->{hours}} ){
			# Skip first datasets of current day
			my $now = localtime;
			my $hfctime = localtime($results->{datetimeEpoch});
			if ($now->hour > $hfctime->hour) {
				next;
			}
			print F "$i|";
			$i++;
			print F $results->{datetimeEpoch}, "|";
			$t = localtime($results->{datetimeEpoch});
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
			print F sprintf("%.1f",$results->{feelslike}), "|";
			print F "-9999|";
			print F "$results->{humidity}|";
			$wdir = $results->{winddir};
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
			print F "$results->{winddir}|";
			print F sprintf("%.1f",$results->{windspeed}), "|";
			print F sprintf("%.1f",$results->{feelslike}), "|";
			print F sprintf("%.1f",$results->{pressure}), "|";
			print F sprintf("%.1f",$results->{dew}), "|";
			print F sprintf("%.0f",$results->{cloudcover}), "|";
			print F "-9999|";
			print F sprintf("%.1f",$results->{uvindex}),"|";
			print F sprintf("%.2f",$results->{precip}), "|";
			print F sprintf("%.2f",$results->{snow}), "|";
			print F sprintf("%.1f",$results->{precipprob}), "|";
			# Convert Weather string into Weather Code and convert icon name
			$weather = $results->{icon};
			$weather =~ s/\-night|\-day//; # No -night and -day
			$weather =~ s/\-//; # No -
			$weather =~ tr/A-Z/a-z/; # All Lowercase
			$code = "";
			$icon = "";
			if ($weather eq "clear") { $code = "1"; $icon = "clear" };
			if ($weather eq "snow") { $code = "21"; $icon = "snow" };
			if ($weather eq "snowshowers") { $code = "19"; $icon = "sleet" };
			if ($weather eq "thunderrain") { $code = "15"; $icon = "tstorms" };
			if ($weather eq "thundershowsers") { $code = "15"; $icon = "tstorms" };
			if ($weather eq "rain") { $code = "13"; $icon = "rain" };
			if ($weather eq "showsers") { $code = "11"; $icon = "rain" };
			if ($weather eq "fog") { $code = "6"; $icon = "fog" };
			if ($weather eq "wind") { $code = "22"; $icon = "wind" };
			if ($weather eq "cloudy") { $code = "4"; $icon = "cloudy" };
			if ($weather eq "partlycloudy") { $code = "2"; $icon = "partlycloudy" };
			if (!$icon) { $icon = "clear" };
 	 	 	if (!$code) { $code = "1" };
			print F "$code|";
			print F "$icon|";
			print F "$results->{conditions}|";
			print F "-9999|";
			print F sprintf("%.1f",$results->{solarradiation}), "|";
			print F sprintf("%.1f",$results->{visibility}),"|";
			my ( $moonphase,
			  $moonillum,
			  $moonage,
			  $moondist,
			  $moonang,
			  $sundist,
			  $sunang ) = phase($results->{datetimeEpoch});
			print F sprintf("%.2f",$moonillum*100), "|";
			print F sprintf("%.2f",$moonage), "|";
			print F sprintf("%.2f",$moonphase*100), "|";
			print F "\n";
		}
	}
  flock(F,8);
close(F);

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
