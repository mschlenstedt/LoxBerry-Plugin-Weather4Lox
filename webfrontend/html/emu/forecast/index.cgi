#!/usr/bin/perl
use warnings;
use strict;
use lib 'REPLACELBHOMEDIR/libs/perllib';

use LoxBerry::System;
use LoxBerry::Log;

my $log = LoxBerry::Log->new (
    package => 'REPLACELBPPLUGINDIR',
	name => 'Emulator',
	filename => "REPLACELBPLOGDIR/emu-access.log",
	append => 1,
	addtime => 1,
);

LOGSTART("Request from $ENV{REMOTE_ADDR}");
my $requestinfo = "$ENV{'REMOTE_ADDR'} $ENV{'REQUEST_METHOD'} $ENV{'REQUEST_URI'} $ENV{'QUERY_STRING'} $ENV{'HTTP_USER_AGENT'}";

print "content-type: text/plain\r\n\r\n";

if ( -e "index.txt" ) {
	print LoxBerry::System::read_file("index.txt");
	LOGOK ("$requestinfo: Response sent");
} else {
	LOGWARN ("$requestinfo: Data currently not available");
}
LOGEND();
