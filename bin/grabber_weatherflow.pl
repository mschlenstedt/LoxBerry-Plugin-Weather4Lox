#!/usr/bin/perl

# grabber for fetching data from Weatherflow
# fetches weather data (current and forecast) from Weatherflow

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
my $version = LoxBerry::System::pluginversion();

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url          = $pcfg->param("WEATHERFLOW.URL");
my $apikey       = $pcfg->param("WEATHERFLOW.APIKEY");
my $lang         = $pcfg->param("WEATHERFLOW.LANG");
my $coordlat     = $pcfg->param("WEATHERFLOW.COORDLAT");
my $coordlong    = $pcfg->param("WEATHERFLOW.COORDLONG");
my $city         = $pcfg->param("WEATHERFLOW.CITY");
my $country      = $pcfg->param("WEATHERFLOW.COUNTRY");
my $stationid    = $pcfg->param("WEATHERFLOW.STATIONID");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_weaterflow',
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

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

# Update API key to comply with Wetherflow format
$apikey =~ s/^(.{8})(.{4})(.{4})(.{4})(.{12})/$1\-$2\-$3\-$4\-$5/;

LOGSTART "Weather4Lox GRABBER_WEATHERFLOW process started";
LOGDEB "This is $0 Version $version";

# Get forecast data from Weatherflow Server
# Note: the forecast data also contains current conditions, but these are not as accurate as the station observations
# For that reason, we also query the station observations (see below)
my $queryurlcr = "$url\/better_forecast?station_id=$stationid&api_key=$apikey&lat=$coordlat&lon=$coordlong";

LOGINF "Fetching Data for Station $stationid";
LOGDEB "URL: $queryurlcr";

my $ua = new LWP::UserAgent;
my $res = $ua->get($queryurlcr);
my $json = $res->decoded_content();

# Check status of request
my $urlstatus = $res->status_line;
my $urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch forecast data for Station $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Data fetched successfully for Station $stationid";
}

# Decode JSON response from server
my $forecast_json = decode_json( $json );

# end retreiving forecast data

# Get current station observation from Weatherflow Server
my $queryurlcr_curr = "$url\/observations/station/$stationid?token=$apikey";

LOGINF "Fetching Data for Station $stationid";
LOGDEB "URL: $queryurlcr_curr";

my $ua_curr = new LWP::UserAgent;
my $res_curr = $ua_curr->get($queryurlcr_curr);
my $json_curr = $res_curr->decoded_content();

# Check status of request
my $urlstatus_curr = $res_curr->status_line;
my $urlstatuscode_curr = substr($urlstatus_curr,0,3);

LOGDEB "Status: $urlstatus_curr";

if ($urlstatuscode_curr ne "200") {
  LOGCRIT "Failed to fetch current observation data for Station $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Data fetched successfully for Station $stationid";
}

# Decode JSON response from server
my $current_observation_json = decode_json( $json_curr );

# end retreiving current station observation data

my $t;
my $weather;
my $icon;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;
my $error;


if ( $current ) { # Start current

# Write location data into database
$t = localtime($forecast_json->{current_conditions}->{time});
LOGINF "Saving new Data for Timestamp $t to database.";

# Saving new current data...
$error = 0;
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F "$forecast_json->{current_conditions}->{time}|"; # Date Epoche 
	print F $t, " ", sprintf("+%04d", $forecast_json->{timezone_offset_minutes}/60 * 100), "|"; 	# Date RFC822
	my $tz_short = qx(TZ='$forecast_json->{timezone}' date +%Z);
	chomp ($tz_short);
	print F "$tz_short|"; # Timeezone Short
	print F "$forecast_json->{timezone}|"; # Timezone Long
	print F sprintf("+%04d", $forecast_json->{timezone_offset_minutes}/60 * 100), "|"; # Timezone Offset
	$city = Encode::decode("UTF-8", $city);
	print F "$city|"; # Observation location
	$country = Encode::decode("UTF-8", $country);
	print F "$country|"; # Location Country
	print F "-9999|"; # Location Country Code
	print F "$forecast_json->{latitude}|"; #	Location Latitude
	print F "$forecast_json->{longitude}|"; # Location Longitude
	print F "$forecast_json->{station}->{elevation}|"; # Location Elevation
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{air_temperature}), "|"; # Temperature
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{feels_like}), "|"; # Feelslike Temp
	print F "$current_observation_json->{obs}->[0]->{relative_humidity}|"; # Rel. Humidity
	$wdir = $current_observation_json->{obs}->[0]->{wind_direction};
	if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
	if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
	if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
	if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
	if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
	if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
	if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
	if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	print F "$wdirdes|"; # Wind Dir Description
	print F "$current_observation_json->{obs}->[0]->{wind_direction}|"; # Wind Dir Degrees
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{wind_avg} * 3.6), "|"; # Wind Speed
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{wind_gust} * 3.6), "|"; # Wind Gust
	print F sprintf("%.0f",$current_observation_json->{obs}->[0]->{wind_chill}), "|"; # Windchill
	print F "$current_observation_json->{obs}->[0]->{sea_level_pressure}|"; # Pressure
	print F sprintf("%.1f",$current_observation_json->{obs}->[0]->{dew_point}), "|"; # Dew Point
	print F "-9999|"; # Visibility
	print F "$current_observation_json->{obs}->[0]->{solar_radiation}|"; #Solar Radiation
	print F "$current_observation_json->{obs}->[0]->{heat_index}|"; #Heat Index
	print F "$current_observation_json->{obs}->[0]->{uv}|"; # UV Index
	print F sprintf("%.3f",$current_observation_json->{obs}->[0]->{precip_accum_local_day}), "|";  # Precipitation Today
	print F sprintf("%.3f",$current_observation_json->{obs}->[0]->{precip_accum_last_1hr}), "|"; # Precipitation 1hr
	# Convert Weather string into Weather Code and convert icon name
	$weather = $forecast_json->{current_conditions}->{icon};
	$weather =~ s/\-night|\-day//; # No -night and -day
	$weather =~ s/cc\-//; # No cc-
	$weather =~ s/\-//; # No -
	$weather =~ s/possibly/chance/; # added for wf: replace possibly by chance
	$weather =~ tr/A-Z/a-z/; # All Lowercase
	my $icon = $weather;
	if ($weather eq "clear") {$weather = "1";}
	#elsif ($weather eq "sunny") {$weather = "1";}
	#elsif ($weather eq "partlysunny") {$weather = "3";}
	#elsif ($weather eq "mostlysunny") {$weather = "2";}
	elsif ($weather eq "partlycloudy") {$weather = "2";}
	#elsif ($weather eq "mostlycloudy") {$weather = "3";}
	elsif ($weather eq "cloudy") {$weather = "4";}
	#elsif ($weather eq "overcast") {$weather = "4";}
	#elsif ($weather eq "chanceflurries") {$weather = "18";}
	elsif ($weather eq "chancesleet") {$weather = "18";}
	elsif ($weather eq "chancesnow") {$weather = "20";}
	elsif ($weather eq "snowlikely") {$weather = "20"; $icon="chancesnow"} # added for wf
	#elsif ($weather eq "flurries") {$weather = "16";}
	elsif ($weather eq "sleet") {$weather = "19";}
	elsif ($weather eq "snow") {$weather = "21";}
	elsif ($weather eq "chancerain") {$weather = "12";}
	elsif ($weather eq "chancerainy") {$weather = "12"; $icon="chancerain"} # added for wf
	elsif ($weather eq "rainy") {$weather = "12"; $icon="chancerain"}  # added for wf
	elsif ($weather eq "rain") {$weather = "13";}
	#elsif ($weather eq "chancetstorms") {$weather = "14";}
	#elsif ($weather eq "tstorms") {$weather = "15";}
	elsif ($weather eq "fog") {$weather = "6";}
	#elsif ($weather eq "hazy") {$weather = "5";}
	elsif ($weather eq "wind") {$weather = "22";}
	else {$weather = "0";}
	print F "$icon|"; # Weather Icon
	print F "$weather|"; # Weather Code
	print F "$forecast_json->{current_conditions}->{conditions}|"; # Weather Description
	
	#print F $forecast_json->{daily}->{data}->[0]->{moonPhase}*100, "|"; 
	# See https://github.com/mschlenstedt/LoxBerry-Plugin-Weather4Lox/issues/37
	#my $moonphase = $forecast_json->{daily}->{data}->[0]->{moonPhase};
	#if ($moonphase le "0.5") {
	#	$moonphase = $moonphase * 2 * 100;
	#} else {
	#	$moonphase = (1 - $moonphase) * 2 * 100;
	#}
	print F "-9999|"; # Moon percent Illuminated
	print F "-9999|"; # Moon: Age of Moon
	print F "-9999|"; # Moon: Phase of Moon
	print F "-9999|"; # Moon: Hemisphere
	
	$t = localtime($forecast_json->{forecast}->{daily}->[0]->{sunrise}); 
	print F sprintf("%02d", $t->hour), "|"; # Sunrise
	print F sprintf("%02d", $t->min), "|";
	$t = localtime($forecast_json->{forecast}->{daily}->[0]->{sunset});
	print F sprintf("%02d", $t->hour), "|"; # Sunset
	print F sprintf("%02d", $t->min), "|";
	print F "-9999|"; # Density of atmospheric ozone
	print F "-9999|"; # Sky (clouds) %
	print F $forecast_json->{forecast}->{daily}->[0]->{precip_probability}*100, "|"; # % of Precipitation
	print F "-9999|"; # Snow
close(F);

LOGOK "Saving current data to $lbplogdir/current.dat.tmp successfully.";

my @filecontent;
LOGDEB "Database content:";
open(F,"<$lbplogdir/current.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
	# Convert elevation from feet to meter
		LOGDEB "$_";
	}
close (F);

} # end current

#
# Fetch daily data
#

if ( $daily ) { # Start daily

# Saving new daily forecast data...
$error = 0;
open(F,">$lbplogdir/dailyforecast.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/dailyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	my $i = 1;
	for my $results( @{$forecast_json->{forecast}->{daily}} ){
		print F "$i|";
		$i++;
		print F $results->{day_start_local}, "|";
		$t = localtime($results->{day_start_local});
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
		print F sprintf("%.1f",$results->{air_temp_high}), "|";
		print F sprintf("%.1f",$results->{air_temp_low}), "|";
		print F $results->{precip_probability}, "|";
		print F "-9999|"; # Precipitation Forecast
		print F "-9999|"; # Snow Forecast
		print F "-9999|"; # Max. Wind Speed
		print F "-9999|"; # Max. Wind Dir Descript.
		print F "-9999|"; # Max. Wind Dir 
		print F "-9999|"; # Ave. Wind Speed
		print F "-9999|"; # Ave. Wind Dir Descript.
		print F "-9999|"; # Ave. Wind Dir
		print F "-9999|"; # Ave. Humidity
		print F "-9999|"; # Max. Humidity
		print F "-9999|"; # Min. Humidity
		$weather = $results->{icon}; # Icon Name
		$weather =~ s/\-night|\-day//; # No -night and -day
	    $weather =~ s/cc\-//; # No cc-
		$weather =~ s/\-//; # No -
		$weather =~ s/possibly/chance/; # added fr wf: replace possibly by chance
		$weather =~ tr/A-Z/a-z/; # All Lowercase
		my $icon = $weather;
		if ($weather eq "clear") {$weather = "1";}
		#elsif ($weather eq "sunny") {$weather = "1";}
		#elsif ($weather eq "partlysunny") {$weather = "3";}
		#elsif ($weather eq "mostlysunny") {$weather = "2";}
		elsif ($weather eq "partlycloudy") {$weather = "2";}
		#elsif ($weather eq "mostlycloudy") {$weather = "3";}
		elsif ($weather eq "cloudy") {$weather = "4";}
		#elsif ($weather eq "overcast") {$weather = "4";}
		#elsif ($weather eq "chanceflurries") {$weather = "18";}
		elsif ($weather eq "chancesleet") {$weather = "18";}
		elsif ($weather eq "chancesnow") {$weather = "20";}
		elsif ($weather eq "snowlikely") {$weather = "20"; $icon="chancesnow"} # added for wf
		#elsif ($weather eq "flurries") {$weather = "16";}
		elsif ($weather eq "sleet") {$weather = "19";}
		elsif ($weather eq "snow") {$weather = "21";}
		elsif ($weather eq "chancerain") {$weather = "12";}
		elsif ($weather eq "chancerainy") {$weather = "12"; $icon="chancerain"} # added for wf
		elsif ($weather eq "rainy") {$weather = "12"; $icon="chancerain"} # added for wf
		elsif ($weather eq "rain") {$weather = "13";}
		#elsif ($weather eq "chancetstorms") {$weather = "14";}
		#elsif ($weather eq "tstorms") {$weather = "15";}
		elsif ($weather eq "fog") {$weather = "6";}
		#elsif ($weather eq "hazy") {$weather = "5";}
		elsif ($weather eq "wind") {$weather = "22";}
		else {$weather = "0";}
		print F "$icon|"; # Icon
		print F "$weather|"; # Weather Code
		print F "$results->{conditions}|"; # Weather Description
		print F "-9999|"; # Density of atmospheric ozone
		# print F $results->{moonPhase}*100, "|"; 
		# See https://github.com/mschlenstedt/LoxBerry-Plugin-Weather4Lox/issues/37
		#my $moonphase = $results->{moonPhase};
		#if ($moonphase le "0.5") {
		#	$moonphase = $moonphase * 2 * 100;
		#} else {
		#	$moonphase = (1 - $moonphase) * 2 * 100;
		#}
		print F "-9999|"; # Moon: precent Illuminated
		print F "-9999|"; # 	Dew Point
		print F "-9999|"; # Pressure
		print F "-9999|"; #UV Index
		$t = localtime($results->{sunrise}); # Sunrise
		print F sprintf("%02d", $t->hour), "|"; 
		print F sprintf("%02d", $t->min), "|";
		$t = localtime($results->{sunset});# Sunset
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F "-9999|"; # Visibility
		print F "-9999|"; # ??
		print F "\n";
	}
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

} # end daily

#
# Fetch hourly data
#

if ( $hourly ) { # Start hourly

# Saving new hourly forecast data...
$error = 0;
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	$i = 1;
	my $n = 0;
	for my $results( @{$forecast_json->{forecast}->{hourly}} ){
		# Skip first dataset (eq to current)
		if ($n eq "0") {
			$n++;
			next;
		} 
		print F "$i|";
		$i++;
		print F $results->{time}, "|";
		$t = localtime($results->{time});
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
		print F sprintf("%.1f",$results->{air_temperature}), "|";
		print F sprintf("%.1f",$results->{feels_like}), "|";
		print F "-9999|"; # Heat Index
		print F $results->{relative_humidity}, "|";
		$wdir = $results->{wind_direction};
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
		print F "$results->{wind_direction}|";
		print F sprintf("%.1f",$results->{wind_avg} * 3.6), "|";
		#print F sprintf("%.1f",$results->{windGust} * 3.6), "|";
		print F sprintf("%.1f",$results->{feels_like}), "|";
		print F "$results->{sea_level_pressure}|";
		print F "-9999|"; # Dewpoint
		print F "-9999|"; # Sky (clouds) cover
		print F "-9999|"; # Sky Description
		print F "$results->{uv}|";
		print F $results->{precip}, "|";  # Quant. Precipitation FC in mm
		print F "-9999|"; # 	Snow Forecast
		print F $results->{precip_probability}, "|"; 
		$weather = $results->{icon};
		$weather =~ s/\-night|\-day//; # No -night and -day
		$weather =~ s/cc\-//; # No cc-
		$weather =~ s/\-//; # No -
		$weather =~ s/possibly/chance/; # replace possibly by chance
		$weather =~ tr/A-Z/a-z/; # All Lowercase
		my $icon = $weather;
		if ($weather eq "clear") {$weather = "1";}
		#elsif ($weather eq "sunny") {$weather = "1";}
		#elsif ($weather eq "partlysunny") {$weather = "3";}
		#elsif ($weather eq "mostlysunny") {$weather = "2";}
		elsif ($weather eq "partlycloudy") {$weather = "2";}
		#elsif ($weather eq "mostlycloudy") {$weather = "3";}
		elsif ($weather eq "cloudy") {$weather = "4";}
		#elsif ($weather eq "overcast") {$weather = "4";}
		#elsif ($weather eq "chanceflurries") {$weather = "18";}
		elsif ($weather eq "chancesleet") {$weather = "18";}
		elsif ($weather eq "chancesnow") {$weather = "20";}
		elsif ($weather eq "snowlikely") {$weather = "20";  $icon = "chancesnow"} # added for wf
		#elsif ($weather eq "flurries") {$weather = "16";}
		elsif ($weather eq "sleet") {$weather = "19";}
		elsif ($weather eq "snow") {$weather = "21";}
		elsif ($weather eq "chancerain") {$weather = "12";}
		elsif ($weather eq "chancerainy") {$weather = "12"; $icon="chancerain"} # added for wf
		elsif ($weather eq "rainy") {$weather = "12"; $icon = "chancerain"} # added for wf
		elsif ($weather eq "rain") {$weather = "13";}
		#elsif ($weather eq "chancetstorms") {$weather = "14";}
		#elsif ($weather eq "tstorms") {$weather = "15";}
		elsif ($weather eq "fog") {$weather = "6";}
		#elsif ($weather eq "hazy") {$weather = "5";}
		elsif ($weather eq "wind") {$weather = "22";}
		else {$weather = "0";}
		print F "$weather|"; # Weather Code
		print F "$icon|"; # Icon
		print F "$results->{conditions}|";
		print F "-9999|"; # Ozone
		print F "-9999|";
		print F "-9999|";
		print F "\n";
	}
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

if ($current) {

LOGINF "Cleaning $lbplogdir/current.dat.tmp";
open(F,"+<$lbplogdir/current.dat.tmp");
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
close(F);

my $currentname = "$lbplogdir/current.dat.tmp";
my $currentsize = -s ($currentname);
if ($currentsize > 100) {
        move($currentname, "$lbplogdir/current.dat");
}

}

if ($daily) {

LOGINF "Cleaning $lbplogdir/dailyforecast.dat.tmp";
open(F,"+<$lbplogdir/dailyforecast.dat.tmp");
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
close(F);

my $dailyname = "$lbplogdir/dailyforecast.dat.tmp";
my $dailysize = -s ($dailyname);
if ($dailysize > 100) {
        move($dailyname, "$lbplogdir/dailyforecast.dat");
}

}

if ($hourly) {

LOGINF "Cleaning $lbplogdir/hourlyforecast.dat.tmp";
open(F,"+<$lbplogdir/hourlyforecast.dat.tmp");
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

