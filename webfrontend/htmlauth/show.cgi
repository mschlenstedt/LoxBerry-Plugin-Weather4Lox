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
use DateTime;
use Config::Simple;
use File::HomeDir;
use Cwd 'abs_path';
use CGI::Carp qw(fatalsToBrowser);
use CGI qw/:standard/;
#use strict;
#use warnings;

##########################################################################
# Settings
##########################################################################

# Version of this script
my $version = "4.3.0";

# Figure out in which subfolder we are installed
our $psubfolder = abs_path($0);
our $psubfolder =~ s/(.*)\/(.*)\/(.*)$/$2/g;
our $home = File::HomeDir->my_home;
our $webpath = "/plugins/$psubfolder";

our $cfg             = new Config::Simple("$home/config/system/general.cfg");
our $installfolder   = $cfg->param("BASE.INSTALLFOLDER");
our $lang            = $cfg->param("BASE.LANG");

our $pcfg            = new Config::Simple("$installfolder/config/plugins/$psubfolder/weather4lox.cfg");
our $stdtheme        = $pcfg->param("WEB.THEME");
our $stdiconset      = $pcfg->param("WEB.ICONSET");
our $metric          = $pcfg->param("SERVER.METRIC");

# Check for parameters we got from URL
foreach (split(/&/,$ENV{'QUERY_STRING'})){
  ($namef,$value) = split(/=/,$_,2);
  $namef =~ tr/+/ /;
  $namef =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
  $value =~ tr/+/ /;
  $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
  if($query{$namef}){
    $query{$namef} .= ",$value";
    $Multiple{$namef} = 1;
  }else{
    $query{$namef} = $value;
  }
}
foreach $var ("theme","lang","map","iconset","dfc","hfc") {
  if ($query{$var}) {
    ${$var} = $query{$var};
  }
}

# If it is not set, use defaults from config
if (!$theme) {
  $theme = $stdtheme;
}
if (!$iconset) {
  $iconset = $stdiconset;
}

# Build complete themeurl
$themeurl = "$ENV{REQUEST_URI}";
#$themeurl = "$ENV{HTTP_HOST}$ENV{REQUEST_URI}";
$themeurl =~ s/(.*)\?(.*)$/$1/eg;
$themeurl = $themeurl."?theme=".$theme."&lang=".$lang."&iconset=".$iconset;
$themeurlmain = "$themeurl";
$themeurldfc = "$themeurl&dfc=1";
$themeurlhfc = "$themeurl&hfc=1";
$themeurlmap = "$themeurl&map=1";

# Date Reference: Convert into Loxone Epoche (1.1.2009)
my $dateref = DateTime->new(
      year      => 2009,
      month     => 1,
      day       => 1,
      time_zone => 'local',
);

#############################################
# MAP VIEW
#############################################

# If map view is requested, open template
if ($map) {
  # Output Theme ot Browser
  print "Content-type: text/html\n\n";
  open(F,"<$home/templates/plugins/$psubfolder/themes/$lang/$theme.map.html") || die "Missing template $home/templates/plugins/$psubfolder/themes/$lang/$theme.map.html";
       while (<F>) {
         $_ =~ s/<!--\$(.*?)-->/${$1}/g;
         print $_;
       }
  close(F);

  exit;
}

#############################################
# Daily Forecast
#############################################

if ($dfc) {

  # Read data
  open(F,"<$home/log/plugins/$psubfolder/dailyforecast.dat") || die "Cannot open $home/log/plugins/$psubfolder/dailyforecast.dat";
    our @dfcdata = <F>;
  close(F);

  foreach (@dfcdata){
    s/[\n\r]//g;
    my @fields = split(/\|/);

    my $per = @fields[0] - 1;

    ${dfc.$per._per} = @fields[0] - 1;
    ${dfc.$per._date} = @fields[1];
    ${dfc.$per._day} = @fields[2];
    ${dfc.$per._month} = @fields[3];
    ${dfc.$per._monthn} = @fields[4];
    ${dfc.$per._monthn_sh} = @fields[5];
    ${dfc.$per._year} = @fields[6];
    ${dfc.$per._hour} = @fields[7];
    ${dfc.$per._min} = @fields[8];
    ${dfc.$per._wday} = @fields[9];
    ${dfc.$per._wday_sh} = @fields[10];
    ${dfc.$per._pop} = @fields[13];
    ${dfc.$per._w_dirdes_h} = @fields[17];
    ${dfc.$per._w_dir_h} = @fields[18];
    ${dfc.$per._w_dirdes_a} = @fields[20];
    ${dfc.$per._w_dir_a} = @fields[21];
    ${dfc.$per._hu_a} = @fields[22];
    ${dfc.$per._hu_h} = @fields[23];
    ${dfc.$per._hu_l} = @fields[24];
    ${dfc.$per._we_icon} = @fields[25];
    ${dfc.$per._we_code} = @fields[26];
    ${dfc.$per._we_des} = @fields[27];
    if (!$metric) {
    ${dfc.$per._tt_h} = @fields[11]*1.8+32;
    ${dfc.$per._tt_l} = @fields[12]*1.8+32;
    ${dfc.$per._prec} = @fields[14]*0.0393700787;
    ${dfc.$per._snow} = @fields[15]*0.393700787;
    ${dfc.$per._w_sp_h} = @fields[16]*0.621;
    ${dfc.$per._w_sp_a} = @fields[19]*0.621;
    } else {
    ${dfc.$per._tt_h} = @fields[11];
    ${dfc.$per._tt_l} = @fields[12];
    ${dfc.$per._prec} = @fields[14];
    ${dfc.$per._snow} = @fields[15];
    ${dfc.$per._w_sp_h} = @fields[16];
    ${dfc.$per._w_sp_a} = @fields[19];
    }
    # Use night icons between sunset and sunrise
    #if (${dfc.$per._hour} > $hour_sun_s || ${dfc.$per._hour} < $hour_sun_r) {
    #  ${dfc.$per._dayornight} = "n";
    #} else {
    #  ${dfc.$per._dayornight} = "d";
    #}

  }

  # Output Theme to Browser
  print "Content-type: text/html\n\n";
  open(F,"<$home/templates/plugins/$psubfolder/themes/$lang/$theme.dfc.html") || die "Missing template <$home/templates/plugins/$psubfolder/themes/$lang/$theme.dfc.html";
       while (<F>) {
         $_ =~ s/<!--\$(.*?)-->/${$1}/g;
         print $_;
       }
  close(F);

  exit;
}

#############################################
# Hourly Forecast
#############################################

if ($hfc) {

  # Get current weather data from database - Needed for Sunrise and Sunset
  open(F,"<$home/log/plugins/$psubfolder/current.dat") || die "Cannot open $home/log/plugins/$psubfolder/current.dat";
    our $curdata = <F>;
  close(F);
  chomp $curdata;
  my @fields = split(/\|/,$curdata);
  $hour_sun_r = @fields[34];
  $hour_sun_s = @fields[36];

  # Read data for Hourly Forecast
  open(F,"<$home/log/plugins/$psubfolder/hourlyforecast.dat") || die "Cannot open $home/log/plugins/$psubfolder/hourlyforecast.dat";
    our @hfcdata = <F>;
  close(F);

  foreach (@hfcdata){
    s/[\n\r]//g;
    my @fields = split(/\|/);

    $per = @fields[0];

    ${hfc.$per._per} = @fields[0];
    ${hfc.$per._date} = @fields[1];
    ${hfc.$per._day} = @fields[2];
    ${hfc.$per._month} = @fields[3];
    ${hfc.$per._monthn} = @fields[4];
    ${hfc.$per._monthn_sh} = @fields[5];
    ${hfc.$per._year} = @fields[6];
    ${hfc.$per._hour} = @fields[7];
    ${hfc.$per._min} = @fields[8];
    ${hfc.$per._wday} = @fields[9];
    ${hfc.$per._wday_sh} = @fields[10];
    ${hfc.$per._hu} = @fields[14];
    ${hfc.$per._w_dirdes} = @fields[15];
    ${hfc.$per._w_dir} = @fields[16];
    ${hfc.$per._pr} = @fields[19];
    ${hfc.$per._dp} = @fields[20];
    ${hfc.$per._sky} = @fields[21];
    ${hfc.$per._sky._des} = @fields[22];
    ${hfc.$per._uvi} = @fields[23];
    ${hfc.$per._pop} = @fields[26];
    ${hfc.$per._we_code} = @fields[27];
    ${hfc.$per._we_icon} = @fields[28];
    ${hfc.$per._we_des} = @fields[29];
    if (!$metric) {
    ${hfc.$per._tt} = @fields[11]*1.8+32;
    ${hfc.$per._tt_fl} = @fields[12]*1.8+32;
    ${hfc.$per._hi} = @fields[13]*1.8+32;
    ${hfc.$per._w_sp} = @fields[17]*0.621;
    ${hfc.$per._w_ch} = @fields[18]*1.8+32;
    ${hfc.$per._prec} = @fields[24]*0.0393700787;
    ${hfc.$per._snow} = @fields[25]*0.393700787;
    } else {
    ${hfc.$per._tt} = @fields[11];
    ${hfc.$per._tt_fl} = @fields[12];
    ${hfc.$per._hi} = @fields[13];
    ${hfc.$per._w_sp} = @fields[17];
    ${hfc.$per._w_ch} = @fields[18];
    ${hfc.$per._prec} = @fields[24];
    ${hfc.$per._snow} = @fields[25];
    }
    # Use night icons between sunset and sunrise
    if (${hfc.$per._hour} > $hour_sun_s || ${hfc.$per._hour} < $hour_sun_r) {
      ${hfc.$per._dayornight} = "n";
    } else {
      ${hfc.$per._dayornight} = "d";
    }

  }

  # Output Theme to Browser
  print "Content-type: text/html\n\n";
  open(F,"<$home/templates/plugins/$psubfolder/themes/$lang/$theme.hfc.html") || die "Missing template <$home/templates/plugins/$psubfolder/themes/$lang/$theme.hfc.html";
       while (<F>) {
         $_ =~ s/<!--\$(.*?)-->/${$1}/g;
         print $_;
       }
  close(F);

  exit;

}

#############################################
# CURRENT CONDITIONS
#############################################

# Get current weather data from database
open(F,"<$home/log/plugins/$psubfolder/current.dat") || die "Cannot open $home/log/plugins/$psubfolder/current.dat";
  our $curdata = <F>;
close(F);

chomp $curdata;

my @fields = split(/\|/,$curdata);

$cur_date = @fields[0];
$cur_date_des = @fields[1];
$cur_date_tz_des_sh = @fields[2];
$cur_date_tz_des = @fields[3];
$cur_date_tz = @fields[4];

our $epochdate = DateTime->from_epoch(
      epoch      => @fields[0],
      time_zone => 'local',
);

$cur_day        = sprintf("%02d", $epochdate->day);
$cur_month      = sprintf("%02d", $epochdate->month);
$cur_hour       = sprintf("%02d", $epochdate->hour);
$cur_min        = sprintf("%02d", $epochdate->minute);
$cur_year       = $epochdate->year;
$cur_loc_n      = @fields[5];
$cur_loc_c      = @fields[6];
$cur_loc_ccode  = @fields[7];
$cur_loc_lat    = @fields[8];
$cur_loc_long   = @fields[9];
$cur_loc_el     = @fields[10];
$cur_hu         = @fields[13];
$cur_w_dirdes   = @fields[14];
$cur_w_dir      = @fields[15];
$cur_sr         = @fields[22];
$cur_uvi        = @fields[24];
$cur_we_icon    = @fields[27];
$cur_we_code    = @fields[28];
$cur_we_des     = @fields[29];
$cur_moon_p     = @fields[30];
$cur_moon_a     = @fields[31];
$cur_moon_ph    = @fields[32];
$cur_moon_h     = @fields[33];

if (!$metric) {
$cur_tt         = @fields[11]*1.8+32;
$cur_tt_fl      = @fields[12]*1.8+32;
$cur_w_sp       = @fields[16]*0.621371192;
$cur_w_gu       = @fields[17]*0.621371192;
$cur_w_ch       = @fields[18]*1.8+32;
$cur_pr         = @fields[19]*0.0295301;
$cur_dp         = @fields[20]*1.8+32;
$cur_vis        = @fields[21]*0.621371192;
$cur_hi         = @fields[23]*1.8+32;
$cur_prec_today = @fields[25]*0.0393700787;
$cur_prec_1hr   = @fields[26]*0.0393700787;
} else {
$cur_tt         = @fields[11];
$cur_tt_fl      = @fields[12];
$cur_w_sp       = @fields[16];
$cur_w_gu       = @fields[17];
$cur_w_ch       = @fields[18];
$cur_pr         = @fields[19];
$cur_dp         = @fields[20];
$cur_vis        = @fields[21];
$cur_hi         = @fields[23];
$cur_prec_today = @fields[25];
$cur_prec_1hr   = @fields[26];
}

$cur_sun_r = "@fields[34]:@fields[35]";
$cur_sun_s = "@fields[36]:@fields[37]";

# Use night icons between sunset and sunrise
$hour_sun_r = @fields[34];
$hour_sun_s = @fields[36];
if ($cur_hour > $hour_sun_s || $cur_hour < $hour_sun_r) {
  $cur_dayornight = "n";
} else {
  $cur_dayornight = "d";
}

# Output Theme to Browser
print "Content-type: text/html\n\n";
open(F,"<$home/templates/plugins/$psubfolder/themes/$lang/$theme.main.html") || die "Missing template <$home/templates/plugins/$psubfolder/themes/$lang/$theme.main.html";
     while (<F>) {
       $_ =~ s/<!--\$(.*?)-->/${$1}/g;
       print $_;
     }
close(F);

exit;
