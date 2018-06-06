#!/bin/sh

# Bashscript which is executed by bash *AFTER* complete installation is done
# (but *BEFORE* postupdate). Use with caution and remember, that all systems
# may be different! Better to do this in your own Pluginscript if possible.
#
# Exit code must be 0 if executed successfull.
#
# Will be executed as user "loxberry".
#
# We add 5 arguments when executing the script:
# command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER>
#
# For logging, print to STDOUT. You can use the following tags for showing
# different colorized information during plugin installation:
#
# <OK> This was ok!"
# <INFO> This is just for your information."
# <WARNING> This is a warning!"
# <ERROR> This is an error!"
# <FAIL> This is a fail!"

# To use important variables from command line use the following code:
ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

# Copy Apache2 configuration for WU4Lox
echo "<INFO> Installing Apache2 configuration for Weather4Lox"
cp $LBHOMEDIR/config/plugins/$ARGV3/apache2.conf $LBHOMEDIR/system/apache2/sites-available/001-$ARGV3.conf > /dev/null 2>&1

echo "<INFO> Installing Cronjob"
ln -s REPLACELBPBINDIR/weather4lox_cronjob.sh $LBHOMEDIR/system/cron/cron.hourly/99-weather4lox_cronjob > /dev/null 2>&1

# Copy Dummy files
echo "<INFO> Copy dummy data files"
if [ ! -e $LBPLOG/$ARGV3/current.dat ]; then
	cp $LBPDATA/$ARGV3/dummies/current.dat $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/dailyforecast.dat ]; then
	cp $LBPDATA/$ARGV3/dummies/dailyforecast.dat $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/hourlyforecast.dat ]; then
	cp $LBPDATA/$ARGV3/dummies/hourlyforecast.dat $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/hourlyhistory.dat ]; then
	cp $LBPDATA/$ARGV3/dummies/hourlyhistory.dat $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/webpage.html ]; then
	cp $LBPDATA/$ARGV3/dummies/webpage.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/webpage.map.html ]; then
	cp $LBPDATA/$ARGV3/dummies/webpage.map.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/webpage.dfc.html ]; then
	cp $LBPDATA/$ARGV3/dummies/webpage.dfc.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/webpage.hfc.html ]; then
	cp $LBPDATA/$ARGV3/dummies/webpage.hfc.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/weatherdata.html ]; then
	cp $LBPDATA/$ARGV3/dummies/weatherdata.html $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
if [ ! -e $LBPLOG/REPLACELBPPLUGINDIR/index.txt ]; then
	cp $LBPDATA/$ARGV3/dummies/index.txt $LBPLOG/$ARGV3/ > /dev/null 2>&1
fi
REPLACELBPBINDIR/weather4lox_cronjob.sh > /dev/null 2>&1

echo "<INFO> Creating Symlinks in Webfolder"
ln -s $LBPLOG/REPLACELBPPLUGINDIR/webpage.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/webpage.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/webpage.map.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/webpage.map.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/webpage.dfc.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/webpage.dfc.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/webpage.hfc.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/webpage.hfc.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/weatherdata.html $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/weatherdata.html > /dev/null 2>&1
ln -s $LBPLOG/REPLACELBPPLUGINDIR/index.txt $LBHOMEDIR/webfrontend/html/plugins/REPLACELBPPLUGINDIR/emu/forecast/index.txt > /dev/null 2>&1

# Exit with Status 0
exit 0
