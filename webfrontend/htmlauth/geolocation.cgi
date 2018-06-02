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

use LoxBerry::System;
use LoxBerry::Web;
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use LWP::UserAgent;
use JSON qw( decode_json );
use utf8;
use Encode qw(encode_utf8);
use warnings;
use strict;

##########################################################################
# Variables
##########################################################################

our $cfg;
our $pphrase;
our $lang;
our $template_title;
our $installdir;
our $planguagefile;
our $table;
our $version;
our $search;
our $queryurl;
our $res;
our $ua;
our $json;
our $decoded_json;
our $urlstatus;
our $urlstatuscode;
our $i;
our $results;
our $decoded_json;
our $lat;
our $long;
our $numrestotal;
our $template;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
$version = "4.1.1";

# Language
our $lang = lblanguage();

#########################################################################
# Parameter
#########################################################################

my $cgi = CGI->new;
$cgi->import_names('R');

$search = $R::search;
$search = quotemeta($search);

# Template
my $template = HTML::Template->new(
    filename => "$lbptemplatedir/addresslist.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
    #associate => $cfg,
);

##########################################################################
# Language Settings
##########################################################################

# Read translations
my %L = LoxBerry::Web::readlanguage($template, "language.ini");

##########################################################################
# Main program
##########################################################################

if ($search) {

  $queryurl = "http://maps.googleapis.com/maps/api/geocode/json?sensor=false&address=$search";

  # If we received a query, send it to Google API
  $ua = new LWP::UserAgent;
  $res = $ua->get($queryurl);

  $json=$res->decoded_content();
  $json = encode_utf8( $json );

  # JSON Answer
  $decoded_json = decode_json( $json );

  $urlstatus = $res->status_line;
  $urlstatuscode = substr($urlstatus,0,3);

  # Count results
  $numrestotal = 0;
  for my $results( @{$decoded_json->{results}} ){
    $numrestotal++;
  }
 
  if (!$numrestotal) {
    $table = "<tr><td align=\"center\">" . $L{'SETTINGS.HINT_NO_SEARCH_RESULTS'} . "</td></tr>\n";
  } else { 
    $i = 1;
      for $results( @{$decoded_json->{results}} ){
        $lat = $results->{geometry}->{location}->{lat};
        $long = $results->{geometry}->{location}->{lng};
        $table = $table . "<tr><td align=\"right\">$i\.</td><td>$results->{formatted_address}</td>\n";
        $table = "$table" ."<td style=\"vertical-align: middle; text-align: center\"><button type=\"button\" data-role=\"button\" data-inline=\"true\" data-mini=\"true\" onClick=\"window.opener.document.getElementById('coordlat').value = '$lat';window.opener.document.getElementById('coordlong').value = '$long';window.close()\"> <font size=\"-1\">" . $L{'SETTINGS.BUTTON_APPLY'} .  "</font></button></td></tr>\n";
        $i++;
      };
  }

  $template->param( "TABLE", $table);
}

LoxBerry::Web::head();
print $template->output();
LoxBerry::Web::foot();

exit;
