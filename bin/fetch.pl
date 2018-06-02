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
use LWP::UserAgent;
use JSON qw( decode_json ); 
use File::Copy;
use Getopt::Long;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = "4.1.2";

#my $cfg             = new Config::Simple("$home/config/system/general.cfg");
#my $lang            = $cfg->param("BASE.LANG");
#my $installfolder   = $cfg->param("BASE.INSTALLFOLDER");
#my $miniservers     = $cfg->param("BASE.MINISERVERS");
#my $clouddns        = $cfg->param("BASE.CLOUDDNS");

my $pcfg             = new Config::Simple("$lbpconfigdir/wu4lox.cfg");
my $wuurl            = $pcfg->param("SERVER.WUURL");
my $wuapikey         = $pcfg->param("SERVER.WUAPIKEY");
my $wulang           = $pcfg->param("SERVER.WULANG");
my $stationid;
if ($pcfg->param("SERVER.STATIONTYP") eq "statid") {
	$stationid = $pcfg->param("SERVER.STATIONID");
} elsif ($pcfg->param("SERVER.STATIONTYP") eq "coord") {
	$stationid = $pcfg->param("SERVER.COORDLAT") . "," . $pcfg->param("SERVER.COORDLONG");
} else {
	$stationid = "autoip"
}

# Create a logging object
my $log = LoxBerry::Log->new ( 	name => 'fetch',
			filename => "$lbplogdir/wu4lox.log",
			append => 1,
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Due to a bug in the Logging routine, set the loglevel fix to 3
$log->loglevel(3);
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "WU4Lox FETCH process started";
LOGDEB "This is $0 Version $version";

# Get data from Wunderground Server (API request) for current conditions
my $wgqueryurlcr = "$wuurl\/$wuapikey\/conditions\/astronomy\/forecast\/hourly10day\/pws:1\/lang:$wulang\/q\/$stationid\.json";

LOGINF "Fetching Data for Station $stationid";
LOGDEB "URL: $wgqueryurlcr";

my $ua = new LWP::UserAgent;
my $res = $ua->get($wgqueryurlcr);
my $json = $res->decoded_content();

# Check status of request
my $urlstatus = $res->status_line;
my $urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch data for $stationid\. Status Code: $urlstatuscode";
  LOGEND "Exit.";
  exit 2;
} else {
  LOGOK "Data fetched successfully for $stationid";
}

# Decode JSON response from server
my $decoded_json = decode_json( $json );

# Write location data into database
LOGINF "Saving new Data for Timestamp $decoded_json->{current_observation}->{observation_time_rfc822} to database.";

# Saving new current data...
my $error = 0;
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
  		LOGEND "Exit.";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F "$decoded_json->{current_observation}->{local_epoch}|";
	print F "$decoded_json->{current_observation}->{local_time_rfc822}|";
	print F "$decoded_json->{current_observation}->{local_tz_short}|";
	print F "$decoded_json->{current_observation}->{local_tz_long}|";
	print F "$decoded_json->{current_observation}->{local_tz_offset}|";
	my $city = $decoded_json->{current_observation}->{display_location}->{city};
	my $test;
	eval "\$test = decode( 'UTF-8', \$city, Encode::FB_CROAK )";
	if ( !$@ ) {
		$city = Encode::decode("UTF-8", $city);
	}
	print F "$city|";
	print F "$decoded_json->{current_observation}->{display_location}->{state_name}|";
	print F "$decoded_json->{current_observation}->{display_location}->{country_iso3166}|";
	print F "$decoded_json->{current_observation}->{display_location}->{latitude}|";
	print F "$decoded_json->{current_observation}->{display_location}->{longitude}|";
	# Convert elevation from feet to meter
	my $elevation = $decoded_json->{current_observation}->{display_location}->{elevation};
	$elevation =~ s/(.*)\ ft$/$1/eg;
	$elevation = $elevation * 0.3048;
	print F "$elevation|";
	print F "$decoded_json->{current_observation}->{temp_c}|";
	print F "$decoded_json->{current_observation}->{feelslike_c}|";
	# Clean Humidity var
	my $humidity = $decoded_json->{current_observation}->{relative_humidity};
	$humidity =~ s/(.*)\%$/$1/eg;
	print F "$humidity|";
	print F "$decoded_json->{current_observation}->{wind_dir}|";
	print F "$decoded_json->{current_observation}->{wind_degrees}|";
	print F "$decoded_json->{current_observation}->{wind_kph}|";
	print F "$decoded_json->{current_observation}->{wind_gust_kph}|";
	print F "$decoded_json->{current_observation}->{windchill_c}|";
	print F "$decoded_json->{current_observation}->{pressure_mb}|";
	print F "$decoded_json->{current_observation}->{dewpoint_c}|";
	print F "$decoded_json->{current_observation}->{visibility_km}|";
	print F "$decoded_json->{current_observation}->{solarradiation}|";
	print F "$decoded_json->{current_observation}->{heat_index_c}|";
	print F "$decoded_json->{current_observation}->{UV}|";
	print F "$decoded_json->{current_observation}->{precip_today_metric}|";
	print F "$decoded_json->{current_observation}->{precip_1hr_metric}|";
	print F "$decoded_json->{current_observation}->{icon}|";;
	# Convert Weather string into Weather Code
	my $weather = $decoded_json->{current_observation}->{icon};
	#$weather =~ s/^Heavy//eg; # No Heavy
	#$weather =~ s/^Light//eg; # No Light
	#$weather =~ s/\ //eg; # No Spaces
	$weather =~ tr/A-Z/a-z/; # All Lowercase
	if ($weather eq "clear") {$weather = "1";}
	elsif ($weather eq "sunny") {$weather = "1";}
	elsif ($weather eq "partlysunny") {$weather = "3";}
	elsif ($weather eq "mostlysunny") {$weather = "2";}
	elsif ($weather eq "partlycloudy") {$weather = "2";}
	elsif ($weather eq "mostlycloudy") {$weather = "3";}
	elsif ($weather eq "cloudy") {$weather = "4";}
	elsif ($weather eq "overcast") {$weather = "4";}
	elsif ($weather eq "chanceflurries") {$weather = "18";}
	elsif ($weather eq "chancesleet") {$weather = "18";}
	elsif ($weather eq "chancesnow") {$weather = "20";}
	elsif ($weather eq "flurries") {$weather = "16";}
	elsif ($weather eq "sleet") {$weather = "19";}
	elsif ($weather eq "snow") {$weather = "21";}
	elsif ($weather eq "chancerain") {$weather = "12";}
	elsif ($weather eq "rain") {$weather = "13";}
	elsif ($weather eq "chancetstorms") {$weather = "14";}
	elsif ($weather eq "tstorms") {$weather = "15";}
	elsif ($weather eq "fog") {$weather = "6";}
	elsif ($weather eq "hazy") {$weather = "5";}
	else {$weather = "0";}
	print F "$weather|";
	print F "$decoded_json->{current_observation}->{weather}|";
	print F "$decoded_json->{moon_phase}->{percentIlluminated}|";
	print F "$decoded_json->{moon_phase}->{ageOfMoon}|";
	print F "$decoded_json->{moon_phase}->{phaseofMoon}|";
	print F "$decoded_json->{moon_phase}->{hemisphere}|";
	print F "$decoded_json->{sun_phase}->{sunrise}->{hour}|";
	print F "$decoded_json->{sun_phase}->{sunrise}->{minute}|";
	print F "$decoded_json->{sun_phase}->{sunset}->{hour}|";
	print F "$decoded_json->{sun_phase}->{sunset}->{minute}";
close(F);

LOGOK "Saving current data to $lbplogdir/current.dat.tmp successfully.";

my @filecontent;
LOGDEB "Database content:";
open(F,"<$lbplogdir/current.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

# Saving new daily forecast data...
$error = 0;
open(F,">$lbplogdir/dailyforecast.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/dailyforecast.dat.tmp";
  		LOGEND "Exit.";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	for my $results( @{$decoded_json->{forecast}->{simpleforecast}->{forecastday}} ){
		print F $results->{period} . "|";
		print F $results->{date}->{epoch} . "|";
		if(length($results->{date}->{month}) == 1) { $results->{date}->{month}="0$results->{date}->{month}"; }
		if(length($results->{date}->{day}) == 1) { $results->{date}->{day}="0$results->{date}->{day}"; }
		if(length($results->{date}->{hour}) == 1) { $results->{date}->{hour}="0$results->{date}->{hour}"; }
		if(length($results->{date}->{min}) == 1) { $results->{date}->{min}="0$results->{date}->{min}"; }
		print F "$results->{date}->{day}|";
		print F "$results->{date}->{month}|";
		print F "$results->{date}->{monthname}|";
		print F "$results->{date}->{monthname_short}|";
		print F "$results->{date}->{year}|";
		print F "$results->{date}->{hour}|";
		print F "$results->{date}->{min}|";
		print F "$results->{date}->{weekday}|";
		print F "$results->{date}->{weekday_short}|";
		print F "$results->{high}->{celsius}|";
		print F "$results->{low}->{celsius}|";
		print F "$results->{pop}|";
		print F "$results->{qpf_allday}->{mm}|";
		print F "$results->{snow_allday}->{cm}|";
		print F "$results->{maxwind}->{kph}|";
		print F "$results->{maxwind}->{dir}|";
		print F "$results->{maxwind}->{degrees}|";
		print F "$results->{avewind}->{kph}|";
		print F "$results->{avewind}->{dir}|";
		print F "$results->{avewind}->{degrees}|";
		print F "$results->{avehumidity}|";
		print F "$results->{maxhumidity}|";
		print F "$results->{minhumidity}|";
		print F "$results->{icon}|";
		# Convert Weather string into Weather Code
		my $weather = $results->{icon};
		#$weather =~ s/^Heavy//eg; # No Heavy
		#$weather =~ s/^Light//eg; # No Light
		#$weather =~ s/\ //eg; # No Spaces
		$weather =~ tr/A-Z/a-z/; # All Lowercase
		if ($weather eq "clear") {$weather = "1";}
		elsif ($weather eq "sunny") {$weather = "1";}
		elsif ($weather eq "partlysunny") {$weather = "3";}
		elsif ($weather eq "mostlysunny") {$weather = "2";}
		elsif ($weather eq "partlycloudy") {$weather = "2";}
		elsif ($weather eq "mostlycloudy") {$weather = "3";}
		elsif ($weather eq "cloudy") {$weather = "4";}
		elsif ($weather eq "overcast") {$weather = "4";}
		elsif ($weather eq "chanceflurries") {$weather = "18";}
		elsif ($weather eq "chancesleet") {$weather = "18";}
		elsif ($weather eq "chancesnow") {$weather = "20";}
		elsif ($weather eq "flurries") {$weather = "16";}
		elsif ($weather eq "sleet") {$weather = "19";}
		elsif ($weather eq "snow") {$weather = "21";}
		elsif ($weather eq "chancerain") {$weather = "12";}
		elsif ($weather eq "rain") {$weather = "13";}
		elsif ($weather eq "chancetstorms") {$weather = "14";}
		elsif ($weather eq "tstorms") {$weather = "15";}
		elsif ($weather eq "fog") {$weather = "6";}
		elsif ($weather eq "hazy") {$weather = "5";}
		else {$weather = "0";}
		print F "$weather|";
		print F "$results->{conditions}";
		print F "\n";
	}
close(F);

LOGOK "Saving current data to $lbplogdir/dailyforecast.dat successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/dailyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

# Saving new hourly forecast data...
$error = 0;
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
  		LOGEND "Exit.";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	my $i = 1;
	for my $results( @{$decoded_json->{hourly_forecast}} ){
		print F "$i|";
		print F "$results->{FCTTIME}->{epoch}|";
		print F "$results->{FCTTIME}->{mday_padded}|";
		print F "$results->{FCTTIME}->{mon_padded}|";
		print F "$results->{FCTTIME}->{month_name}|";
		print F "$results->{FCTTIME}->{month_name_abbrev}|";
		print F "$results->{FCTTIME}->{year}|";
		print F "$results->{FCTTIME}->{hour_padded}|";
		print F "$results->{FCTTIME}->{min}|";
		print F "$results->{FCTTIME}->{weekday_name}|";
		print F "$results->{FCTTIME}->{weekday_name_abbrev}|";
		print F "$results->{temp}->{metric}|";
		print F "$results->{feelslike}->{metric}|";
		print F "$results->{heatindex}->{metric}|";
		print F "$results->{humidity}|";
		print F "$results->{wdir}->{dir}|";
		print F "$results->{wdir}->{degrees}|";
		print F "$results->{wspd}->{metric}|";
		print F "$results->{windchill}->{metric}|";
		print F "$results->{mslp}->{metric}|";
		print F "$results->{dewpoint}->{metric}|";
		print F "$results->{sky}|";
		print F "$results->{wx}|";
		print F "$results->{uvi}|";
		print F "$results->{qpf}->{metric}|";
		print F "$results->{snow}->{metric}|";
		print F "$results->{pop}|";
		print F "$results->{fctcode}|";
		print F "$results->{icon}|";
		print F "$results->{condition}";
		print F "\n";
		$i++;
	}
close(F);

LOGOK "Saving current data to $lbplogdir/hourlyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/hourlyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

# Clean Up Databases
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

# Test downloaded files
my $currentname = "$lbplogdir/current.dat.tmp";
my $currentsize = -s ($currentname);
if ($currentsize > 100) {
        move($currentname, "$lbplogdir/current.dat");
}
my $dailyname = "$lbplogdir/dailyforecast.dat.tmp";
my $dailysize = -s ($dailyname);
if ($dailysize > 100) {
        move($dailyname, "$lbplogdir/dailyforecast.dat");
}
my $hourlyname = "$lbplogdir/hourlyforecast.dat.tmp";
my $hourlysize = -s ($hourlyname);
if ($hourlysize > 100) {
        move($hourlyname, "$lbplogdir/hourlyforecast.dat");
}

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Data to Loxone
if ($verbose) { 
  system ("$lbpbindir/datatoloxone.pl -v");
} else {
  system ("$lbpbindir/datatoloxone.pl");
}

# Exit
LOGEND "Exit.";
exit;

