#!/usr/bin/python3
# -*- coding: utf-8 -*-

import sys
import string
import time
import paho.mqtt.client as mqtt
import json
import logging
import os
import signal
import datetime
import getopt
from queue import Queue
import hashlib
import numpy as np
from math import sin,cos,pi,asin,radians,degrees,atan2
import requests
from configparser import ConfigParser

#############################################################################
# Global vars
#############################################################################

q=Queue()
verbose=0
sensorvalues = dict()
sensors = dict()
pconfig = dict()
mqttconfig = dict()
windspeed_avg2m = list()
windspeed_avg10m = list()
winddir_avg2m = list()
winddir_avg10m = list()
historydata = dict()
data = dict()
lastsend=0

lbpconfigdir = os.popen("perl -e 'use LoxBerry::System; print $lbpconfigdir; exit;'").read()
lbpdatadir = os.popen("perl -e 'use LoxBerry::System; print $lbpdatadir; exit;'").read()
lbplogdir = os.popen("perl -e 'use LoxBerry::System; print $lbplogdir; exit;'").read()
pluginversion = os.popen("perl -e 'use LoxBerry::System; my $version = LoxBerry::System::pluginversion(); print $version; exit;'").read()

#############################################################################
# MQTT Lib functions
#############################################################################

def on_connect(client, userdata, flags, rc):
    if rc==0:
        client.connected_flag=True #set flag
        log.info("MQTT: Connected OK")
    else:
        log.critical("MQTT: Bad connection, Returned code=",rc)

def on_message(client, userdata, message):
    q.put(message)

#############################################################################
# Plugin Lib functions
#############################################################################

def readconfig():
    try:
        #with open(lbpconfigdir + '/plugin.json') as f:
        #    global pconfig
        #    pconfig = json.load(f)
        # Parse sensors
        #for item in pconfig['sensors']:
        #    global sensors
        #    sensors[item] = pconfig['sensors'][item]
        cfg = ConfigParser()
        cfg.read(lbpconfigdir + '/weather4lox.cfg'))
    except:
        log.critical("Cannot read plugin configuration")
        sys.exit()

def readhistory():
    global historydata
    file = lbpdatadir + '/history.json'
    try:
        with open(file) as f:
            global historydata
            historydata = json.load(f)
    except:
        log.info("Cannot read history data. Use default (empty) dataset")
    # Set defaults
    historydata.setdefault('rain', {}).setdefault('event', {}).setdefault('amount',0)
    historydata.setdefault('rain', {}).setdefault('event', {}).setdefault('last',0)
    historydata.setdefault('rain', {}).setdefault('hourly', {}).setdefault('amount',0)
    historydata.setdefault('rain', {}).setdefault('hourly', {}).setdefault('last',0)
    historydata.setdefault('rain', {}).setdefault('daily', {}).setdefault('amount',0)
    historydata.setdefault('rain', {}).setdefault('daily', {}).setdefault('last',0)
    historydata.setdefault('rain', {}).setdefault('weekly', {}).setdefault('amount',0)
    historydata.setdefault('rain', {}).setdefault('weekly', {}).setdefault('last',0)
    historydata.setdefault('rain', {}).setdefault('monthly', {}).setdefault('amount',0)
    historydata.setdefault('rain', {}).setdefault('monthly', {}).setdefault('last',0)
    historydata.setdefault('rain', {}).setdefault('yearly', {})
    historydata.setdefault('rain', {}).setdefault('24h', {})
    historydata.setdefault('rain', {}).setdefault('1h', {})
    historydata.setdefault('lightning', {}).setdefault('offset',0)
    historydata.setdefault('lightning', {}).setdefault('event', {}).setdefault('amount',0)
    historydata.setdefault('lightning', {}).setdefault('event', {}).setdefault('last',0)
    historydata.setdefault('lightning', {}).setdefault('hourly', {}).setdefault('amount',0)
    historydata.setdefault('lightning', {}).setdefault('hourly', {}).setdefault('last',0)
    historydata.setdefault('lightning', {}).setdefault('daily', {}).setdefault('amount',0)
    historydata.setdefault('lightning', {}).setdefault('daily', {}).setdefault('last',0)
    historydata.setdefault('lightning', {}).setdefault('weekly', {}).setdefault('amount',0)
    historydata.setdefault('lightning', {}).setdefault('weekly', {}).setdefault('last',0)
    historydata.setdefault('lightning', {}).setdefault('monthly', {}).setdefault('amount',0)
    historydata.setdefault('lightning', {}).setdefault('monthly', {}).setdefault('last',0)
    historydata.setdefault('lightning', {}).setdefault('yearly', {})
    historydata.setdefault('lightning', {}).setdefault('24h', {})
    historydata.setdefault('lightning', {}).setdefault('1h', {})

def exit_handler(a="", b=""):
    # Close MQTT
    client.loop_stop()
    log.info("MQTT: Disconnecting from Broker.")
    client.disconnect()
    # Write history data
    try:
        # Serializing json
        json_object = json.dumps(historydata, indent=4)
        with open(lbpdatadir + '/history.json', 'w') as f:
            f.write(json_object)
    except:
        log.critical("Cannot save history data")
    # close the log
    if str(logdbkey) != "":
        logging.shutdown()
        os.system("perl -e 'use LoxBerry::Log; my $log = LoxBerry::Log->new ( dbkey => \"" + logdbkey + "\", append => 1 ); LOGEND \"Good Bye.\"; $log->close; exit;'")
    else:
        log.info("Good Bye.")
    # End
    sys.exit();

def ctof(c,n):                                           # convert Celsius to Fahrenheit
  out = "-9999"
  try:
    out = round((float(c)*9/5.0) + 32,n)
  except ValueError: pass
  return out

def hpatoin(f,n):                                        # convert HPa to inHg 
  return round(float(f)/33.87,n)

def mstomph(m,n):                                        # convert ms to mph
  return round(float(m)*2.23694,n)

def intomm(f,n):                                         # convert in to mm
  return round(float(f)/0.0393701,n)

def mmtoin(f,n):                                         # convert mm to in
  return round(float(f)/25.4,n)

def avgwind(d):                                          # get avg from list
  s = sinSum = cosSum = 0;
  # https://www.dwd.de/DE/leistungen/lf_11_flugwetterbetriebsdienste/handbuch_band_tech_v4.0.pdf
  l = len(d)
  if len(d) < 1:
      return -9999
  for i in range(l):
      sinSum += sin(radians(d[i]));
      cosSum += cos(radians(d[i]));
  a = round((degrees(atan2(sinSum, cosSum)) + 360) % 360,1)
  return a

def rainstats(x, rainrate, amount):                       # Create rain stats
  global historydata
  ret = dict()
  thishour = str( x.strptime(x.strftime("%Y/%m/%d %H:00:00"), "%Y/%m/%d %H:%M:%S").timestamp() )
  thisminute = str( x.strptime(x.strftime("%Y/%m/%d %H:%M:00"), "%Y/%m/%d %H:%M:%S").timestamp() )
  if float(rainrate) >= 0.03937: # Calculate Rain Event, https://www.wetterstationsforum.info/viewtopic.php?t=241
      historydata['rain']['event']['amount'] = round(float(historydata['rain']['event']['amount']) + amount,3)
      historydata['rain']['event']['last'] = str(x.timestamp())
  historydata['rain']['hourly']['amount'] = round(float(historydata['rain']['hourly']['amount']) + amount,3)
  historydata['rain']['daily']['amount'] = round(float(historydata['rain']['daily']['amount']) + amount,3)
  historydata['rain']['weekly']['amount'] = round(float(historydata['rain']['weekly']['amount']) + amount,3)
  historydata['rain']['monthly']['amount'] = round(float(historydata['rain']['monthly']['amount']) + amount,3)
  historydata.setdefault('rain', {}).setdefault('yearly', {}).setdefault(x.strftime("%Y"),0)
  historydata['rain']['yearly'][x.strftime("%Y")] = round(float(historydata['rain']['yearly'][x.strftime("%Y")]) + amount,3)
  historydata['rain']['hourly']['last'] = str(x.timestamp())
  historydata['rain']['daily']['last'] = str(x.timestamp())
  historydata['rain']['weekly']['last'] = str(x.timestamp())
  historydata['rain']['monthly']['last'] = str(x.timestamp())
  ret['1'] = rainrate
  ret['2'] = round(float(historydata['rain']['event']['amount']),3)
  ret['3'] = 0
  for minute in historydata['rain']['1h']:
      ret['3'] = round(ret['3'] + float(historydata['rain']['1h'][minute]),3)
  ret['4'] = round(float(historydata['rain']['daily']['amount']),3)
  ret['5'] = round(float(historydata['rain']['weekly']['amount']),3)
  ret['6'] = round(float(historydata['rain']['monthly']['amount']),3)
  ret['7'] = round(float(historydata['rain']['yearly'][x.strftime("%Y")]),3)
  ret['8'] = 0
  for year in historydata['rain']['yearly']:
      ret['8'] = round(ret['8'] + float(historydata['rain']['yearly'][year]),3)
  historydata.setdefault('rain', {}).setdefault('24h', {}).setdefault(thishour,0)
  historydata['rain']['24h'][thishour] = historydata['rain']['hourly']['amount']
  ret['9'] = 0
  for hour in historydata['rain']['24h']:
      ret['9'] = round(ret['9'] + float(historydata['rain']['24h'][hour]),3)
  historydata.setdefault('rain', {}).setdefault('1h', {}).setdefault(thisminute,0)
  historydata['rain']['1h'][thisminute] = amount
  return (ret)

def lightningstats(x, number, amount):                    # Create lightning stats
  global historydata
  ret = dict()
  thishour = str( x.strptime(x.strftime("%Y/%m/%d %H:00:00"), "%Y/%m/%d %H:%M:%S").timestamp() )
  thisminute = str( x.strptime(x.strftime("%Y/%m/%d %H:%M:00"), "%Y/%m/%d %H:%M:%S").timestamp() )
  historydata['lightning']['offset'] = number
  historydata['lightning']['hourly']['amount'] = int(historydata['lightning']['hourly']['amount']) + amount
  historydata['lightning']['daily']['amount'] = int(historydata['lightning']['daily']['amount']) + amount
  historydata['lightning']['weekly']['amount'] = int(historydata['lightning']['weekly']['amount']) + amount
  historydata['lightning']['monthly']['amount'] = int(historydata['lightning']['monthly']['amount']) + amount
  historydata.setdefault('lightning', {}).setdefault('yearly', {}).setdefault(x.strftime("%Y"),0)
  historydata['lightning']['yearly'][x.strftime("%Y")] = int(historydata['lightning']['yearly'][x.strftime("%Y")]) + amount
  historydata['lightning']['hourly']['last'] = str(x.timestamp())
  historydata['lightning']['daily']['last'] = str(x.timestamp())
  historydata['lightning']['weekly']['last'] = str(x.timestamp())
  historydata['lightning']['monthly']['last'] = str(x.timestamp())
  ret['1'] = int(historydata['lightning']['daily']['amount'])
  ret['2'] = int(historydata['lightning']['event']['amount'])
  ret['3'] = 0
  for minute in historydata['lightning']['1h']:
      ret['3'] = int(round(ret['3'] + float(historydata['lightning']['1h'][minute]),1))
  ret['4'] = int(historydata['lightning']['daily']['amount'])
  ret['5'] = int(historydata['lightning']['weekly']['amount'])
  ret['6'] = int(historydata['lightning']['monthly']['amount'])
  ret['7'] = int(historydata['lightning']['yearly'][x.strftime("%Y")])
  ret['8'] = 0
  for year in historydata['lightning']['yearly']:
      ret['8'] = int(ret['8'] + int(historydata['lightning']['yearly'][year]))
  thishour = str( x.strptime(x.strftime("%Y/%m/%d %H:00:00"), "%Y/%m/%d %H:%M:%S").timestamp() )
  thisminute = str( x.strptime(x.strftime("%Y/%m/%d %H:%M:00"), "%Y/%m/%d %H:%M:%S").timestamp() )
  historydata.setdefault('lightning', {}).setdefault('24h', {}).setdefault(thishour,0)
  historydata['lightning']['24h'][thishour] = historydata['lightning']['hourly']['amount']
  ret['9'] = 0
  for hour in historydata['lightning']['24h']:
      ret['9'] = int(round(ret['9'] + float(historydata['lightning']['24h'][hour]),1))
  historydata.setdefault('lightning', {}).setdefault('1h', {}).setdefault(thisminute,0)
  historydata['lightning']['1h'][thisminute] = amount
  return (ret)

#############################################################################
# Main Script
#############################################################################

# Standard loglevel
loglevel="ERROR"
logfile=""
logdbkey=""

# Get full command-line arguments
# https://stackabuse.com/command-line-arguments-in-python/
full_cmd_arguments = sys.argv
argument_list = full_cmd_arguments[1:]
short_options = "vlfd:"
long_options = ["verbose","loglevel=","logfile=","logdbkey="]

try:
    arguments, values = getopt.getopt(argument_list, short_options, long_options)
except getopt.error as err:
    print (str(err))
    sys.exit(2)

for current_argument, current_value in arguments:
    if current_argument in ("-v", "--verbose"):
        loglevel="DEBUG"
        verbose=1
    elif current_argument in ("-l", "--loglevel"):
        loglevel=current_value
    elif current_argument in ("-f", "--logfile"):
        logfile=current_value
    elif current_argument in ("-d", "--logdbkey"):
        logdbkey=current_value

# Logging with standard LoxBerry log format
numeric_loglevel = getattr(logging, loglevel.upper(), None)
if not isinstance(numeric_loglevel, int):
    raise ValueError('Invalid log level: %s' % loglevel)

if str(logfile) == "":
    logfile = str(lbplogdir) + "/" + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3] + "_w4l-gateway.log"

log = logging.getLogger()
fileHandler = logging.FileHandler(logfile)
formatter = logging.Formatter('%(asctime)s.%(msecs)03d <%(levelname)s> %(message)s',datefmt='%H:%M:%S')

if verbose == 1:
    streamHandler = logging.StreamHandler(sys.stdout)
    streamHandler.setFormatter(formatter)
    log.addHandler(streamHandler)

fileHandler.setFormatter(formatter)
log.addHandler(fileHandler)

# Logging Starting message
log.setLevel(logging.INFO)
log.info("Starting Logfile for w4l-gateway. The Loglevel is %s" % loglevel.upper())
log.setLevel(numeric_loglevel)

# Read MQTT config
mqttconfig['server'] = os.popen("perl -e 'use LoxBerry::IO; my $mqttcred = LoxBerry::IO::mqtt_connectiondetails(); print $mqttcred->{brokerhost}; exit'").read()
mqttconfig['port'] = os.popen("perl -e 'use LoxBerry::IO; my $mqttcred = LoxBerry::IO::mqtt_connectiondetails(); print $mqttcred->{brokerport}; exit'").read()
mqttconfig['username'] = os.popen("perl -e 'use LoxBerry::IO; my $mqttcred = LoxBerry::IO::mqtt_connectiondetails(); print $mqttcred->{brokeruser}; exit'").read()
mqttconfig['password'] = os.popen("perl -e 'use LoxBerry::IO; my $mqttcred = LoxBerry::IO::mqtt_connectiondetails(); print $mqttcred->{brokerpass}; exit'").read()

# Read Plugin config
readconfig()

# Read history data
readhistory()

# Conncect to broker
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
client.connected_flag=False
client.on_connect = on_connect

if mqttconfig['username'] and mqttconfig['password']:
    log.info("Using MQTT Username and password.")
    client.username_pw_set(username = mqttconfig['username'],password = mqttconfig['password'])

log.info("Connecting to Broker %s on port %s." % (mqttconfig['server'], str(mqttconfig['port'])))
client.connect(mqttconfig['server'], port = int(mqttconfig['port']))

# Subscription for W4L Topic
log.info("Subscribe to: " + cfg.get('SERVER','TOPIC') + "/#")
client.subscribe(cfg.get('SERVER','TOPIC') + "/#", qos=0)
client.on_message = on_message

# Start MQTT Loop
client.loop_start()

# Wait for connection
counter=0
while not client.connected_flag: #wait in loop
    log.info("MQTT: Wait for connection...")
    time.sleep(1)
    counter+=1
    if counter > 60:
        log.critical("MQTT: Cannot connect to Broker %s on port %s." % (mqttconfig['server'], str(mqttconfig['port'])))
        exit()

# Start MQTT Loop
client.loop_start()

# Exit handler
signal.signal(signal.SIGTERM, exit_handler)
signal.signal(signal.SIGINT, exit_handler)

# Loop
while True:

    # Check for any subscribed messages in the queue
    while not q.empty():
        message = q.get()
        response = ""

        log.debug("Received subscription: " + str(message.topic) + " Payload: " + str(message.payload.decode("utf-8")))

        if message is None:
            continue

        # Check for new measurement
        for item in sensors:
            if sensors[item]['topic'] in message.topic:
                data.setdefault(item, {})
                data[item].clear()
                log.debug("Received Measurement " + item + " (Original): " + str(message.topic) + " " + str(message.payload.decode("utf-8")))
                # Temperature
                if item == "temp":
                    data[item]['1'] = ctof(float(message.payload),1)
                # Humidity
                elif item == "humidity":
                    data[item]['1'] = round(float(message.payload),1)
                # Pressure
                elif item == "pressure":
                    data[item]['1'] = hpatoin(float(message.payload),3)
                    # Calculate relative pressure: https://www.bjoerns-techblog.de/2017/12/luftdruck-absolut-oder-relativ/
                    # https://www.wetterstationsforum.info/viewtopic.php?t=171#p1443
                    correction = 0
                    if 'height' in sensors[item]:
                        if float(sensors[item]['height']) > 0 and sensors[item]['height'] is not None:
                            if float(sensors[item]['height']) > 880:
                                correction = float(sensors[item]['height']) / 11
                            else:
                               correction = float(sensors[item]['height']) / 8
                    data[item]['2'] = hpatoin(float(message.payload) + correction,3)
                # Illuminance
                elif item == "illuminance":
                    data[item]['1'] = round(float(message.payload),1)
                    if int(sensors[item]['calc_sr']) > 0: # Calc SolarRadiation from Lux. 126.7 is the facotor Ecowitt uses
                        data[item]['2'] = round(float(data['1'])/126.7,2)    # https://www.extrica.com/article/21667/pdf
                # Twilight
                elif item == "twilight":
                    data[item]['1'] = -9999
                    if 'max' in sensors[item]:
                        if float(sensors[item]['max']) > 0 and sensors[item]['max'] is not None:
                            data[item]['1'] = round( float(message.payload) / float(sensors[item]['max']) * 100,1)
                # UV Index
                elif item == "uv":
                    data[item]['1'] = round(float(message.payload) / 0.1,1)
                # Windspeed
                elif item == "windspeed":
                    wind = mstomph(float(message.payload),2)
                    while len(windspeed_avg2m) > 39: # Interval 3 sec, 40 values
                        del windspeed_avg2m[0]
                    while len(windspeed_avg10m) > 199: # Interval 3 sec, 200 values
                        del windspeed_avg10m[0]
                    windspeed_avg2m.append(wind)
                    windspeed_avg10m.append(wind)
                    data[item]['1'] = wind
                    data[item]['2'] = max(windspeed_avg2m)
                    data[item]['3'] = round(np.mean(windspeed_avg2m),2)
                    data[item]['4'] = round(np.mean(windspeed_avg10m),2)
                # Winddir
                elif item == "winddir":
                    volt = round( float(message.payload),1 )
                    while len(winddir_avg2m) > 39: # Interval 3 sec, 40 values
                        del winddir_avg2m[0]
                    while len(winddir_avg10m) > 199: # Interval 3 sec, 200 values
                        del winddir_avg10m[0]
                    if str(volt) in sensors[item]['converttable']:
                        data[item]['1'] = sensors[item]['converttable'][str(volt)]
                        winddir_avg2m.append(float(data[item]['1']))
                        winddir_avg10m.append(float(data[item]['1']))
                    else:
                        data[item]['1'] = -9999
                        if len(winddir_avg10m) > 0 and len(winddir_avg2m) > 0:
                            last = winddir_avg2m[-1]
                            winddir_avg2m.append(float(last))
                            last = winddir_avg10m[-1]
                            winddir_avg10m.append(float(last))
                    data[item]['2'] = avgwind(winddir_avg2m)
                    data[item]['3'] = avgwind(winddir_avg10m)
                # Solar Radiation
                elif item == "solarradiation":
                    value = float(message.payload)
                    if 'offset' in sensors[item] and sensors[item]['offset'] is not None:
                        value = value - float(sensors[item]['offset'])
                    if float(value) < 0:
                        value = 0
                    data[item]['1'] = "-9999"
                    if 'max' in sensors[item]:
                        if float(sensors[item]['max']) > 0 and sensors[item]['max'] is not None:
                            sr = round( (float(value) * 1000) / float(sensors[item]['max']) * 1000,1)
                            if sr < 0.6:
                                data[item]['1'] = 0
                            else:
                                data[item]['1'] = round( float(sr),1)
                # Rain State
                elif item == "rainstate":
                    input = message.payload.decode("utf-8")
                    data.setdefault(item, {}).setdefault('cur_state',0)
                    if str(input) == "ON":
                        data[item]['1'] = 1
                        data['rainstate']['cur_state'] = 1
                    else:
                        data[item]['1'] = 0
                        data['rainstate']['cur_state'] = 0
                # Rain Rate
                elif item == "rainrate":
                    data.setdefault('rainstate', {}).setdefault('cur_state',0)
                    x = datetime.datetime.now()
                    rainrate = mmtoin(float(message.payload) * 6,3) # Rate is mm/10m, so factor 6 for mm/hr
                    amount = mmtoin(float(message.payload),3) # Amount in the last 10 minutes
                    if float(sensors['rainstate']['calc_rr']) > 0 and float(data['rainstate']['cur_state']) > 0 and rainrate < 0.5: # Calculate rainrate from rainstate
                        rainrate = mmtoin(float(0.5),3) # 0.5 mm/hr
                        amount = mmtoin(float(0.083),3) # 0.5mm/h, Amount in the last 10 minutes
                    ret = rainstats(x, rainrate, amount)
                    data[item]['1'] = rainrate
                    data[item]['2'] = float(ret['2'])
                    data[item]['3'] = float(ret['3'])
                    data[item]['4'] = float(ret['4'])
                    data[item]['5'] = float(ret['5'])
                    data[item]['6'] = float(ret['6'])
                    data[item]['7'] = float(ret['7'])
                    data[item]['8'] = float(ret['8'])
                    data[item]['9'] = float(ret['9'])
                # Lightning Last
                elif item == "lightning_last":
                    try:
                        x = datetime.datetime.utcfromtimestamp(float(message.payload)) # Convert to UTC
                        last =  int(x.timestamp())
                        if last < 0:
                            last = 0
                        data[item]['1'] = str( last )
                    except:
                        data[item]['1'] = 0
                # Lightning Distance
                elif item == "lightning_distance":
                    data[item]['1'] = round(float(message.payload),1)
                # Lightning Number
                elif item == "lightning_number":
                    x = datetime.datetime.now()
                    number = float(message.payload)
                    if number < int(historydata['lightning']['offset']): # Seems plugin was restarted
                        historydata['lightning']['offset'] = 0
                    amount = number - int(historydata['lightning']['offset'])
                    ret = lightningstats(x, number, amount)
                    data[item]['1'] = int(number)
                    data[item]['2'] = int(ret['2'])
                    data[item]['3'] = int(ret['3'])
                    data[item]['4'] = int(ret['4'])
                    data[item]['5'] = int(ret['5'])
                    data[item]['6'] = int(ret['6'])
                    data[item]['7'] = int(ret['7'])
                    data[item]['8'] = int(ret['8'])
                    data[item]['9'] = int(ret['9'])


                # Save new current data
                for val in data[item]:
                    if 'name'+val in sensors[item] and data[item][val] is not None:
                        sensorvalues[str(sensors[item]['name'+val])] = data[item][val]
                        log.debug("Received Measurement " + item + " (Converted): " + str(sensors[item]['name'+val]) + " " + str(data[item][val]))
                #data[item].clear()
                log.debug("Stored History Data: " + str(historydata))
                log.debug("Stored Windspeed AVG2m Data: " + str(windspeed_avg2m))
                log.debug("Stored Windspeed AVG10m Data: " + str(windspeed_avg10m))
                log.debug("Stored Winddir AVG2m Data: " + str(winddir_avg2m))
                log.debug("Stored Winddir AVG10m Data: " + str(winddir_avg10m))

    # Loop
    now = datetime.datetime.now()

    # Reset / calculate some historical data
    # Rain
    if float(now.timestamp()) > float(historydata['rain']['event']['last']) + 86400: # Event, https://www.wetterstationsforum.info/viewtopic.php?t=241
        historydata['rain']['event']['amount'] = 0
    y = datetime.datetime.fromtimestamp(float(historydata['rain']['hourly']['last']))
    if now.strftime("%H") != y.strftime("%H"): # Hourly
        historydata['rain']['hourly']['amount'] = 0
    if now.strftime("%j") != y.strftime("%j"): # Daily
        historydata['rain']['daily']['amount'] = 0
    if now.strftime("%W") != y.strftime("%W"): # Weekly
        historydata['rain']['weekly']['amount'] = 0
    if now.strftime("%m") != y.strftime("%m"): # Monthly
        historydata['rain']['monthly']['amount'] = 0
    for hour in list(historydata['rain']['24h']): # 24h
        if float(now.timestamp()) > float(hour) + 86400:
            del historydata['rain']['24h'][hour]
    for minute in list(historydata['rain']['1h']): # 1h
        if float(now.timestamp()) > float(minute) + 3600:
            del historydata['rain']['1h'][minute]
    # Lightning
    if float(now.timestamp()) > float(historydata['lightning']['event']['last']) + 86400: # Event, https://www.wetterstationsforum.info/viewtopic.php?t=241
        historydata['lightning']['event']['amount'] = 0
    y = datetime.datetime.fromtimestamp(float(historydata['lightning']['hourly']['last']))
    if now.strftime("%H") != y.strftime("%H"): # Hourly
        historydata['lightning']['hourly']['amount'] = 0
    if now.strftime("%j") != y.strftime("%j"): # Daily
        historydata['lightning']['daily']['amount'] = 0
    if now.strftime("%W") != y.strftime("%W"): # Weekly
        historydata['lightning']['weekly']['amount'] = 0
    if now.strftime("%m") != y.strftime("%m"): # Monthly
        historydata['lightning']['monthly']['amount'] = 0
    for hour in list(historydata['lightning']['24h']): # 24h
        if float(now.timestamp()) > float(hour) + 86400:
            del historydata['lightning']['24h'][hour]
    for minute in list(historydata['lightning']['1h']): # 1h
        if float(now.timestamp()) > float(minute) + 3600:
            del historydata['lightning']['1h'][minute]

    # Send data every x seconds
    if float(now.timestamp()) > float(lastsend) + float(pconfig['ecowittinterval']):
        lastsend = float(now.timestamp())
        sensorvalues['dateutc'] = str( datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S") )
        try:
            url = pconfig['ecowittserver'] + ":" + pconfig['ecowittport'] + '/data/report/'
            response = requests.post(url, data = sensorvalues)
            log.debug("Response from Server: " + response.text)
        except requests.exceptions.RequestException as e:
            log.critical("Cannot send data to Ecowitt server! Error: " + str(e))

    time.sleep(0.1)
