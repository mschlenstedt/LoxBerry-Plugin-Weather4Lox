#!/bin/sh

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

# Installing Perl MOdule for WTTR.in Grabber
echo "<INFO> Installing Perl Module Math::Function::Interpolator"
cpanm Math::Function::Interpolator

echo "<INFO> Installing Perl Module Astro::MoonPhase"
cpanm Astro::MoonPhase

# Exit with Status 0
exit 0
