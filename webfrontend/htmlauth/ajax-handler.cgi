#!/usr/bin/perl

# Copyright 2019-2023 Michael Schlenstedt, michael@loxberry.de
#                     Christian Fenzl, christian@loxberry.de
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

use CGI;
use LoxBerry::System;
use LoxBerry::JSON; # Available with LoxBerry 2.0
use warnings;
use strict;

##########################################################################
# Variables
##########################################################################

# Read Form
my $cgi = CGI->new;
my $q = $cgi->Vars;

my $version = LoxBerry::System::pluginversion();

# Globals 

##########################################################################
# AJAX
##########################################################################

print $cgi->header(
	-type => 'application/json',
	-charset => 'utf-8',
	-status => '200 OK',
);	

## Handle all ajax requests 
#require JSON;
# require Time::HiRes;
my %response;

if( !$q->{ajax} )  {
	$q->{ajax} = "fetch";
}

# Save MQTT Settings
if( $q->{ajax} eq "fetch" ) {
	$response{error} = &fetch();
	print JSON->new->canonical(1)->encode(\%response);
}

exit;

#
# Fetch weather data
#
sub fetch
{
	system ("$lbpbindir/fetch.pl -v >/dev/null 2>&1");
	return ("0");
}
