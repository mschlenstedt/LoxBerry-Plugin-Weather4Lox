#!/usr/bin/perl

use LoxBerry::System;
use strict;
use warnings;

my $ip = LoxBerry::System::get_localip();
print $ip;
