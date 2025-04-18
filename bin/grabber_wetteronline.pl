#!/usr/bin/perl

# grabber for fetching data from wetteronline.de
# fetches weather data (current and forecast) from wetteronline.de

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
use JSON::PP;
#use JSON qw( decode_json );
use File::Copy;
use Getopt::Long;
use Time::Piece;
use HTTP::Request;
use DateTime;
#use DateTime::TimeZone;
#use DateTime::Format::ISO8601;
use Astro::MoonPhase;
use utf8;
use Encode qw(encode_utf8);
use HTML::Entities;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg             = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $city             = $pcfg->param("WETTERONLINE.STATION");
my $apikey           = $pcfg->param("WETTERONLINE.APIKEY");
my $timezone         = qx(cat /etc/timezone);
my $useragent        = $pcfg->param("WETTERONLINE.USERAGENT");
my $urlCurrent_raw   = $pcfg->param("WETTERONLINE.URL-CURRENT");
my $urlDaily_raw     = $pcfg->param("WETTERONLINE.URL-DAILY");
my $urlHourly_raw    = $pcfg->param("WETTERONLINE.URL-HOURLY");
chomp ($timezone);

my $error = 0;

my $json = JSON::PP->new->relaxed;
$json = $json->utf8(1);
$json = $json->relaxed(1);
$json = $json->allow_barekey(1);

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_wetteronline',
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

LOGSTART "Weather4Lox GRABBER_WETTERONLINE process started";
LOGDEB "This is $0 Version $version";

# Get data from wetteronline.de (HTTP Body request) for current conditions
sub getUrl {
    my ($myUrl, $useragent) = @_;
    LOGDEB("URL: " . $myUrl);
    
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(GET => $myUrl);
    $request->header('User-Agent' => $useragent);
    
    my $response = $ua->request($request);
    
    if ($response->is_success) {
        LOGDEB("Status: " . $response->status_line);
        return $response->decoded_content;
    } else {
        LOGCRIT("Failed to fetch data for $city. Status: " . $response->status_line);
        die "Quit fetching data.";
    }
}

# Searching for GID for selected city
sub findGid {
    my ($city, $body) = @_;
    
    if ($body =~ /gid : "([^"]+)"/s) {
        my $gid = $1;
		LOGDEB "The GID of city $city is $gid.";
        return $gid;
    } else {
		LOGCRIT "Failed to fetch GID for $city";
		die "Quit fetching GID.";
    }
}

# Getting current data and decoding to perl format
LOGINF "Fetching current data for location $city";
my $urlCurrent  = "$urlCurrent_raw$city";
my $body = getUrl($urlCurrent, $useragent);
my $currentCondMatch;
if ($body =~ /WO\.metadata\.p_city_weather\.nowcastBarMetadata = (\{.+\})$/m) {
	$currentCondMatch = $1;
}
my $firstHourlyMatch;
if ($body =~ /hourlyForecastElements\.push\((\{[^}]+\})/ms) {
	$firstHourlyMatch = $1;
}
my $geodataMatch;
if ($body =~ /WO\.geo = (\{(?:[^{}]*|(?1))*\});/s) {
	$geodataMatch = $1;
}
my $decodedBodyCurrent;
my $decodedBodyFirstHourly;
my $decodedGeodata;
$currentCondMatch = decode_entities($currentCondMatch);
$firstHourlyMatch = decode_entities($firstHourlyMatch);
$geodataMatch = decode_entities($geodataMatch);
$currentCondMatch = encode_utf8($currentCondMatch);
$firstHourlyMatch = encode_utf8($firstHourlyMatch);
$geodataMatch = encode_utf8($geodataMatch);
$decodedBodyCurrent = $json->decode($currentCondMatch);
$decodedBodyFirstHourly = $json->decode($firstHourlyMatch);
$decodedGeodata = $json->decode($geodataMatch);

# Getting daily data and decoding to perl format
LOGINF "Fetching daily data for location $city";
my $gid = findGid($city, $body);
my $urlDaily = "$urlDaily_raw$apikey&location_id=$gid&timezone=$timezone";
my $dailyData = getUrl($urlDaily, $useragent);
my $decodedDaily;
$dailyData = encode_utf8($dailyData);
$decodedDaily = $json->decode($dailyData);

# Getting hourly data and decoding to perl format
LOGINF "Fetching hourly data for location $city";
my $urlHourly = "$urlHourly_raw$apikey&location_id=$gid&timezone=$timezone";
my $hourlyData = getUrl($urlHourly, $useragent);
my $decodedHourly;
$hourlyData = encode_utf8($hourlyData);
$decodedHourly = $json->decode($hourlyData);

my $t;
my $weather;
my $code;
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
$t = DateTime->from_epoch(
	 epoch     => $decodedBodyCurrent->{hourly}->{currentTime},
         time_zone => $timezone,
);
LOGINF "Saving new Data for Timestamp $t to database.";

# Saving new current data...
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	
	# cur_date
	my $epoch_time = $decodedBodyCurrent->{hourly}->{currentTime};
	print F "$epoch_time|";
	
	# cur_date_des
	my $date = qx(TZ='$timezone' date -R -d "\@$epoch_time");
	chomp($date);
	print F "$date|";
	
	# cur_date_tz_des_sh
	my $tz_short = qx(TZ='$timezone' date +%Z);
	chomp ($tz_short);
	print F "$tz_short|";
	
	# cur_date_tz_des
	print F "$timezone|";
	
	# cur_date_tz
	my $tz_offset = qx(TZ='$timezone' date +%z);
	chomp ($tz_offset);
	print F "$tz_offset|";
	
	# cur_loc_n
	my $location = $decodedGeodata->{locationname};
	if (defined $decodedGeodata->{sublocationname} && $decodedGeodata->{sublocationname} ne "") {
		$location .= ", " . $decodedGeodata->{sublocationname};
	}
	print F "$location|";
	
	# cur_loc_c
	my @locs = split(/;/, $decodedGeodata->{path});
	print F "$locs[5]|";
	
	# cur_loc_ccode
	my $iso_code = $decodedGeodata->{location_info}->{geoObject}->{"iso-3166-1"};
	print F "$iso_code|";
	
	# cur_loc_lat
	my $lat = $decodedGeodata->{lat};
	print F "$lat|";
	
	# cur_loc_lon
	my $long = $decodedGeodata->{lon};
	print F "$long|";
	
	# cur_loc_el
	my $altitude = $decodedGeodata->{alt};
	print F "$altitude|";
	
	# cur_tt
	my $temp_aktuell;
		foreach my $entry (@{$decodedBodyCurrent->{nowcastBar}}) {
			if ($entry->{relTime} eq 'aktuell') {
				$temp_aktuell = $entry->{temp};
				last;
			}
		}
	print F sprintf("%.1f",$temp_aktuell), "|";
	
	# cur_tt_fl
	print F sprintf("%.1f",$decodedBodyFirstHourly->{apparentTemperature}), "|";
	
	# cur_hu
	my $humidity = $decodedBodyFirstHourly->{humidity};
	print F "$humidity|";
	
	# cur_w_dirdes && cur_w_dir
	my $wdir = $decodedBodyFirstHourly->{windDirectionShortSector};
	my $wind_deg;

	if ($wdir eq "N") {
		$wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'});  # Norden
		$wind_deg = 0;
	} elsif ($wdir eq "NO") {
		$wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}); # Nordosten
		$wind_deg = 45;
	} elsif ($wdir eq "O") {
		$wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'});  # Osten
		$wind_deg = 90;
	} elsif ($wdir eq "SO") {
		$wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}); # Südosten
		$wind_deg = 135;
	} elsif ($wdir eq "S") {
		$wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'});  # Süden
		$wind_deg = 180;
	} elsif ($wdir eq "SW") {
		$wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}); # Südwesten
		$wind_deg = 225;
	} elsif ($wdir eq "W") {
		$wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'});  # Westen
		$wind_deg = 270;
	} elsif ($wdir eq "NW") {
		$wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}); # Nordwesten
		$wind_deg = 315;
	} else {
		$wdirdes = "Unbekannte Richtung";
		$wind_deg = -1; # -1 für unbekannte Richtung
	}
	print F "$wdirdes|";
	print F "$wind_deg|";
	
	# cur_w_sp
	print F sprintf("%.1f",$decodedBodyFirstHourly->{windSpeedKmh}), "|";
	
	# cur_w_gu
	print F sprintf("%.1f",$decodedBodyFirstHourly->{windGustsKmh}), "|";
	
	# cur_w_ch
	print F sprintf("%.1f",$decodedBodyFirstHourly->{apparentTemperature}), "|";
	
	# cur_pr
	print F sprintf("%.0f",$decodedBodyFirstHourly->{airPressure}), "|";
	
	# cur_dp
	my $dew_point = sprintf("%.1f", 
		(243.04 * (log($humidity / 100) + 17.625 * $temp_aktuell / (243.04 + $temp_aktuell))) /
		(17.625 - (log($humidity / 100) + 17.625 * $temp_aktuell / (243.04 + $temp_aktuell)))
	);
	print F "$dew_point|";
	
	# cur_vis
	print F "-9999|";
	
	# cur_sr
	print F "-9999|";
	
	# cur_hi
	print F "-9999|";
	
	# cur_uvi
	my $uvi;
	if ($body =~ /<tr\s+id="uvi">.*?<p>(\d+)/s) {
		$uvi = $1;
	}
	print F sprintf("%.0f",$uvi), "|";
	
	# cur_prec_today
	print F "-9999|";
	
	# cur_prec_1hr
	my $hourlyPrecipitationAmount = $decodedBodyFirstHourly->{hourlyPrecipitationAmount};
	my ($value_after_minus) = $hourlyPrecipitationAmount =~ /-(.+)/;
	if ( $value_after_minus ) {
		print F sprintf("%.2f",$value_after_minus), "|";
	}
	else {
		print F "0|";
	}
	
	# cur_we_icon && cur_we_code
	my %translation_table = (					# translating wetteronline weather-code to openweather weather-code
		"800"  => ["so____", "mo____"],
		"721"  => ["ns____", "nm____"],
		"741"  => ["nb____"],
		"801"  => ["wb____", "mb____"],
		"802"  => ["bd____"],
		"500"  => ["wbs1__", "mbs1__"],
		"520"  => ["bdr1__"],
		"501"  => ["wbs2__", "mbs2__"],
		"521"  => ["bdr2__"],
		"522"  => ["bdr3__"],
		"615"  => ["wbsrs1", "mbsrs1", "bdsr1_"],
		"616"  => ["wbsrs2", "mbsrs2", "bdsr2_", "bdsr3_"],
		"620"  => ["wbsns1", "mbsns1", "bdsn1_"],
		"621"  => ["wbsns2", "mbsns2", "bdsn2_"],
		"601"  => ["bdsn2_"],
		"602"  => ["bdsn3_"],
		"622"  => ["wbsg__", "mbsg__", "bdsg__"],
		"200"  => ["wbg1__", "mbg1__", "bdg1__"],
		"211"  => ["wbg2__", "mbg2__", "bdg2__"],
		"511"  => ["bdgr1_", "bdgr2_"],
	);
  
	foreach my $entry (@{$decodedBodyCurrent->{nowcastBar}}) {
		if ($entry->{relTime} eq 'aktuell') {
			$weather = $entry->{symbol};
			last;
		}
	}
	$code = "";
	$icon = "";
	
	for my $translated_weather (keys %translation_table) {
		if (grep { $_ eq $weather } @{$translation_table{$translated_weather}}) {
			if ($translated_weather == 200) { $code = "18"; $icon = "tstorms" };
			if ($translated_weather == 201) { $code = "18"; $icon = "tstorms" };
			if ($translated_weather == 202) { $code = "19"; $icon = "tstorms" };
			if ($translated_weather == 210) { $code = "18"; $icon = "tstorms" };
			if ($translated_weather == 211) { $code = "18"; $icon = "tstorms" };
			if ($translated_weather == 212) { $code = "19"; $icon = "tstorms" };
			if ($translated_weather == 221) { $code = "19"; $icon = "tstorms" };
			if ($translated_weather == 230) { $code = "18"; $icon = "tstorms" };
			if ($translated_weather == 231) { $code = "18"; $icon = "tstorms" };
			if ($translated_weather == 232) { $code = "19"; $icon = "tstorms" };
			if ($translated_weather == 300) { $code = "13"; $icon = "chancerain" };
			if ($translated_weather == 301) { $code = "13"; $icon = "chancerain" };
			if ($translated_weather == 302) { $code = "13"; $icon = "chancerain" };
			if ($translated_weather == 310) { $code = "10"; $icon = "chancerain" };
			if ($translated_weather == 311) { $code = "11"; $icon = "rain" };
			if ($translated_weather == 312) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 313) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 314) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 321) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 500) { $code = "10"; $icon = "chancerain" };
			if ($translated_weather == 501) { $code = "11"; $icon = "rain" };
			if ($translated_weather == 502) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 503) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 504) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 511) { $code = "14"; $icon = "sleet" };
			if ($translated_weather == 520) { $code = "10"; $icon = "rain" };
			if ($translated_weather == 521) { $code = "11"; $icon = "rain" };
			if ($translated_weather == 522) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 531) { $code = "12"; $icon = "rain" };
			if ($translated_weather == 600) { $code = "20"; $icon = "snow" };
			if ($translated_weather == 601) { $code = "21"; $icon = "snow" };
			if ($translated_weather == 602) { $code = "21"; $icon = "snow" };
			if ($translated_weather == 611) { $code = "26"; $icon = "sleet" };
			if ($translated_weather == 612) { $code = "28"; $icon = "sleet" };
			if ($translated_weather == 613) { $code = "29"; $icon = "sleet" };
			if ($translated_weather == 615) { $code = "23"; $icon = "sleet" };
			if ($translated_weather == 616) { $code = "23"; $icon = "snow" };
			if ($translated_weather == 620) { $code = "21"; $icon = "snow" };
			if ($translated_weather == 621) { $code = "21"; $icon = "snow" };
			if ($translated_weather == 622) { $code = "21"; $icon = "snow" };
			if ($translated_weather == 701) { $code = "6";  $icon = "fog" };
			if ($translated_weather == 711) { $code = "6";  $icon = "fog" };
			if ($translated_weather == 721) { $code = "5";  $icon = "hazy" };
			if ($translated_weather == 731) { $code = "6";  $icon = "fog" };
			if ($translated_weather == 741) { $code = "6";  $icon = "fog" };
			if ($translated_weather == 751) { $code = "6";  $icon = "fog" };
			if ($translated_weather == 761) { $code = "6";  $icon = "fog" };
			if ($translated_weather == 762) { $code = "6";  $icon = "fog" };
			if ($translated_weather == 771) { $code = "19";  $icon = "tstorms" };
			if ($translated_weather == 781) { $code = "19";  $icon = "tstorms" };
			if ($translated_weather == 800) { $code = "1";  $icon = "clear" };
			if ($translated_weather == 801) { $code = "2";  $icon = "mostlysunny" };
			if ($translated_weather == 802) { $code = "3";  $icon = "mostlycloudy" };
			if ($translated_weather == 803) { $code = "4";  $icon = "cloudy" };
			if ($translated_weather == 804) { $code = "4";  $icon = "overcast" };
		}
	}
	if (!$icon) { $icon = "clear" };
	if (!$code) { $code = "1" };
	print F "$icon|";
	print F "$code|";
	
	# cur_we_des
	my $description_current;
		foreach my $entry (@{$decodedBodyCurrent->{nowcastBar}}) {
			if ($entry->{relTime} eq 'aktuell') {
				$description_current = $entry->{text};
				last;
			}
		}
	print F ucfirst($description_current) . "|";
	
	# Astro Data
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
#	# cur_moon_p
#	my $moonage_raw = $decodedBodyCurrent->{moonage};
#	my ($moonage) = $moonage_raw =~ /-(.+)/;
#	my $moonphase = $moonage / 30;
#	my $moonpercent = 0;
#	if ($moonphase le "0.5") {
#		$moonpercent = $moonphase * 2 * 100;
#	} else {
#		$moonpercent = (1 - $moonphase) * 2 * 100;
#	}
#	print F "$moonpercent|";
#	
#	# cur_moon_a
#	print F "$moonage|";
#	
#	# cur_moon_ph
#	print F sprintf("%.0f",$moonphase*100), "|";
#	
#	# cur_moon_h
#	print F "-9999|";
	
	# cur_sun_r && cur_sun_s
	my ($sunrise_hour, $sunrise_minute, $sunset_hour, $sunset_minute);
	if ($body =~ /<span id="sunrise" title="Sonnenaufgang">\s*(\d{2}):(\d{2})\s*<\/span>/) {
		($sunrise_hour, $sunrise_minute) = ($1, $2);
	}
	if ($body =~ /<span id="sunset" title="Sonnenuntergang">\s*(\d{2}):(\d{2})\s*<\/span>/) {
		($sunset_hour, $sunset_minute) = ($1, $2);
	}
	if (defined $sunrise_hour && defined $sunrise_minute && defined $sunset_hour && defined $sunset_minute) {
		print F sprintf("%02d", $sunrise_hour), "|";
		print F sprintf("%02d", $sunrise_minute), "|";
		print F sprintf("%02d", $sunset_hour), "|";
		print F sprintf("%02d", $sunset_minute), "|";
	} else {
		print F "-9999|";
		print F "-9999|";
		print F "-9999|";
		print F "-9999|";
	}

	# cur_ozone
	print F "-9999|";
	
	# cur_sky
	print F "-9999|";
	
	# cur_pop
	print F "$decodedBodyFirstHourly->{precipitationProbability}|";
		
	# cur_snow
	print F "$decodedBodyFirstHourly->{snowProbability}|";
	
	
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
	for my $results( @{$decodedDaily} ){
		# dfc0_per
		print F "$i|";
		$i++;
		
		# dfc0_date
		my $date_str = qx( TZ='$timezone' date  -d "$results->{date}" +'%Y-%m-%d' );
		chomp($date_str);
		my $t = Time::Piece->strptime($date_str, "%Y-%m-%d");
		my $epoch_time = $t->epoch;
		print F $epoch_time, "|";
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

		# dfc0_tt_h
		print F sprintf("%.1f",$results->{temperature}->{max}->{air}), "|";
		
		# dfc0_tt_l
		print F sprintf("%.1f",$results->{temperature}->{min}->{air}), "|";
		
		# dfc0_pop
		if ($results->{precipitation}{probability}) {
                        print F sprintf("%.0f",$results->{precipitation}{probability} * 100), "|";
                } else {
                        print F "0|";
                }
				
		# dfc0_prec
		if ($results->{precipitation}{details}{rainfall_amount}{millimeter}{interval_end}) {
			print F sprintf("%.2f",$results->{precipitation}{details}{rainfall_amount}{millimeter}{interval_end}), "|";
		} else {
			print F "0|";
		}
		
		# dfc0_snow
		if ($results->{precipitation}{details}{snow_height}{centimeter}{interval_end}) {
			print F sprintf("%.2f",$results->{precipitation}{details}{snow_height}{centimeter}{interval_end}), "|";
		} else {
			print F "0|";
		}
		
		# dfc0_w_sp_h
		print F sprintf("%.2f",$results->{wind}{speed}{kilometer_per_hour}{value}), "|";

		# dfc0_w_dirdes_h
		$wdir = $results->{wind}{direction};
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

		# dfc0_w_dir_h
		print F "$results->{wind}{direction}|";
		
		# dfc0_w_sp_a
		print F sprintf("%.2f",$results->{wind}{speed}{kilometer_per_hour}{value}), "|";
		
		# dfc0_w_dirdes_a
		print F "$wdirdes|";
		
		# dfc0_w_dir_a
		print F "$results->{wind}{direction}|";
		
		# dfc0_hu_a
		print F sprintf("%.0f",$results->{humidity} * 100), "|";
		
		# dfc0_hu_h && dfc0_hu_l
		my $min_humidity = 1;
		my $max_humidity = 0;
		my @dayparts = @{$results->{dayparts}};
		foreach my $daypart (@dayparts) {
			my $humidity = $daypart->{humidity};
			if ($humidity < $min_humidity) {
				$min_humidity = $humidity;
			}
			if ($humidity > $max_humidity) {
				$max_humidity = $humidity;
			}
		}
		print F sprintf("%.0f",$max_humidity * 100), "|";
		print F sprintf("%.0f",$min_humidity * 100), "|";
		
		# dfc0_we_icon && dfc0_we_code		
		my %translation_table = (					# translating wetteronline weather-code to openweather weather-code
			"800"  => ["so____", "mo____"],
			"721"  => ["ns____", "nm____"],
			"741"  => ["nb____"],
			"801"  => ["wb____", "mb____"],
			"802"  => ["bd____"],
			"500"  => ["wbs1__", "mbs1__"],
			"520"  => ["bdr1__"],
			"501"  => ["wbs2__", "mbs2__"],
			"521"  => ["bdr2__"],
			"522"  => ["bdr3__"],
			"615"  => ["wbsrs1", "mbsrs1", "bdsr1_"],
			"616"  => ["wbsrs2", "mbsrs2", "bdsr2_", "bdsr3_"],
			"620"  => ["wbsns1", "mbsns1", "bdsn1_"],
			"621"  => ["wbsns2", "mbsns2", "bdsn2_"],
			"601"  => ["bdsn2_"],
			"602"  => ["bdsn3_"],
			"622"  => ["wbsg__", "mbsg__", "bdsg__"],
			"200"  => ["wbg1__", "mbg1__", "bdg1__"],
			"211"  => ["wbg2__", "mbg2__", "bdg2__"],
			"511"  => ["bdgr1_", "bdgr2_"],
		);
	  
		$weather = $results->{symbol};
	  
		$code = "";
		$icon = "";
		
		for my $translated_weather (keys %translation_table) {
			if (grep { $_ eq $weather } @{$translation_table{$translated_weather}}) {
				if ($translated_weather == 200) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 201) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 202) { $code = "19"; $icon = "tstorms" };
				if ($translated_weather == 210) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 211) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 212) { $code = "19"; $icon = "tstorms" };
				if ($translated_weather == 221) { $code = "19"; $icon = "tstorms" };
				if ($translated_weather == 230) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 231) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 232) { $code = "19"; $icon = "tstorms" };
				if ($translated_weather == 300) { $code = "13"; $icon = "chancerain" };
				if ($translated_weather == 301) { $code = "13"; $icon = "chancerain" };
				if ($translated_weather == 302) { $code = "13"; $icon = "chancerain" };
				if ($translated_weather == 310) { $code = "10"; $icon = "chancerain" };
				if ($translated_weather == 311) { $code = "11"; $icon = "rain" };
				if ($translated_weather == 312) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 313) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 314) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 321) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 500) { $code = "10"; $icon = "chancerain" };
				if ($translated_weather == 501) { $code = "11"; $icon = "rain" };
				if ($translated_weather == 502) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 503) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 504) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 511) { $code = "14"; $icon = "sleet" };
				if ($translated_weather == 520) { $code = "10"; $icon = "rain" };
				if ($translated_weather == 521) { $code = "11"; $icon = "rain" };
				if ($translated_weather == 522) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 531) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 600) { $code = "20"; $icon = "snow" };
				if ($translated_weather == 601) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 602) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 611) { $code = "26"; $icon = "sleet" };
				if ($translated_weather == 612) { $code = "28"; $icon = "sleet" };
				if ($translated_weather == 613) { $code = "29"; $icon = "sleet" };
				if ($translated_weather == 615) { $code = "23"; $icon = "sleet" };
				if ($translated_weather == 616) { $code = "23"; $icon = "snow" };
				if ($translated_weather == 620) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 621) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 622) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 701) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 711) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 721) { $code = "5";  $icon = "hazy" };
				if ($translated_weather == 731) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 741) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 751) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 761) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 762) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 771) { $code = "19";  $icon = "tstorms" };
				if ($translated_weather == 781) { $code = "19";  $icon = "tstorms" };
				if ($translated_weather == 800) { $code = "1";  $icon = "clear" };
				if ($translated_weather == 801) { $code = "2";  $icon = "mostlysunny" };
				if ($translated_weather == 802) { $code = "3";  $icon = "mostlycloudy" };
				if ($translated_weather == 803) { $code = "4";  $icon = "cloudy" };
				if ($translated_weather == 804) { $code = "4";  $icon = "overcast" };
			}
		}
		if (!$icon) { $icon = "clear" };
		if (!$code) { $code = "1" };
		print F "$icon|";
		print F "$code|";

		# dfc0_we_des
		my %translation_table = (
			'so____'   => 'sonnig bzw. klar',
			'mo____'   => 'sonnig bzw. klar',
			'ns____'   => 'teils neblig',
			'nm____'   => 'teils neblig',
			'nb____'   => 'neblig',
			'wb____'   => 'unterschiedlich bewölkt',
			'mb____'   => 'unterschiedlich bewölkt',
			'bd____'   => 'bedeckt',
			'wbs1__'  => 'unterschiedlich bewölkt und vereinzelt Schauer',
			'mbs1__'  => 'unterschiedlich bewölkt und vereinzelt Schauer',
			'bdr1__'  => 'bedeckt, etwas Regen oder vereinzelt Schauer',
			'wbs2__'  => 'unterschiedlich bewölkt und Schauer',
			'mbs2__'  => 'unterschiedlich bewölkt und Schauer',
			'bdr2__'  => 'bedeckt, Regen oder Schauer',
			'bdr3__'  => 'bedeckt und ergiebiger Regen',
			'wbsrs1'  => 'unterschiedlich bewölkt und vereinzelt Schneeregenschauer',
			'mbsrs1'  => 'unterschiedlich bewölkt und vereinzelt Schneeregenschauer',
			'bdsr1_'  => 'bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer',
			'wbsrs2'  => 'unterschiedlich bewölkt und Schneeregenschauer',
			'mbsrs2'  => 'unterschiedlich bewölkt und Schneeregenschauer',
			'bdsr2_'  => 'bedeckt, Schneeregen oder Schneeregenschauer',
			'bdsr3_'  => 'bedeckt und ergiebiger Schneeregen',
			'wbsns1'  => 'unterschiedlich bewölkt und vereinzelt Schneeschauer',
			'mbsns1'  => 'unterschiedlich bewölkt und vereinzelt Schneeschauer',
			'bdsn1_'  => 'bedeckt, leichter Schneefall oder vereinzelt Schneeschauer',
			'wbsns2'  => 'unterschiedlich bewölkt und Schneeschauer',
			'mbsns2'  => 'unterschiedlich bewölkt und Schneeschauer',
			'bdsn2_'  => 'bedeckt, Schneefall oder Schneeschauer',
			'bdsn3_'  => 'bedeckt und ergiebiger Schneefall',
			'wbsg__'  => 'unterschiedlich bewölkt und Schneegewitter',
			'mbsg__'  => 'unterschiedlich bewölkt und Schneegewitter',
			'bdsg__'  => 'bedeckt und Schneegewitter',
			'wbg1__'  => 'unterschiedlich bewölkt, vereinzelt Schauer und Gewitter',
			'mbg1__'  => 'unterschiedlich bewölkt, vereinzelt Schauer und Gewitter',
			'bdg1__'  => 'bedeckt, vereinzelt Schauer und Gewitter',
			'wbg2__'  => 'unterschiedlich bewölkt, Schauer und Gewitter',
			'mbg2__'  => 'unterschiedlich bewölkt, Schauer und Gewitter',
			'bdg2__'  => 'bedeckt, Schauer und Gewitter',
			'bdgr1_'  => 'bedeckt und gefrierender Sprühregen',
			'bdgr2_'  => 'bedeckt und gefrierender Regen',
		);
		my $weather_text = $translation_table{$weather};
		print F ucfirst($weather_text) . "|";
		
		# dfc0_ozone
		print F "-9999|";
		
		# dfc0_moon_p
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($epoch_time);
		print F sprintf("%.2f",$moonillum*100), "|";
#		my $moonage = $results->{moon}{age};
#		my $moonphase = $moonage / 30;
#		my $moonpercent = 0;
#		if ($moonphase le "0.5") {
#			$moonpercent = $moonphase * 2 * 100;
#		} else {
#			$moonpercent = (1 - $moonphase) * 2 * 100;
#		}
#		print F "$moonpercent|";

		# dfc0_dp
		my $sum_dew_point = 0;
		my $count = 0;
		foreach my $daypart (@dayparts) {
			my $dew_point = $daypart->{dew_point}{celsius};
			$sum_dew_point += $dew_point;
			$count++;
		}
		my $average_dew_point = $sum_dew_point / $count;
		print F sprintf("%.1f",$average_dew_point), "|";
		
		# dfc0_pr
		print F sprintf("%.0f",$results->{air_pressure}{hpa}), "|";
		
		# dfc0_uvi
		print F sprintf("%.1f",$results->{uv_index}{value}),"|";
		
		# dfc0_sun_r
		my $sunrise_str = qx( TZ='$timezone' date  -d "$results->{sun}{rise}" +'%Y-%m-%d %H:%M' );
		chomp($sunrise_str);
		my $srt = Time::Piece->strptime($sunrise_str, "%Y-%m-%d %H:%M");
		print F sprintf("%02d", $srt->hour), "|";
		print F sprintf("%02d", $srt->minute), "|";
		
		# dfc0_sun_s
		my $sunset_str = qx( TZ='$timezone' date  -d "$results->{sun}{set}" +'%Y-%m-%d %H:%M' );
		chomp($sunset_str);
		my $srt = Time::Piece->strptime($sunset_str, "%Y-%m-%d %H:%M");
		print F sprintf("%02d", $srt->hour), "|";
		print F sprintf("%02d", $srt->minute), "|";
		
		#dfc0_vis
		print F "-9999";

		# dfc0_moon_a
		print F sprintf("%.2f",$moonage), "|";
		
		# dfc0_moon_ph
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
my $epoch_time = 0;
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	$i = 1;
	my $n = 0;
	for my $results( @{$decodedHourly->{hours}} ){
		# Skip first dataset (eq to current)
		if ($n eq "0") {
			$n++;
			next;
		}
		
		# hfc1_per
		print F "$i|";
		$i++;
		
		# hfc1_date
		my $date_str = qx( TZ='$timezone' date  -d "$results->{date}" +'%Y-%m-%d %H:%M' );
		chomp($date_str);
		my $t = Time::Piece->strptime($date_str, "%Y-%m-%d %H:%M");
		$epoch_time = $t->epoch;
		print F $epoch_time, "|";

		# hfc1_day && hfc1_month && hfc1_monthn && hfc1_monthn_sh && hfc1_year && hfc1_hour &&hfc1_min && hfc1_wday && hfc1_wday_sh
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

		# hfc1_tt
		print F sprintf("%.1f",$results->{temperature}{air}), "|";

		# hfc1_tt_fl
		print F sprintf("%.1f",$results->{temperature}{apparent}), "|";
		
		# hfc1_hi
		print F "-9999|";
		
		# hfc1_hu
		print F sprintf("%.0f",$results->{humidity} * 100), "|";
		
		# hfc1_w_dirdes
		$wdir = $results->{wind}{direction};
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

		# hfc1_w_dir
		print F "$results->{wind}{direction}|";
		
		# hfc1_w_sp
		print F sprintf("%.2f",$results->{wind}{speed}{kilometer_per_hour}{value}), "|";
		
		# hfc1_w_ch
		print F sprintf("%.1f",$results->{temperature}{apparent}), "|";
		
		# hfc1_pr
		print F sprintf("%.0f",$results->{air_pressure}{hpa}), "|";
		
		# hfc1_dp
		print F sprintf("%.1f",$results->{dew_point}{celsius}), "|";
		
		# hfc1_sky
		print F "-9999|";
		
		# hfc1_sky_des
		print F "-9999|";
		
		# hfc1_uvi
		print F "-9999|";
		
		# hfc1_prec
		if ($results->{precipitation}{details}{rainfall_amount}{millimeter}) {
			my $rfamount = ($results->{precipitation}{details}{rainfall_amount}{millimeter}{interval_begin} + $results->{precipitation}{details}{rainfall_amount}{millimeter}{interval_end}) / 2;
			print F sprintf("%.2f",$rfamount), "|";
		} else {
			print F "0|";
		}
		
		# hfc1_snow
		if ($results->{precipitation}{details}{snow_height}{centimeter}) {
			print F sprintf("%.2f",$results->{precipitation}{details}{snow_height}{centimeter}), "|";
		} else {
			print F "0|";
		}
		
		# hfc1_pop
		if ($results->{precipitation}{probability}) {
                        print F sprintf("%.0f",$results->{precipitation}{probability} * 100), "|";
                } else {
                        print F "0|";
                }
				
		# hfc1_we_icon && hfc1_we_code		
		my %translation_table = (					# translating wetteronline weather-code to openweather weather-code
			"800"  => ["so____", "mo____"],
			"721"  => ["ns____", "nm____"],
			"741"  => ["nb____"],
			"801"  => ["wb____", "mb____"],
			"802"  => ["bd____"],
			"500"  => ["wbs1__", "mbs1__"],
			"520"  => ["bdr1__"],
			"501"  => ["wbs2__", "mbs2__"],
			"521"  => ["bdr2__"],
			"522"  => ["bdr3__"],
			"615"  => ["wbsrs1", "mbsrs1", "bdsr1_"],
			"616"  => ["wbsrs2", "mbsrs2", "bdsr2_", "bdsr3_"],
			"620"  => ["wbsns1", "mbsns1", "bdsn1_"],
			"621"  => ["wbsns2", "mbsns2", "bdsn2_"],
			"601"  => ["bdsn2_"],
			"602"  => ["bdsn3_"],
			"622"  => ["wbsg__", "mbsg__", "bdsg__"],
			"200"  => ["wbg1__", "mbg1__", "bdg1__"],
			"211"  => ["wbg2__", "mbg2__", "bdg2__"],
			"511"  => ["bdgr1_", "bdgr2_"],
		);
	  
		$weather = $results->{symbol};
	  
		$code = "";
		$icon = "";
		
		for my $translated_weather (keys %translation_table) {
			if (grep { $_ eq $weather } @{$translation_table{$translated_weather}}) {
				if ($translated_weather == 200) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 201) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 202) { $code = "19"; $icon = "tstorms" };
				if ($translated_weather == 210) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 211) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 212) { $code = "19"; $icon = "tstorms" };
				if ($translated_weather == 221) { $code = "19"; $icon = "tstorms" };
				if ($translated_weather == 230) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 231) { $code = "18"; $icon = "tstorms" };
				if ($translated_weather == 232) { $code = "19"; $icon = "tstorms" };
				if ($translated_weather == 300) { $code = "13"; $icon = "chancerain" };
				if ($translated_weather == 301) { $code = "13"; $icon = "chancerain" };
				if ($translated_weather == 302) { $code = "13"; $icon = "chancerain" };
				if ($translated_weather == 310) { $code = "10"; $icon = "chancerain" };
				if ($translated_weather == 311) { $code = "11"; $icon = "rain" };
				if ($translated_weather == 312) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 313) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 314) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 321) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 500) { $code = "10"; $icon = "chancerain" };
				if ($translated_weather == 501) { $code = "11"; $icon = "rain" };
				if ($translated_weather == 502) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 503) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 504) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 511) { $code = "14"; $icon = "sleet" };
				if ($translated_weather == 520) { $code = "10"; $icon = "rain" };
				if ($translated_weather == 521) { $code = "11"; $icon = "rain" };
				if ($translated_weather == 522) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 531) { $code = "12"; $icon = "rain" };
				if ($translated_weather == 600) { $code = "20"; $icon = "snow" };
				if ($translated_weather == 601) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 602) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 611) { $code = "26"; $icon = "sleet" };
				if ($translated_weather == 612) { $code = "28"; $icon = "sleet" };
				if ($translated_weather == 613) { $code = "29"; $icon = "sleet" };
				if ($translated_weather == 615) { $code = "23"; $icon = "sleet" };
				if ($translated_weather == 616) { $code = "23"; $icon = "snow" };
				if ($translated_weather == 620) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 621) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 622) { $code = "21"; $icon = "snow" };
				if ($translated_weather == 701) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 711) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 721) { $code = "5";  $icon = "hazy" };
				if ($translated_weather == 731) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 741) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 751) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 761) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 762) { $code = "6";  $icon = "fog" };
				if ($translated_weather == 771) { $code = "19";  $icon = "tstorms" };
				if ($translated_weather == 781) { $code = "19";  $icon = "tstorms" };
				if ($translated_weather == 800) { $code = "1";  $icon = "clear" };
				if ($translated_weather == 801) { $code = "2";  $icon = "mostlysunny" };
				if ($translated_weather == 802) { $code = "3";  $icon = "mostlycloudy" };
				if ($translated_weather == 803) { $code = "4";  $icon = "cloudy" };
				if ($translated_weather == 804) { $code = "4";  $icon = "overcast" };
			}
		}
		if (!$icon) { $icon = "clear" };
		if (!$code) { $code = "1" };
		print F "$code|";
		print F "$icon|";

		# hfc1_we_des
		my %translation_table = (
			'so____'   => 'sonnig bzw. klar',
			'mo____'   => 'sonnig bzw. klar',
			'ns____'   => 'teils neblig',
			'nm____'   => 'teils neblig',
			'nb____'   => 'neblig',
			'wb____'   => 'unterschiedlich bewölkt',
			'mb____'   => 'unterschiedlich bewölkt',
			'bd____'   => 'bedeckt',
			'wbs1__'  => 'unterschiedlich bewölkt und vereinzelt Schauer',
			'mbs1__'  => 'unterschiedlich bewölkt und vereinzelt Schauer',
			'bdr1__'  => 'bedeckt, etwas Regen oder vereinzelt Schauer',
			'wbs2__'  => 'unterschiedlich bewölkt und Schauer',
			'mbs2__'  => 'unterschiedlich bewölkt und Schauer',
			'bdr2__'  => 'bedeckt, Regen oder Schauer',
			'bdr3__'  => 'bedeckt und ergiebiger Regen',
			'wbsrs1'  => 'unterschiedlich bewölkt und vereinzelt Schneeregenschauer',
			'mbsrs1'  => 'unterschiedlich bewölkt und vereinzelt Schneeregenschauer',
			'bdsr1_'  => 'bedeckt, leichter Schneeregen oder vereinzelt Schneeregenschauer',
			'wbsrs2'  => 'unterschiedlich bewölkt und Schneeregenschauer',
			'mbsrs2'  => 'unterschiedlich bewölkt und Schneeregenschauer',
			'bdsr2_'  => 'bedeckt, Schneeregen oder Schneeregenschauer',
			'bdsr3_'  => 'bedeckt und ergiebiger Schneeregen',
			'wbsns1'  => 'unterschiedlich bewölkt und vereinzelt Schneeschauer',
			'mbsns1'  => 'unterschiedlich bewölkt und vereinzelt Schneeschauer',
			'bdsn1_'  => 'bedeckt, leichter Schneefall oder vereinzelt Schneeschauer',
			'wbsns2'  => 'unterschiedlich bewölkt und Schneeschauer',
			'mbsns2'  => 'unterschiedlich bewölkt und Schneeschauer',
			'bdsn2_'  => 'bedeckt, Schneefall oder Schneeschauer',
			'bdsn3_'  => 'bedeckt und ergiebiger Schneefall',
			'wbsg__'  => 'unterschiedlich bewölkt und Schneegewitter',
			'mbsg__'  => 'unterschiedlich bewölkt und Schneegewitter',
			'bdsg__'  => 'bedeckt und Schneegewitter',
			'wbg1__'  => 'unterschiedlich bewölkt, vereinzelt Schauer und Gewitter',
			'mbg1__'  => 'unterschiedlich bewölkt, vereinzelt Schauer und Gewitter',
			'bdg1__'  => 'bedeckt, vereinzelt Schauer und Gewitter',
			'wbg2__'  => 'unterschiedlich bewölkt, Schauer und Gewitter',
			'mbg2__'  => 'unterschiedlich bewölkt, Schauer und Gewitter',
			'bdg2__'  => 'bedeckt, Schauer und Gewitter',
			'bdgr1_'  => 'bedeckt und gefrierender Sprühregen',
			'bdgr2_'  => 'bedeckt und gefrierender Regen',
		);
		my $weather_text = $translation_table{$weather};
		print F  ucfirst($weather_text) . "|";

		# Ozone
		print F "-9999|";
		
		# Solar Radiation
		print F "-9999|";
		
		# Visibility km
		print F sprintf("%.2f",$results->{visibility} / 1000), "|";
		
		# hfc0_moon_p
		my ( $moonphase,
		  $moonillum,
		  $moonage,
		  $moondist,
		  $moonang,
		  $sundist,
		  $sunang ) = phase($epoch_time);
		print F sprintf("%.2f",$moonillum*100), "|";

		# hfc0_moon_a
		print F sprintf("%.2f",$moonage), "|";
		
		# hfc0_moon_ph
		print F sprintf("%.2f",$moonphase*100), "|";
		
		print F "\n";
		}
		
	# WetterOnline only offers 32h hourly forecast. Fill data with "-9999" to have at least 72h of hourly forecast data for the weather emulator - otherwise Loxone app scrambles the webdata.
	while ($i <= 75) {
			
		# hfc1_per
		print F "$i|";
		$i++;

		# hfc1_date
		$epoch_time += 3600;
		print F "$epoch_time|";
		$t = Time::Piece->new ($epoch_time);

		# hfc1_day && hfc1_month && hfc1_monthn && hfc1_monthn_sh && hfc1_year && hfc1_hour &&hfc1_min && hfc1_wday && hfc1_wday_sh
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

		# writing rubish till dataset is full
		my $x = 0;
		while ($x < 25) {
			$x++;
			print F "-9999|";
		}
		print F "\n";
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
