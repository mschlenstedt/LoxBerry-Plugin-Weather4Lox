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

#use strict;
#use warnings;

##########################################################################
# Modules
##########################################################################

use LoxBerry::System;
use LoxBerry::IO;
use DateTime;
use Net::MQTT::Simple;
use Data::Dumper;

my $i;
our $value;
our $name;
our $per;
our $data;
our $mqtt;

# Date Reference: Convert into Loxone Epoche (1.1.2009)
my $dateref = DateTime->new(
      year      => 2009,
      month     => 1,
      day       => 1,
);

# Connect to broker
my $pcfg             = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
our $topic            = $pcfg->param("SERVER.TOPIC");
&mqttconnect();

#
# Print out Current Data
#

# Read data
open(F,"<$lbplogdir/current.dat");
  our $curdata = <F>;
close(F);

chomp $curdata;

my @fields = split(/\|/,$curdata);

# Correct Epoch by Timezone
my $tzseconds = (@fields[4] / 100 * 3600);

# EpochDate - Corrected by TZ
our $epochdate = DateTime->from_epoch(
      epoch      => @fields[0],
);
$epochdate->add( seconds => $tzseconds );

$name = "date_lox";
$value = $epochdate->epoch() - $dateref->epoch();
&add_cur;

$name = "date_epoche";
$value = $epochdate->epoch();
&add_cur;

$name = "date_des";
$value = @fields[1];
&add_cur;

$name = "date_tz_des_sh";
$value = @fields[2];
&add_cur;

$name = "date_tz_des";
$value = @fields[3];
&add_cur;

$name = "date_tz";
$value = @fields[4];
&add_cur;

$name = "day";
$value = $epochdate->day;
&add_cur;

$name = "month";
$value = $epochdate->month;
&add_cur;

$name = "year";
$value = $epochdate->year;
&add_cur;

$name = "hour";
$value = $epochdate->hour;
&add_cur;

$name = "min";
$value = $epochdate->minute;
&add_cur;

$name = "loc_n";
$value = @fields[5];
&add_cur;

$name = "loc_c";
$value = @fields[6];
&add_cur;

$name = "loc_ccode";
$value = @fields[7];
&add_cur;

$name = "loc_lat";
$value = @fields[8];
&add_cur;

$name = "loc_long";
$value = @fields[9];
&add_cur;

$name = "loc_el";
$value = @fields[10];
&add_cur;

$name = "tt";
$value = @fields[11];
&add_cur;

$name = "tt_fl";
$value = @fields[12];
&add_cur;

$name = "hu";
$value = @fields[13];
&add_cur;

$name = "w_dirdes";
$value = @fields[14];
&add_cur;

$name = "w_dir";
$value = @fields[15];
&add_cur;

$name = "w_sp";
$value = @fields[16];
&add_cur;

$name = "w_gu";
$value = @fields[17];
&add_cur;

$name = "w_ch";
$value = @fields[18];
&add_cur;

$name = "pr";
$value = @fields[19];
&add_cur;

$name = "dp";
$value = @fields[20];
&add_cur;

$name = "vis";
$value = @fields[21];
&add_cur;

$name = "sr";
$value = @fields[22];
&add_cur;

$name = "hi";
$value = @fields[23];
&add_cur;

$name = "uvi";
$value = @fields[24];
&add_cur;

$name = "prec_today";
$value = @fields[25];
&add_cur;

$name = "prec_1hr";
$value = @fields[26];
&add_cur;

$name = "we_icon";
$value = @fields[27];
&add_cur;

$name = "we_code";
$value = @fields[28];
&add_cur;

$name = "we_des";
$value = @fields[29];
&add_cur;

$name = "moon_p";
$value = @fields[30];
&add_cur;

$name = "moon_a";
$value = @fields[31];
&add_cur;

$name = "moon_ph";
$value = @fields[32];
&add_cur;

$name = "moon_h";
$value = @fields[33];
&add_cur;

# Create Sunset/rise Date in Loxone Epoch Format (1.1.2009)
# Sunrise
my $sunrdate;
$sunrdate = DateTime->new(
      year      => $epochdate -> year(),
      month     => $epochdate -> month(),
      day       => $epochdate -> day(),
      hour      => @fields[34],
      minute    => @fields[35],
);
#$sunrdate->add( seconds => $tzseconds );
$name = "sun_r_lox";
$value = $sunrdate->epoch() - $dateref->epoch();
&add_cur;

# Sunset
my $sunsdate;
$sunsdate = DateTime->new(
      year      => $epochdate -> year(),
      month     => $epochdate -> month(),
      day       => $epochdate -> day(),
      hour      => @fields[36],
      minute    => @fields[37],
);
#$sunsdate->add( seconds => $tzseconds );
$name = "sun_s_lox";
$value = $sunsdate->epoch() - $dateref->epoch();
&add_cur;

$name = "ozone";
$value = @fields[38];
&add_cur;

$name = "sky";
$value = @fields[39];
&add_cur;

$name = "pop";
$value = @fields[40];
&add_cur;

$name = "snow";
$value = @fields[41];
&add_cur;

#
# Print out Daily Forecast
#

# Read data
open(F,"<$lbplogdir/dailyforecast.dat");
  our @dfcdata = <F>;
close(F);

foreach (@dfcdata){
  s/[\n\r]//g;
  @fields = split(/\|/);

  $per = @fields[0];

  # DFC: Today is dfc0
  $per = $per-1;

  # Calculate Epoche Date
  my $epochdatedfc = DateTime->from_epoch(
      epoch      => @fields[1],
  );
  $epochdatedfc->add( seconds => $tzseconds );

  $name = "date_lox";
  $value = $epochdatedfc->epoch() - $dateref->epoch();
  &add_dfc;

  $name = "date_epoche";
  $value = $epochdatedfc->epoch();
  &add_dfc;

  $name = "day";
  $value = @fields[2];
  &add_dfc;

  $name = "month";
  $value = @fields[3];
  &add_dfc;

  $name = "monthn";
  $value = @fields[4];
  &add_dfc;

  $name = "monthn_sh";
  $value = @fields[5];
  &add_dfc;

  $name = "year";
  $value = @fields[6];
  &add_dfc;

  $name = "hour";
  $value = @fields[7];
  &add_dfc;

  $name = "min";
  $value = @fields[8];
  &add_dfc;

  $name = "wday";
  $value = @fields[9];
  &add_dfc;

  $name = "wday_sh";
  $value = @fields[10];
  &add_dfc;

  $name = "tt_h";
  $value = @fields[11];
  &add_dfc;

  $name = "tt_l";
  $value = @fields[12];
  &add_dfc;

  $name = "pop";
  $value = @fields[13];
  &add_dfc;

  $name = "prec";
  $value = @fields[14];
  &add_dfc;

  $name = "snow";
  $value = @fields[15];
  &add_dfc;

  $name = "w_sp_h";
  $value = @fields[16];
  &add_dfc;

  $name = "w_dirdes_h";
  $value = @fields[17];
  &add_dfc;

  $name = "w_dir_h";
  $value = @fields[18];
  &add_dfc;

  $name = "w_sp_a";
  $value = @fields[19];
  &add_dfc;

  $name = "w_dirdes_a";
  $value = @fields[20];
  &add_dfc;

  $name = "w_dir_a";
  $value = @fields[21];
  &add_dfc;

  $name = "hu_a";
  $value = @fields[22];
  &add_dfc;

  $name = "hu_h";
  $value = @fields[23];
  &add_dfc;

  $name = "hu_l";
  $value = @fields[24];
  &add_dfc;

  $name = "we_icon";
  $value = @fields[25];
  &add_dfc;

  $name = "we_code";
  $value = @fields[26];
  &add_dfc;

  $name = "we_des";
  $value = @fields[27];
  &add_dfc;

  $name = "ozone";
  $value = @fields[28];
  &add_dfc;

  $name = "moon_p";
  $value = @fields[29];
  &add_dfc;

  $name = "dp";
  $value = @fields[30];
  &add_dfc;

  $name = "pr";
  $value = @fields[31];
  &add_dfc;

  $name = "uvi";
  $value = @fields[32];
  &add_dfc;

  # Create Sunset/rise Date in Loxone Epoch Format (1.1.2009)
  # Sunrise
  my $sunrdate;
  $sunrdate = DateTime->new(
      year      => $epochdate -> year(),
      month     => $epochdate -> month(),
      day       => $epochdate -> day(),
      hour      => @fields[33],
      minute    => @fields[34],
  );
  #$sunrdate->add( seconds => $tzseconds );
  $name = "sun_r_lox";
  $value = $sunrdate->epoch() - $dateref->epoch();
  &add_dfc;

  # Sunset
  my $sunsdate;
  $sunsdate = DateTime->new(
      year      => $epochdate -> year(),
      month     => $epochdate -> month(),
      day       => $epochdate -> day(),
      hour      => @fields[35],
      minute    => @fields[36],
  );
  #$sunsdate->add( seconds => $tzseconds );
  $name = "sun_s_lox";
  $value = $sunsdate->epoch() - $dateref->epoch();
  &add_dfc;

  $name = "vis";
  $value = @fields[37];
  &add_dfc;

  $name = "moon_a";
  $value = @fields[38];
  &add_dfc;

  $name = "moon_ph";
  $value = @fields[39];
  &add_dfc;
}

#
# Print out Hourly Forecast
#

# Read data
open(F,"<$lbplogdir/hourlyforecast.dat");
  our @hfcdata = <F>;
close(F);

foreach (@hfcdata){
  s/[\n\r]//g;
  @fields = split(/\|/);

  $per = @fields[0];

  # HFC: Current hour is hfc0
  $per = $per-1;

  $name = "date_lox";
  $value = @fields[1] - $dateref->epoch();
  &add_hfc;

  $name = "date_epoche";
  $value = @fields[1];
  &add_hfc;

  $name = "day";
  $value = @fields[2];
  &add_hfc;

  $name = "month";
  $value = @fields[3];
  &add_hfc;

  $name = "monthn";
  $value = @fields[4];
  &add_hfc;

  $name = "monthn_sh";
  $value = @fields[5];
  &add_hfc;

  $name = "year";
  $value = @fields[6];
  &add_hfc;

  $name = "hour";
  $value = @fields[7];
  &add_hfc;

  $name = "min";
  $value = @fields[8];
  &add_hfc;

  $name = "wday";
  $value = @fields[9];
  &add_hfc;

  $name = "wday_sh";
  $value = @fields[10];
  &add_hfc;

  $name = "tt";
  $value = @fields[11];
  &add_hfc;

  $name = "tt_fl";
  $value = @fields[12];
  &add_hfc;

  $name = "hi";
  $value = @fields[13];
  &add_hfc;

  $name = "hu";
  $value = @fields[14];
  &add_hfc;

  $name = "w_dirdes";
  $value = @fields[15];
  &add_hfc;

  $name = "w_dir";
  $value = @fields[16];
  &add_hfc;

  $name = "w_sp";
  $value = @fields[17];
  &add_hfc;

  $name = "w_ch";
  $value = @fields[18];
  &add_hfc;

  $name = "pr";
  $value = @fields[19];
  &add_hfc;

  $name = "dp";
  $value = @fields[20];
  &add_hfc;

  $name = "sky";
  $value = @fields[21];
  &add_hfc;

  $name = "sky\_des";
  $value = @fields[22];
  &add_hfc;

  $name = "uvi";
  $value = @fields[23];
  &add_hfc;

  $name = "prec";
  $value = @fields[24];
  &add_hfc;

  $name = "snow";
  $value = @fields[25];
  &add_hfc;

  $name = "pop";
  $value = @fields[26];
  &add_hfc;

  $name = "we_code";
  $value = @fields[27];
  &add_hfc;

  $name = "we_icon";
  $value = @fields[28];
  &add_hfc;


  $name = "we_des";
  $value = @fields[29];
  &add_hfc;

  $name = "ozone";
  $value = @fields[30];
  &add_hfc;

  $name = "sr";
  $value = @fields[31];
  &add_hfc;

  $name = "vis";
  $value = @fields[32];
  &add_hfc;

  $name = "moon_p";
  $value = @fields[33];
  &add_hfc;

  $name = "moon_a";
  $value = @fields[34];
  &add_hfc;

  $name = "moon_ph";
  $value = @fields[35];
  &add_hfc;
}

print "\nEnde\n";
exit (0);

#
# Subroutines
#

sub add_cur {

	$mqtt->retain($topic . "/current/" . $name, $value);
	return;

}

sub add_dfc {

	$mqtt->retain($topic . "/daily/" . $per . "/" . $name, $value);
	return;

}

sub add_hfc {

	$mqtt->retain($topic . "/hourly/" . $per . "/" . $name, $value);
	return;

}

sub mqttconnect {

	$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;
	my $mqttcred = LoxBerry::IO::mqtt_connectiondetails();
	my $mqtt_username = $mqttcred->{brokeruser};
	my $mqtt_password = $mqttcred->{brokerpass};
	my $mqttbroker = $mqttcred->{brokerhost};
	my $mqttport = $mqttcred->{brokerport};

	if (!$mqttbroker || !$mqttport) {
		print "No MQTT config found. Giving up.\n";
		exit (2);
	}
	
	# Connect
	eval {
		$mqtt = Net::MQTT::Simple->new($mqttbroker . ":" . $mqttport);
		if ($mqtt_username and $mqtt_password) {
			$mqtt->login($mqtt_username, $mqtt_password);
		}
	};
	if ($@ || !$mqtt) {
		my $error = $@ || 'Unknown failure';
		print "Cannot connect to Broker. An error occurred - $error";
		exit (2);
	};

	# Update Plugin Status
	$topic = "weather4lox" if !$topic;; # Use standard if not defined
	$mqtt->retain($topic . "/plugin/lastupdate_epoche", time());

	return();

};
