#!/usr/bin/perl

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


##########################################################################
# Modules
##########################################################################

use Config::Simple '-strict';
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use LWP::UserAgent;
use JSON qw( decode_json );
use LoxBerry::System;
use LoxBerry::Web;
#use warnings;
#use strict;

##########################################################################
# Variables
##########################################################################

# Read Form
my $cgi = CGI->new;
$cgi->import_names('R');

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

# Settings
my $cfg = new Config::Simple("$lbpconfigdir/weather4lox.cfg");

$cfg->param("OPENWEATHER.URL", "https://api.openweathermap.org/data");
$cfg->param("WUNDERGROUND.URL", "https://api.weather.com/v2/pws/observations/current");
$cfg->param("FOSHK.URL", "observations/current/json/units=m");
$cfg->param("WEATHERFLOW.URL", "https://swd.weatherflow.com/swd/rest");
$cfg->param("VISUALCROSSING.URL", "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline");

$cfg->save();

#########################################################################
# Parameter
#########################################################################

my $error;

##########################################################################
# Main program
##########################################################################

# Template
my $template = HTML::Template->new(
    filename => "$lbptemplatedir/settings.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
    associate => $cfg,
);

# Language
my %L = LoxBerry::Web::readlanguage($template, "language.ini");

# Save Form 1 (Server Settings)
if ($R::saveformdata1) {

  	$template->param( FORMNO => '1' );
	$R::wucoordlat =~ tr/,/./;
	$R::wucoordlong =~ tr/,/./;
	$R::openweathercoordlat =~ tr/,/./;
	$R::openweathercoordlong =~ tr/,/./;
	$R::visualcrossingcoordlat =~ tr/,/./;
	$R::visualcrossingcoordlong =~ tr/,/./;

	# Check for Station : OPENWEATHER
	if ($R::weatherservice eq "openweather") {
		our $url = $cfg->param("OPENWEATHER.URL");
		our $querystation = "lat=" . $R::openweathercoordlat . "&lon=" . $R::openweathercoordlong;
		# 1. attempt to query OpenWeather
		&openweatherquery;
		$found = 0;
		if ( !$error && $decoded_json->{lat} ) {
			$found = 1;
		}
		if ( !$error && !$found ) {
			$error = $L{'SETTINGS.ERR_NO_WEATHERSTATION'};
		}
	}

	# Check for Station : WEATHERFLOW
	if ($R::weatherservice eq "weatherflow") {
		our $url = $cfg->param("WEATHERFLOW.URL");
		#our $querystation = "lat=" . $R::weatherflowcoordlat . "&lon=" . $R::weatherflowcoordlong;
		# 1. attempt to query OpenWeather
		&weatherflowquery;
		$found = 0;
		if ( !$error && $decoded_json->{station_id} ) {
			$found = 1;
		}
		if ( !$error && !$found ) {
			$error = $L{'SETTINGS.ERR_NO_WEATHERSTATION'};
		}
	}

	# Check for Station : VISUALCROSSING
	if ($R::weatherservice eq "visualcrossing") {
		our $url = $cfg->param("VISUALCROSSING.URL");
		our $querystation = $R::visualcrossingcoordlat . "," . $R::visualcrossingcoordlong;
		# 1. attempt to query VisualCrossing
		&visualcrossingquery;
		$found = 0;
		if ( !$error && $decoded_json->{latitude} ) {
			$found = 1;
		}
		if ( !$error && !$found ) {
			$error = $L{'SETTINGS.ERR_NO_WEATHERSTATION'};
		}
	}

	# Check for Station : WUNDERGROUND
	if ($R::wugrabber) {
		our $url = $cfg->param("WUNDERGROUND.URL");
		$querystation = $R::wustationid;
		&wuquery;
		$found = 0;
		if ( !$error && $decoded_json->{observations}->[0]->{epoch} ) {
			$found = 1;
		}
		if ( !$error && !$found ) {
			$error = $L{'SETTINGS.ERR_NO_WEATHERSTATION'};
		}
	}

	# OK - now installing...

	# Write configuration file(s)
	$cfg->param("WUNDERGROUND.APIKEY", "$R::wuapikey");
	$cfg->param("WUNDERGROUND.STATIONTYP", "$R::wustationtyp");
	$cfg->param("WUNDERGROUND.STATIONID", "$R::wustationid");
	$cfg->param("WUNDERGROUND.COORDLAT", "$R::wucoordlat");
	$cfg->param("WUNDERGROUND.COORDLONG", "$R::wucoordlong");
	$cfg->param("WUNDERGROUND.LANG", "$R::wulang");

	$cfg->param("OPENWEATHER.APIKEY", "$R::openweatherapikey");
	$cfg->param("OPENWEATHER.COORDLAT", "$R::openweathercoordlat");
	$cfg->param("OPENWEATHER.COORDLONG", "$R::openweathercoordlong");
	$cfg->param("OPENWEATHER.LANG", "$R::openweatherlang");
	$cfg->param("OPENWEATHER.STATION", "$R::openweathercity");
	$cfg->param("OPENWEATHER.COUNTRY", "$R::openweathercountry");

	$cfg->param("WEATHERFLOW.APIKEY", "$R::weatherflowapikey");
	$cfg->param("WEATHERFLOW.LANG", "$R::weatherflowlang");
	$cfg->param("WEATHERFLOW.CITY", "$R::weatherflowcity");
	$cfg->param("WEATHERFLOW.COUNTRY", "$R::weatherflowcountry");
	$cfg->param("WEATHERFLOW.STATIONID", "$R::weatherflowstationid");

	$cfg->param("VISUALCROSSING.APIKEY", "$R::visualcrossingapikey");
	$cfg->param("VISUALCROSSING.COORDLAT", "$R::visualcrossingcoordlat");
	$cfg->param("VISUALCROSSING.COORDLONG", "$R::visualcrossingcoordlong");
	$cfg->param("VISUALCROSSING.LANG", "$R::visualcrossinglang");
	$cfg->param("VISUALCROSSING.STATION", "$R::visualcrossingcity");
	$cfg->param("VISUALCROSSING.COUNTRY", "$R::visualcrossingcountry");

	$cfg->param("FOSHK.SERVER", "$R::foshkserver");
	$cfg->param("FOSHK.PORT", "$R::foshkport");

	$cfg->param("SERVER.PWSCATCHUPLOADGRABBER", "$R::pwscatchuploadgrabber");
	$cfg->param("SERVER.WUGRABBER", "$R::wugrabber");
	$cfg->param("SERVER.WUGRABBER", "$R::wugrabber");
	$cfg->param("SERVER.LOXGRABBER", "$R::loxgrabber");
	$cfg->param("SERVER.FOSHKGRABBER", "$R::foshkgrabber");
	$cfg->param("SERVER.USEALTERNATEDFC", "$R::usealternatedfc");
	$cfg->param("SERVER.USEALTERNATEHFC", "$R::usealternatehfc");
	$cfg->param("SERVER.GETDATA", "$R::getdata");
	$cfg->param("SERVER.CRON", "$R::cron");
	$cfg->param("SERVER.CRON_ALTERNATE", "$R::cron_alternate");
	$cfg->param("SERVER.METRIC", "$R::metric");
	$cfg->param("SERVER.WEATHERSERVICE", "$R::weatherservice");
	$cfg->param("SERVER.WEATHERSERVICEDFC", "$R::weatherservicedfc");
	$cfg->param("SERVER.WEATHERSERVICEHFC", "$R::weatherservicehfc");

	$cfg->save();

	# Create Cronjob
	if ($R::getdata eq "1"){
		system ("ln -s $lbpbindir/cronjob.pl $lbhomedir/system/cron/cron.01min/$lbpplugindir");
	} else {
		unlink ("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
	}

	# Error template
	if ($error) {
		# Template output
		&error;

	# Save template
	} else {
		# Template output
		&save;
	}
	exit;

}

# Save Form 2 (Miniserver)
if ($R::saveformdata2) {

  	$template->param( FORMNO => '2' );

	my $dfc;
	for (my $i=1;$i<=8;$i++) {
		if ( ${"R::dfc$i"} ) {
			if ( !$dfc ) {
				$dfc = $i;
			} else {
				$dfc = $dfc . ";" . $i;
			}
		}
	}
	my $hfc;
	for ($i=1;$i<=48;$i++) {
		if ( ${"R::hfc$i"} ) {
			if ( !$hfc ) {
				$hfc = $i;
			} else {
				$hfc = $hfc . ";" . $i;
			}
		}
	}

	# Write configuration file(s)
	$cfg->param("SERVER.SENDDFC", "$dfc");
	$cfg->param("SERVER.SENDHFC", "$hfc");
	$cfg->param("SERVER.SENDUDP", "$R::sendudp");
	$cfg->param("SERVER.UDPPORT", "$R::udpport");
	$cfg->param("SERVER.MSNO", "$R::msno");
	$cfg->param("SERVER.TOPIC", "$R::mqtttopic");

	$cfg->save();

	# Template output
	&save;

	exit;

}

# Save Form 3 (Website)
if ($R::saveformdata3) {

  	$template->param( FORMNO => '3' );

	# Write configuration file(s)
	$cfg->param("SERVER.EMU", "$R::emu");
	$cfg->param("WEB.THEME", "$R::theme");
	$cfg->param("WEB.ICONSET", "$R::iconset");
	$cfg->param("WEB.LANG", "$R::themelang");

	$cfg->save();

	# Enable/Disable CloudEmu
	if ( $R::emu ) {
		system("sudo $lbpbindir/cloudemu enable > /dev/null 2>&1");
	} else {
		system("sudo $lbpbindir/cloudemu disable > /dev/null 2>&1");
	}

	# Template output
	&save;

	exit;

}

# Navbar
our %navbar;
$navbar{1}{Name} = "$L{'SETTINGS.LABEL_SERVER_SETTINGS'}";
$navbar{1}{URL} = 'index.cgi?form=1';

$navbar{2}{Name} = "$L{'SETTINGS.LABEL_MINISERVERCONNECTION'}";
$navbar{2}{URL} = 'index.cgi?form=2';

$navbar{3}{Name} = "$L{'SETTINGS.LABEL_CLOUDEMU'} / $L{'SETTINGS.LABEL_WEBSITE'}";
$navbar{3}{URL} = 'index.cgi?form=3';

$navbar{99}{Name} = "$L{'SETTINGS.LABEL_LOG'}";
$navbar{99}{URL} = 'index.cgi?form=99';

# Menu: Server
if ($R::form eq "1" || !$R::form) {

  $navbar{1}{active} = 1;
  $template->param( "FORM1", 1);

  my @values;
  my %labels;

  # Weather Service
  @values = ( 'openweather', 'visualcrossing', 'weatherflow', );
  %labels = (
        'openweather' => 'OpenWeatherMap',
        'visualcrossing' => 'Visual Crossing',
        'weatherflow' => 'Weatherflow',
    );
  my $wservice = $cgi->popup_menu(
        -name    => 'weatherservice',
        -id      => 'weatherservice',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.WEATHERSERVICE'),
    );
  $template->param( WEATHERSERVICE => $wservice );

  # DFC Weather Service
  @values = ( 'openweather', 'visualcrossing', 'weatherflow', );
  %labels = (
        'openweather' => 'OpenWeatherMap',
        'visualcrossing' => 'Visual Crossing',
        'weatherflow' => 'Weatherflow',
    );
  my $wservicedfc = $cgi->popup_menu(
        -name    => 'weatherservicedfc',
        -id      => 'weatherservicedfc',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.WEATHERSERVICEDFC'),
    );
  $template->param( WEATHERSERVICEDFC => $wservicedfc );

  # Use alternate DFC Weather Service
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $usealternatedfc = $cgi->popup_menu(
        -name    => 'usealternatedfc',
        -id      => 'usealternatedfc',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.USEALTERNATEDFC'),
    );
  $template->param( USEALTERNATEDFC => $usealternatedfc );

  # HFC Weather Service
  @values = ( 'openweather', 'visualcrossing', 'weatherflow', );
  %labels = (
        'openweather' => 'OpenWeatherMap',
        'visualcrossing' => 'Visual Crossing',
        'weatherflow' => 'Weatherflow',
    );
  my $wservicehfc = $cgi->popup_menu(
        -name    => 'weatherservicehfc',
        -id      => 'weatherservicehfc',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.WEATHERSERVICEHFC'),
    );
  $template->param( WEATHERSERVICEHFC => $wservicehfc );

  # Use alternate HFC Weather Service
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $usealternatehfc = $cgi->popup_menu(
        -name    => 'usealternatehfc',
        -id      => 'usealternatehfc',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.USEALTERNATEHFC'),
    );
  $template->param( USEALTERNATEHFC => $usealternatehfc );

  # Units
  @values = ('1', '0' );
  %labels = (
        '1' => $L{'SETTINGS.LABEL_METRIC'},
        '0' => $L{'SETTINGS.LABEL_IMPERIAL'},
    );
  my $metric = $cgi->popup_menu(
        -name    => 'metric',
        -id      => 'metric',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.METRIC'),
    );
  $template->param( METRIC => $metric );

  # LoxGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $loxgrabber = $cgi->popup_menu(
        -name    => 'loxgrabber',
        -id      => 'loxgrabber',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.LOXGRABBER'),
    );
  $template->param( LOXGRABBER => $loxgrabber );

  # WUGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $wugrabber = $cgi->popup_menu(
        -name    => 'wugrabber',
        -id      => 'wugrabber',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.WUGRABBER'),
    );
  $template->param( WUGRABBER => $wugrabber );

  # FOSHKGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $foshkgrabber = $cgi->popup_menu(
        -name    => 'foshkgrabber',
        -id      => 'foshkgrabber',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.FOSHKGRABBER'),
    );
  $template->param( FOSHKGRABBER => $foshkgrabber );

  # PWSCatchUploadGrabber
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $pwscatchuploadgrabber = $cgi->popup_menu(
        -name    => 'pwscatchuploadgrabber',
        -id      => 'pwscatchuploadgrabber',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.PWSCATCHUPLOADGRABBER'),
    );
  $template->param( PWSCATCHUPLOADGRABBER => $pwscatchuploadgrabber );

  # GetData
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $getdata = $cgi->popup_menu(
        -name    => 'getdata',
        -id      => 'getdata',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.GETDATA'),
    );
  $template->param( GETDATA => $getdata );

  # Cron
  @values = ('1', '3', '5', '10', '15', '30', '60' );
  %labels = (
        '1' => $L{'SETTINGS.LABEL_1MINUTE'},
        '3' => $L{'SETTINGS.LABEL_3MINUTE'},
        '5' => $L{'SETTINGS.LABEL_5MINUTE'},
        '10' => $L{'SETTINGS.LABEL_10MINUTE'},
        '15' => $L{'SETTINGS.LABEL_15MINUTE'},
        '30' => $L{'SETTINGS.LABEL_30MINUTE'},
        '60' => $L{'SETTINGS.LABEL_60MINUTE'},
    );
  my $cron = $cgi->popup_menu(
        -name    => 'cron',
        -id      => 'cron',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.CRON'),
    );
  $template->param( CRON => $cron );

  # Cron Forecast
  @values = ('0', '1', '3', '5', '10', '15', '30', '60' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_SAME_AS_DEFAULT'},
        '1' => $L{'SETTINGS.LABEL_1MINUTE'},
        '3' => $L{'SETTINGS.LABEL_3MINUTE'},
        '5' => $L{'SETTINGS.LABEL_5MINUTE'},
        '10' => $L{'SETTINGS.LABEL_10MINUTE'},
        '15' => $L{'SETTINGS.LABEL_15MINUTE'},
        '30' => $L{'SETTINGS.LABEL_30MINUTE'},
        '60' => $L{'SETTINGS.LABEL_60MINUTE'},
    );
  my $cron_alternate = $cgi->popup_menu(
        -name    => 'cron_alternate',
        -id      => 'cron_alternate',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.CRON_ALTERNATE'),
    );
  $template->param( CRON_ALTERNATE => $cron_alternate );

  # OPenweather Language
  @values = ('af', 'ar', 'az', 'bg', 'ca', 'cz', 'da', 'de', 'el', 'en', 'es', 'eu', 'fa', 'fi', 'fr', 'gl', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'kr', 'la', 'lt', 'mk', 'no', 'nl', 'pl', 'pt', 'pt_br', 'ro', 'ru', 'se', 'sk', 'sl', 'sr', 'th', 'tr', 'uk', 'vi', 'zh_cn', 'zh_tw', 'zu');

  %labels = (
	'af' => 'Africaans',
	'ar' => 'Arabic',
	'az' => 'Azerbaijani',
	'bg' => 'Bulgarian',
	'ca' => 'Catalan',
	'ca' => 'Catalan',
	'cz' => 'Czech',
	'da' => 'Danish',
	'de' => 'German',
	'el' => 'Greek',
	'en' => 'English',
	'es' => 'Spanish',
	'eu' => 'Basque',
	'fa' => 'Persian (Farsi)',
	'fi' => 'Finnish',
	'fr' => 'French',
	'hr' => 'Croatian',
	'ga' => 'Galician',
	'he' => 'Hebrew',
	'hi' => 'Hindi',
	'hr' => 'Croatian',
	'hu' => 'Hungarian',
	'id' => 'Indonesian',
	'it' => 'Italian',
	'ja' => 'Japanese',
	'kr' => 'Korean',
	'la' => 'Latvian',
	'lt' => 'Lithuanian',
	'mk' => 'Macedonian',
	'no' => 'Norwegian',
	'nl' => 'Dutch',
	'pl' => 'Polish',
	'pt' => 'Portuguese',
	'pt_br' => 'Portuguese Brasil',
	'ro' => 'Romanian',
	'ru' => 'Russian',
	'se' => 'Swedish',
	'sk' => 'Slovak',
	'sl' => 'Slovenian',
	'sr' => 'Serbian',
	'th' => 'Thai',
	'tr' => 'Turkish',
	'uk' => 'Ukrainian',
	'vi' => 'Vietnamese',
	'zh_cn' => 'simplified Chinese',
	'zh_tw' => 'traditional Chinese',
	'zu' => 'Zulu',
    );
  my $openweatherlang = $cgi->popup_menu(
        -name    => 'openweatherlang',
        -id      => 'openweatherlang',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('OPENWEATHER.LANG'),
    );
  $template->param( OPENWEATHERLANG => $openweatherlang );

  # Weatherflow Language
  @values = ('en');

  %labels = (
	'en' => 'English',
    );
  my $weatherflowlang = $cgi->popup_menu(
        -name    => 'weatherflowlang',
        -id      => 'weatherflowlang',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('WEATHERFLOW.LANG'),
    );
  $template->param( WEATHERFLOWLANG => $weatherflowlang );

  # VisualCrossing Language
  @values = ('de', 'en', 'es', 'fi', 'fr', 'it', 'ja', 'ko', 'pt', 'ru', 'nl', 'sr', 'zh');

  %labels = (
	'de' => 'German',
	'en' => 'English',
	'es' => 'Spanish',
	'fi' => 'Finnish',
	'fr' => 'French',
	'it' => 'Italian',
	'ja' => 'Japanese',
	'ko' => 'Korean',
	'nl' => 'Netherlands',
	'pt' => 'Portuguese',
	'ru' => 'Russian',
	'sr' => 'Serbian',
	'zh' => 'simplified Chinese',
    );
  my $visualcrossinglang = $cgi->popup_menu(
        -name    => 'visualcrossinglang',
        -id      => 'visualcrossinglang',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('VISUALCROSSING.LANG'),
    );
  $template->param( VISUALCROSSINGLANG => $visualcrossinglang );

  # Statiotyp
  @values = ('statid', 'coord', 'autoip');
  %labels = (
        'statid' => $L{'SETTINGS.LABEL_STATIONID'},
        'coord' => $L{'SETTINGS.LABEL_COORDINATES'},
        'autoip' => $L{'SETTINGS.LABEL_IPADDRESS'},
    );
  my $stationtyp = $cgi->radio_group(
        -name    => 'wustationtyp',
        -id      => 'wustationtyp',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('WUNDERGROUND.STATIONTYP'),
	-onClick => "disable()",
    );
  $template->param( WUSTATIONTYP => $stationtyp );

  # WU Language
  @values = ('AF', 'AL', 'AR', 'HY', 'AZ', 'EU', 'BY', 'BU', 'LI', 'MY', 'CA', 'CN', 'TW', 'CR', 'CZ', 'DK', 'DV', 'NL', 'EN', 'EO', 'ET', 'FA', 'FI', 'FR', 'FC', 'GZ', 'DL', 'KA', 'GR', 'GU', 'HT', 'IL', 'HI', 'HU', 'IS', 'IO', 'ID', 'IR', 'IT', 'JP', 'JW', 'KM', 'KR', 'KU', 'LA', 'LV', 'LT', 'ND', 'MK', 'MT', 'GM', 'MI', 'MR', 'MN', 'NO', 'OC', 'PS', 'GN', 'PL', 'BR', 'PA', 'RO', 'RU', 'SR', 'SK', 'SL', 'SP', 'SI', 'SW', 'CH', 'TL', 'TT', 'TH', 'TR', 'TK', 'UA', 'UZ', 'VU', 'CY', 'SN', 'JI', 'YI');
  %labels = (
	'AF' => 'Afrikaans',
	'AL' => 'Albanian',
	'AR' => 'Arabic',
	'HY' => 'Armenian',
	'AZ' => 'Azerbaijani',
	'EU' => 'Basque',
	'BY' => 'Belarusian',
	'BU' => 'Bulgarian',
	'LI' => 'British English',
	'MY' => 'Burmese',
	'CA' => 'Catalan',
	'CN' => 'Chinese - Simplified',
	'TW' => 'Chinese - Traditional',
	'CR' => 'Croatian',
	'CZ' => 'Czech',
	'DK' => 'Danish',
	'DV' => 'Dhivehi',
	'NL' => 'Dutch',
	'EN' => 'English',
	'EO' => 'Esperanto',
	'ET' => 'Estonian',
	'FA' => 'Farsi',
	'FI' => 'Finnish',
	'FR' => 'French',
	'FC' => 'French Canadian',
	'GZ' => 'Galician',
	'DL' => 'German',
	'KA' => 'Georgian',
	'GR' => 'Greek',
	'GU' => 'Gujarati',
	'HT' => 'Haitian Creole',
	'IL' => 'Hebrew',
	'HI' => 'Hindi',
	'HU' => 'Hungarian',
	'IS' => 'Icelandic',
	'IO' => 'Ido',
	'ID' => 'Indonesian',
	'IR' => 'Irish Gaelic',
	'IT' => 'Italian',
	'JP' => 'Japanese',
	'JW' => 'Javanese',
	'KM' => 'Khmer',
	'KR' => 'Korean',
	'KU' => 'Kurdish',
	'LA' => 'Latin',
	'LV' => 'Latvian',
	'LT' => 'Lithuanian',
	'ND' => 'Low German',
	'MK' => 'Macedonian',
	'MT' => 'Maltese',
	'GM' => 'Mandinka',
	'MI' => 'Maori',
	'MR' => 'Marathi',
	'MN' => 'Mongolian',
	'NO' => 'Norwegian',
	'OC' => 'Occitan',
	'PS' => 'Pashto',
	'GN' => 'Plautdietsch',
	'PL' => 'Polish',
	'BR' => 'Portuguese',
	'PA' => 'Punjabi',
	'RO' => 'Romanian',
	'RU' => 'Russian',
	'SR' => 'Serbian',
	'SK' => 'Slovak',
	'SL' => 'Slovenian',
	'SP' => 'Spanish',
	'SI' => 'Swahili',
	'SW' => 'Swedish',
	'CH' => 'Swiss',
	'TL' => 'Tagalog',
	'TT' => 'Tatarish',
	'TH' => 'Thai',
	'TR' => 'Turkish',
	'TK' => 'Turkmen',
	'UA' => 'Ukrainian',
	'UZ' => 'Uzbek',
	'VU' => 'Vietnamese',
	'CY' => 'Welsh',
	'SN' => 'Wolof',
	'JI' => 'Yiddish - transliterated',
	'YI' => 'Yiddish - unicode',
    );
  my $wulang = $cgi->popup_menu(
        -name    => 'wulang',
        -id      => 'wulang',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('WUNDERGROUND.LANG'),
    );
  $template->param( WULANG => $wulang );


# Menu: Miniserver
} elsif ($R::form eq "2") {
  $navbar{2}{active} = 1;
  $template->param( "FORM2", 1);
  $template->param( "WEBSITE", "http://$ENV{HTTP_HOST}/plugins/$lbpplugindir/weatherdata.html");

  # Miniserver
  my $mshtml = mslist_select_html( FORMID => 'msno', SELECTED => $cfg->param('SERVER.MSNO'), DATA_MINI => 1 );
  $template->param( MINISERVER => $mshtml );

  # SendUDP
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $sendudp = $cgi->popup_menu(
        -name    => 'sendudp',
        -id      => 'sendudp',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.SENDUDP'),
    );
  $template->param( SENDUDP => $sendudp );

  # DFC
  my $dfc;
  my $n;
  my $checked;
  my @fields = split(/;/,$cfg->param('SERVER.SENDDFC'));
  for (my $i=1;$i<=8;$i++) {
    $checked = 0;
    foreach ( split( /;/,$cfg->param('SERVER.SENDDFC') ) ) {
      if ($_ eq $i) {
        $checked = 1;
      }
    }
    $n = $i-1;
    $dfc .= $cgi->checkbox(
        -name    => "dfc$i",
        -id      => "dfc$i",
	-checked => $checked,
        -value   => '1',
	-label   => "+$n $L{'SETTINGS.LABEL_DAYS'}",
      );
  }
  $template->param( DFC => $dfc );

  # HFC
  my $hfc;
  @fields = split(/;/,$cfg->param('SERVER.SENDHFC'));
  for ($i=1;$i<=48;$i++) {
    $checked = 0;
    foreach ( split( /;/,$cfg->param('SERVER.SENDHFC') ) ) {
      if ($_ eq $i) {
        $checked = 1;
      }
    }
    $hfc .= $cgi->checkbox(
        -name    => "hfc$i",
        -id      => "hfc$i",
	-checked => $checked,
        -value   => '1',
	-label   => "+$i $L{'SETTINGS.LABEL_HOURS'}",
      );
  }
  $template->param( HFC => $hfc );

# Menu: Cloudweather / Website
} elsif ($R::form eq "3") {
  $navbar{3}{active} = 1;
  $template->param( "FORM3", 1);
  $template->param( "WEBSITE", "http://$ENV{HTTP_HOST}/plugins/$lbpplugindir/webpage.html");

  # Check for installed DNSMASQ-Plugin
  my $checkdnsmasq = LoxBerry::System::plugindata('DNSmasq');
  if ( $checkdnsmasq->{PLUGINDB_TITLE} ) {
    $template->param( EMUWARNING => $L{'SETTINGS.ERR_DNSMASQ_PLUGIN'} );
  }

  # Cloudweather Emu
  @values = ('0', '1' );
  %labels = (
        '0' => $L{'SETTINGS.LABEL_OFF'},
        '1' => $L{'SETTINGS.LABEL_ON'},
    );
  my $emu = $cgi->popup_menu(
        -name    => 'emu',
        -id      => 'emu',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.EMU'),
    );
  $template->param( EMU => $emu );
  $template->param( MYIP => LoxBerry::System::get_localip() );

  # Theme
  @values = ('dark', 'light', 'custom' );
  %labels = (
        'dark' => "Dark Theme",
        'light' => "Light Theme",
        'custom' => "Custom Theme",
    );
  my $theme = $cgi->popup_menu(
        -name    => 'theme',
        -id      => 'theme',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('WEB.THEME'),
    );
  $template->param( THEME => $theme );

  # Icon Set
  @values = ('color', 'flat', 'dark', 'light', 'green', 'silver', 'realistic', 'custom' );
  %labels = (
        'color' => "Color Set",
        'flat' => "Flat Set",
        'dark' => "Dark Set",
        'light' => "Light Set",
        'green' => "Green Set",
        'silver' => "Silver Set",
        'realistic' => "Realistic Set",
        'custom' => "Custom Set",
    );
  my $iconset = $cgi->popup_menu(
        -name    => 'iconset',
        -id      => 'iconset',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('WEB.ICONSET'),
    );
  $template->param( ICONSET => $iconset );

  # Theme LANG
  @values = ('at', 'nl', 'en', 'de', 'es' );
  %labels = (
        'at' => "Austrian",
        'nl' => "Dutch",
        'en' => "English",
        'de' => "German",
        'es' => "Spanish",
    );
  my $themelang = $cgi->popup_menu(
        -name    => 'themelang',
        -id      => 'themelang',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('WEB.LANG'),
    );
  $template->param( THEMELANG => $themelang );

# Menu: Logfiles
} elsif ($R::form eq "99") {
  $navbar{99}{active} = 1;
  $template->param( "FORM99", 1 );
  $template->param( "LOGLIST_HTML", LoxBerry::Web::loglist_html() );

}

# Template Vars and Form parts
$template->param( "LBPPLUGINDIR", $lbpplugindir);

# Template
LoxBerry::Web::lbheader($L{'SETTINGS.LABEL_PLUGINTITLE'} . " V$version", "http://www.loxwiki.eu/display/LOXBERRY/Weather4Loxone", "help.html");
print $template->output();
LoxBerry::Web::lbfooter();

exit;

#####################################################
# Query Wunderground
#####################################################

sub wuquery
{

	# Get the public API key from the WU website
	my $query = "https://www.wunderground.com/dashboard/pws/$querystation";
	print STDERR "QUERY1: $query\n";

	my $ua = new LWP::UserAgent;
	my $res = $ua->get($query);

	# Check status of request
	my $urlstatus = $res->status_line;
	my $urlstatuscode = substr($urlstatus,0,3);

	my $apikey;
	if ($urlstatuscode ne "200") {
	        $error = $L{'SETTINGS.ERR_NO_DATA'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	} else {
		$apikey = $res->decoded_content;
		$apikey =~ s/\n//g;
		$apikey =~ s/.*apiKey=([0-9a-z]*)\&.*/$1/g;
	}

	print STDERR "API: $apikey\n";

        # Get data from Wunderground Server (API request) for testing API Key and Station
	if (!$error) {
	        $query = "$url?apiKey=$apikey&stationId=$querystation&format=json&units=m";
		print STDERR "QUERY2: $query\n";
		$ua = new LWP::UserAgent;
		$res = $ua->get($query);
		my $json = $res->decoded_content();

		# Check status of request
		my $urlstatus = $res->status_line;
		my $urlstatuscode = substr($urlstatus,0,3);

		if ($urlstatuscode ne "200") {
		        $error = $L{'SETTINGS.ERR_NO_DATA'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
		}

		# Decode JSON response from server
		if (!$error) {
			our $decoded_json = decode_json( $json );
		}
	}
	return();

}

#####################################################
# Query Openweather
#####################################################

sub openweatherquery
{

        # Get data from Weatherbit Server (API request) for testing API Key
        my $query = "$url\/3.0/onecall?appid=$R::openweatherapikey&$querystation";
        my $ua = new LWP::UserAgent;
        my $res = $ua->get($query);
        my $json = $res->decoded_content();

        # Check status of request
        my $urlstatus = $res->status_line;
        my $urlstatuscode = substr($urlstatus,0,3);

	if ($urlstatuscode ne "200" && $urlstatuscode ne "401" ) {
	        $error = $L{'SETTINGS.ERR_NO_DATA'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

	if ($urlstatuscode eq "401" ) {
	        $error = $L{'SETTINGS.ERR_API_KEY'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

        # Decode JSON response from server
	if (!$error) {
        	our $decoded_json = decode_json( $json );
	}
	return();

}

#####################################################
# Query Weatherflow
#####################################################

sub weatherflowquery
{

    # Update API key to comply with Weatherflow format
    #my $apikey = $R::weatherflowapikey;
    #$apikey =~ s/^(.{8})(.{4})(.{4})(.{4})(.{12})/$1\-$2\-$3\-$4\-$5/;

    # Get data from Weatherflow Server (API request) for testing API Key
    my $query = "$url\/observations\/station\/$R::weatherflowstationid?token=$R::weatherflowapikey";
    my $ua = new LWP::UserAgent;
    my $res = $ua->get($query);
    my $json = $res->decoded_content();

    # Check status of request
    my $urlstatus = $res->status_line;
    my $urlstatuscode = substr($urlstatus,0,3);

	if ($urlstatuscode ne "200" && $urlstatuscode ne "401" ) {
	        $error = $L{'SETTINGS.ERR_NO_DATA'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

	if ($urlstatuscode eq "401" ) {
	        $error = $L{'SETTINGS.ERR_API_KEY'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

        # Decode JSON response from server
	if (!$error) {
        	our $decoded_json = decode_json( $json );
	}
	return();

}

#####################################################
# Query Visualcrossing
#####################################################

sub visualcrossingquery
{

        # Get data from VisualCrossing Server (API request) for testing API Key
	my $query = "$url/$querystation?unitGroup=metric&include=current&key=$R::visualcrossingapikey&contentType=json";
        my $ua = new LWP::UserAgent;
        my $res = $ua->get($query);
        my $json = $res->decoded_content();

        # Check status of request
        my $urlstatus = $res->status_line;
        my $urlstatuscode = substr($urlstatus,0,3);

	if ($urlstatuscode ne "200" && $urlstatuscode ne "401" ) {
	        $error = $L{'SETTINGS.ERR_NO_DATA'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

	if ($urlstatuscode eq "401" ) {
	        $error = $L{'SETTINGS.ERR_API_KEY'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

        # Decode JSON response from server
	if (!$error) {
        	our $decoded_json = decode_json( $json );
	}
	return();

}


#####################################################
# Error
#####################################################

sub error
{
	$template->param( "ERROR", 1);
	$template->param( "ERRORMESSAGE", $error);
	LoxBerry::Web::lbheader($L{'SETTINGS.LABEL_PLUGINTITLE'} . " V$version", "http://www.loxwiki.eu/display/LOXBERRY/Weather4Loxone", "help.html");
	print $template->output();
	LoxBerry::Web::lbfooter();

	exit;
}

#####################################################
# Save
#####################################################

sub save
{
	$template->param( "SAVE", 1);
	LoxBerry::Web::lbheader($L{'SETTINGS.LABEL_PLUGINTITLE'} . " V$version", "https://wiki.loxberry.de/plugins/weather4loxone/start", "help.html");
	print $template->output();
	LoxBerry::Web::lbfooter();

	exit;
}

