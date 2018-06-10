#!/bin/sh

ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

echo "<INFO> Copy back existing config files"
cp -p -v -r /tmp/$ARGV1\_upgrade/config/$ARGV3/* $ARGV5/config/plugins/$ARGV3/ 

echo "<INFO> Copy back existing log files"
cp -p -v -r /tmp/$ARGV1\_upgrade/log/$ARGV3/* $ARGV5/log/plugins/$ARGV3/ 

echo "<INFO> Remove temporary folders"
rm -r /tmp/$ARGV1\_upgrade

# Read config
. $LBHOMEDIR/libs/bashlib/iniparser.sh
iniparser $ARGV5/config/plugins/$ARGV3/weather4lox.cfg "SERVER"

echo "<INFO> Recreate cronjob for fetching data from Weather Services"
if [ $SERVERCRON -eq 1 ]; then
	ln -s $ARGV5/bin/plugins/$ARGV3/fetch.pl $ARGV5/system/cron/cron.01min/$ARGV3
fi
if [ $SERVERCRON -eq 3 ]; then
	ln -s $ARGV5/bin/plugins/$ARGV3/fetch.pl $ARGV5/system/cron/cron.03min/$ARGV3
fi
if [ $SERVERCRON -eq 5 ]; then
	ln -s $ARGV5/bin/plugins/$ARGV3/fetch.pl $ARGV5/system/cron/cron.05min/$ARGV3
fi
if [ $SERVERCRON -eq 10 ]; then
	ln -s $ARGV5/bin/plugins/$ARGV3/fetch.pl $ARGV5/system/cron/cron.10min/$ARGV3
fi
if [ $SERVERCRON -eq 15 ]; then
	ln -s $ARGV5/bin/plugins/$ARGV3/fetch.pl $ARGV5/system/cron/cron.15min/$ARGV3
fi
if [ $SERVERCRON -eq 30 ]; then
	ln -s $ARGV5/bin/plugins/$ARGV3/fetch.pl $ARGV5/system/cron/cron.30min/$ARGV3
fi
if [ $SERVERCRON -eq 60 ]; then
	ln -s $ARGV5/bin/plugins/$ARGV3/fetch.pl $ARGV5/system/cron/cron.hourly/$ARGV3
fi

if [ $SERVEREMU -eq 1 ]; then
	echo "<INFO> Enabling Cloud Weather Emulator"
        $ARGV5/bin/plugins/$ARGV3/cloudemu enable > /dev/null 2>&1
fi

# Exit with Status 0
exit 0
