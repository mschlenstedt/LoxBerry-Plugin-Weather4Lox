#!/usr/bin/perl

# Copyright 2016 Michael Schlenstedt, michael@loxberry.de
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

$cfg->param("WEATHERBIT.URL", "http://api.weatherbit.io/v2.0");
$cfg->param("DARKSKY.URL", "https://api.darksky.net");
$cfg->param("WUNDERGROUND.URL", "http://stationdata.wunderground.com/cgi-bin/stationdata");

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
	$R::darkskycoordlat =~ tr/,/./;
	$R::darkskycoordlong =~ tr/,/./;

	# Check for Station : WUNDERGROUND
	if ($R::weatherservice eq "wu") {
		our $url = $cfg->param("WUNDERGROUND.URL");
		our $querystation;
		our $wuquerystation;
		$wuquerystation = $querystation;
		if ($R::wustationtyp eq "statid") {
			$querystation = $R::wustationid;
		} 
		elsif ($R::wustationtyp eq "coord") {
			$querystation = $R::wucoordlat . "," . $R::wucoordlong;
		}
		else {
			$querystation = "autoip";
		}
		# 1. attempt to query Wunderground
		&wuquery;
		$found = 0;
		if ( $decoded_json->{current_observation}->{station_id} ) {
			$found = 1;
			$wuquerystation = $querystation;
		}
		if ( !$found && $decoded_json->{response}->{error}->{type} eq "keynotfound" ) {
			$error = $L{'SETTINGS.ERR_API_KEY'} . "<br><br><b>WU Error Message:</b> $decoded_json->{response}->{error}->{description}";
		}
		# 2. attempt to query Wunderground
		# Before giving up test if it is a PWS
		if (!$found) {
			$querystation = "pws:$querystation";
			&wuquery;
			if ( $decoded_json->{current_observation}->{station_id} ) {
				$found = 1;
				$wuquerystation = $querystation;
			}
		}
		# 3. attempt to query Wunderground
		# Before giving up test if it is a ZMW
		if (!$found) {
			$querystation = "zmw:$querystation";
			&wuquery;
			if ( $decoded_json->{current_observation}->{station_id} ) {
				$found = 1;
				$wuquerystation = $querystation;
			}
		}
		# That was my last attempt - if we haven't found the station, we are giving up.
		if (!$found) {
			$error = $L{'SETTINGS.ERR_NO_WEATHERSTATION'};
		}
	}
	
	# Check for Station : DARKSKY
	if ($R::weatherservice eq "darksky") {
		our $url = $cfg->param("DARKSKY.URL");
		our $querystation = $R::darkskycoordlat . "," . $R::darkskycoordlong;
		# 1. attempt to query Darksky
		&darkskyquery;
		$found = 0;
		if ( !$error && $decoded_json->{latitude} ) {
			$found = 1;
		}
		if ( !$error && !$found ) {
			$error = $L{'SETTINGS.ERR_NO_WEATHERSTATION'};
		}
	}
	
	# Check for Station : WEATHERBIT
	if ($R::weatherservice eq "weatherbit") {
		our $url = $cfg->param("WEATHERBIT.URL");
		our $querystation = "lat=" . $R::weatherbitcoordlat . "&lon=" . $R::weatherbitcoordlong;
		# 1. attempt to query Weatherbit
		&weatherbitquery;
		$found = 0;
		if ( !$error && $decoded_json->{count} ) {
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
#	$cfg->param("WUNDERGROUND.STATIONID", "$wuquerystation");
	$cfg->param("WUNDERGROUND.STATIONID", "$R::wustationid");
	$cfg->param("WUNDERGROUND.COORDLAT", "$R::wucoordlat");
	$cfg->param("WUNDERGROUND.COORDLONG", "$R::wucoordlong");
	$cfg->param("WUNDERGROUND.LANG", "$R::wulang");

	$cfg->param("DARKSKY.APIKEY", "$R::darkskyapikey");
	$cfg->param("DARKSKY.COORDLAT", "$R::darkskycoordlat");
	$cfg->param("DARKSKY.COORDLONG", "$R::darkskycoordlong");
	$cfg->param("DARKSKY.LANG", "$R::darkskylang");
	$cfg->param("DARKSKY.STATION", "$R::darkskycity");
	$cfg->param("DARKSKY.COUNTRY", "$R::darkskycountry");

	$cfg->param("WEATHERBIT.APIKEY", "$R::weatherbitapikey");
	$cfg->param("WEATHERBIT.APIKEY", "$R::weatherbitapikey");
	$cfg->param("WEATHERBIT.COORDLAT", "$R::weatherbitcoordlat");
	$cfg->param("WEATHERBIT.COORDLONG", "$R::weatherbitcoordlong");
	$cfg->param("WEATHERBIT.LANG", "$R::weatherbitlang");
	$cfg->param("WEATHERBIT.COUNTRY", "$R::weatherbitcountry");

	$cfg->param("SERVER.WUGRABBER", "$R::wugrabber");
	$cfg->param("SERVER.LOXGRABBER", "$R::loxgrabber");
	$cfg->param("SERVER.GETDATA", "$R::getdata");
	$cfg->param("SERVER.CRON", "$R::cron");
	$cfg->param("SERVER.METRIC", "$R::metric");
	$cfg->param("SERVER.WEATHERSERVICE", "$R::weatherservice");

	$cfg->save();
		
	# Create Cronjob
	if ($R::getdata eq "1") 
	{
	  if ($R::cron eq "1") 
	  {
	    system ("ln -s $lbpbindir/fetch.pl $lbhomedir/system/cron/cron.01min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.03min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.05min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.10min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.15min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.30min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.hourly/$lbpplugindir");
	  }
	  if ($R::cron eq "3") 
	  {
	    system ("ln -s $lbpbindir/fetch.pl $lbhomedir/system/cron/cron.03min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.05min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.10min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.15min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.30min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.hourly/$lbpplugindir");
	  }
	  if ($R::cron eq "5") 
	  {
	    system ("ln -s $lbpbindir/fetch.pl $lbhomedir/system/cron/cron.05min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.03min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.10min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.15min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.30min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.hourly/$lbpplugindir");
	  }
	  if ($R::cron eq "10") 
	  {
	    system ("ln -s $lbpbindir/fetch.pl $lbhomedir/system/cron/cron.10min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.1min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.3min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.5min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.15min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.30min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.hourly/$lbpplugindir");
	  }
	  if ($R::cron eq "15") 
	  {
	    system ("ln -s $lbpbindir/fetch.pl $lbhomedir/system/cron/cron.15min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.03min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.05min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.10min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.30min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.hourly/$lbpplugindir");
	  }
	  if ($R::cron eq "30") 
	  {
	    system ("ln -s $lbpbindir/fetch.pl $lbhomedir/system/cron/cron.30min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.03min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.05min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.10min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.15min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.hourly/$lbpplugindir");
	  }
	  if ($R::cron eq "60") 
	  {
	    system ("ln -s $lbpbindir/fetch.pl $lbhomedir/system/cron/cron.hourly/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.03min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.05min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.10min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.15min/$lbpplugindir");
	    unlink ("$lbhomedir/system/cron/cron.30min/$lbpplugindir");
	  }
	} 
	else
	{
	  unlink ("$lbhomedir/system/cron/cron.01min/$lbpplugindir");
	  unlink ("$lbhomedir/system/cron/cron.03min/$lbpplugindir");
	  unlink ("$lbhomedir/system/cron/cron.05min/$lbpplugindir");
	  unlink ("$lbhomedir/system/cron/cron.10min/$lbpplugindir");
	  unlink ("$lbhomedir/system/cron/cron.15min/$lbpplugindir");
	  unlink ("$lbhomedir/system/cron/cron.30min/$lbpplugindir");
	  unlink ("$lbhomedir/system/cron/cron.hourly/$lbpplugindir");
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
# $navbar{99}{URL} = LoxBerry::Web::loglist_url();
$navbar{99}{URL} = 'index.cgi?form=99';
# $navbar{99}{target} = '_blank';

# Menu: Server
if ($R::form eq "1" || !$R::form) {

  $navbar{1}{active} = 1;
  $template->param( "FORM1", 1);

  my @values;
  my %labels;

  # Weather Service
  @values = ('darksky', 'weatherbit' );
  %labels = (
        'darksky' => 'Dark Sky',
        'weatherbit' => 'Weatherbit',
	#'wu' => 'Wunderground',
    );
  my $wservice = $cgi->popup_menu(
        -name    => 'weatherservice',
        -id      => 'weatherservice',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('SERVER.WEATHERSERVICE'),
    );
  $template->param( WEATHERSERVICE => $wservice );

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

  # DarkSky Language
  @values = ('ar', 'az', 'be', 'bg', 'bs', 'ca', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fi', 'fr', 'hr', 'hu', 'id', 'is', 'it', 'ja', 'ka', 'ko', 'kw', 'nb', 'nl', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'sr', 'sv', 'tet', 'tr', 'uk', 'x-pig-latin', 'zh', 'zh-tw');

  %labels = (
	'ar' => 'Arabic',
	'az' => 'Azerbaijani',
	'be' => 'Belarusian',
	'bg' => 'Bulgarian',
	'bs' => 'Bosnian',
	'ca' => 'Catalan',
	'cs' => 'Czech',
	'da' => 'Danish',
	'de' => 'German',
	'el' => 'Greek',
	'en' => 'English',
	'es' => 'Spanish',
	'et' => 'Estonian',
	'fi' => 'Finnish',
	'fr' => 'French',
	'hr' => 'Croatian',
	'hu' => 'Hungarian',
	'id' => 'Indonesian',
	'is' => 'Icelandic',
	'it' => 'Italian',
	'ja' => 'Japanese',
	'ka' => 'Georgian',
	'ko' => 'Korean',
	'kw' => 'Cornish',
	'nb' => 'Norwegian Bokmål',
	'nl' => 'Dutch',
	'pl' => 'Polish',
	'pt' => 'Portuguese',
	'ro' => 'Romanian',
	'ru' => 'Russian',
	'sk' => 'Slovak',
	'sl' => 'Slovenian',
	'sr' => 'Serbian',
	'sv' => 'Swedish',
	'tet' => 'Tetum',
	'tr' => 'Turkish',
	'uk' => 'Ukrainian',
	'x-pig-latin' => 'Igpay Atinlay',
	'zh' => 'simplified Chinese',
	'zh-tw' => 'traditional Chinese',
    );
  my $darkskylang = $cgi->popup_menu(
        -name    => 'darkskylang',
        -id      => 'darkskylang',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('DARKSKY.LANG'),
    );
  $template->param( DARKSKYLANG => $darkskylang );

  # Weatherbit Language
  @values = ('ar', 'az', 'be', 'bg', 'bs', 'ca', 'cz', 'da', 'de', 'el', 'en', 'es', 'et', 'fi', 'fr', 'hr', 'hu', 'id', 'is', 'it', 'kw', 'lt', 'nb', 'nl', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'sr', 'sv', 'tr', 'uk', 'zh', 'zh-tw');

  %labels = (
	'ar' => 'Arabic',
	'az' => 'Azerbaijani',
	'be' => 'Belarusian',
	'bg' => 'Bulgarian',
	'bs' => 'Bosnian',
	'ca' => 'Catalan',
	'cz' => 'Czech',
	'da' => 'Danish',
	'de' => 'German',
	'el' => 'Greek',
	'en' => 'English',
	'es' => 'Spanish',
	'et' => 'Estonian',
	'fi' => 'Finnish',
	'fr' => 'French',
	'hr' => 'Croatian',
	'hu' => 'Hungarian',
	'id' => 'Indonesian',
	'is' => 'Icelandic',
	'it' => 'Italian',
#	'ja' => 'Japanese',
#	'ka' => 'Georgian',
#	'ko' => 'Korean',
	'kw' => 'Cornish',
	'lt' => 'Lithuanian',
	'nb' => 'Norwegian Bokmål',
	'nl' => 'Dutch',
	'pl' => 'Polish',
	'pt' => 'Portuguese',
	'ro' => 'Romanian',
	'ru' => 'Russian',
	'sk' => 'Slovak',
	'sl' => 'Slovenian',
	'sr' => 'Serbian',
	'sv' => 'Swedish',
#	'tet' => 'Tetum',
	'tr' => 'Turkish',
	'uk' => 'Ukrainian',
#	'x-pig-latin' => 'Igpay Atinlay',
	'zh' => 'simplified Chinese',
	'zh-tw' => 'traditional Chinese',
    );
  my $weatherbitlang = $cgi->popup_menu(
        -name    => 'weatherbitlang',
        -id      => 'weatherbitlang',
        -values  => \@values,
	-labels  => \%labels,
	-default => $cfg->param('WEATHERBIT.LANG'),
    );
  $template->param( WEATHERBITLANG => $weatherbitlang );
  
  
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
  my $checkdnsmasq = `cat $lbhomedir/data/system/plugindatabase.dat | grep -c -i DNSmasq`;
  if ($checkdnsmasq > 0) {
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

        # Get data from Wunderground Server (API request) for testing API Key and Station
        my $query = "$url\/$R::wuapikey\/conditions\/pws:1\/lang:EN\/q\/$querystation\.json";

        my $ua = new LWP::UserAgent;
        my $res = $ua->get($query);
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
	return();

}

#####################################################
# Query Dark Sky
#####################################################

sub darkskyquery
{

        # Get data from DarkSky Server (API request) for testing API Key
        my $query = "$url\/forecast\/$R::darkskyapikey\/$querystation";
        my $ua = new LWP::UserAgent;
        my $res = $ua->get($query);
        my $json = $res->decoded_content();

        # Check status of request
        my $urlstatus = $res->status_line;
        my $urlstatuscode = substr($urlstatus,0,3);

	if ($urlstatuscode ne "200" && $urlstatuscode ne "403" ) {
	        $error = $L{'SETTINGS.ERR_NO_DATA'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

	if ($urlstatuscode eq "403" ) {
	        $error = $L{'SETTINGS.ERR_API_KEY'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

        # Decode JSON response from server
	if (!$error) {
	        our $decoded_json = decode_json( $json );
	}
	return();

}

#####################################################
# Query Weatherbit
#####################################################

sub weatherbitquery
{

        # Get data from Weatherbit Server (API request) for testing API Key
        my $query = "$url\/current?key=$R::weatherbitapikey&$querystation";
        my $ua = new LWP::UserAgent;
        my $res = $ua->get($query);
        my $json = $res->decoded_content();

        # Check status of request
        my $urlstatus = $res->status_line;
        my $urlstatuscode = substr($urlstatus,0,3);

	if ($urlstatuscode ne "200" && $urlstatuscode ne "403" ) {
	        $error = $L{'SETTINGS.ERR_NO_DATA'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

	if ($urlstatuscode eq "403" ) {
	        $error = $L{'SETTINGS.ERR_API_KEY'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode";
	}

	if ( $decoded_json->{error} ) {
	        $error = $L{'SETTINGS.ERR_NO_DATA'} . "<br><br><b>URL:</b> $query<br><b>STATUS CODE:</b> $urlstatuscode" . "<br><b>ERROR:</b> $decoded_json->{error}";
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
	LoxBerry::Web::lbheader($L{'SETTINGS.LABEL_PLUGINTITLE'} . " V$version", "http://www.loxwiki.eu/display/LOXBERRY/Weather4Loxone", "help.html");
	print $template->output();
	LoxBerry::Web::lbfooter();

	exit;
}

