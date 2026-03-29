## Summary

This PR fixes multiple bugs in the `weather4lox-version4` branch, including three open GitHub issues (#122, #119, #40) and several additional problems found during testing. All changes have been tested on a live LoxBerry system with OpenWeatherMap and Cloud Weather Emulator enabled.

---

## Bug Fix: Ramdisk fills up ([#122](https://github.com/mschlenstedt/LoxBerry-Plugin-Weather4Lox/issues/122))

**Problem:** Every Perl script creates its `LoxBerry::Log` instance with the `logdir` parameter. This causes `LoxBerry::Log` to create a new timestamped log file on every invocation (e.g. `grabber_openweather-2026-03-19_12-00-00.log`). Since the cronjob runs every few minutes, hundreds of log files accumulate in the ramdisk (`/dev/shm`), eventually filling it up completely and causing the system to malfunction.

**Fix:** Changed all 12 Perl scripts from `logdir => "$lbplogdir"` to `filename => "$lbplogdir/weather4lox.log"` with `append => 1`. This writes all log output to a single shared log file that is appended to, preventing unbounded file creation.

**Affected files (12):**
`cronjob.pl`, `fetch.pl`, `datatoloxone.pl`, `grabber_openweather.pl`, `grabber_visualcrossing.pl`, `grabber_weatherflow.pl`, `grabber_wttrin.pl`, `grabber_wetteronline.pl`, `grabber_loxone.pl`, `grabber_foshk.pl`, `grabber_wu.pl`, `grabber_pwscatchupload.pl`

---

## Bug Fix: Icon/Code swap in hourly forecast ([#119](https://github.com/mschlenstedt/LoxBerry-Plugin-Weather4Lox/issues/119))

**Problem:** In `grabber_openweather.pl`, the regular hourly forecast data writes fields in the order `code|icon|description`, but the **interpolated** hourly data (used to fill gaps between API data points) writes them as `icon|code|description`. This causes Loxone to display wrong weather icons for interpolated hours.

**Fix:** Swapped the order in the interpolated section (around line 860) from:
```perl
$newline .= $icon; $newline .= "|"; $newline .= $code;
```
to:
```perl
$newline .= $code; $newline .= "|"; $newline .= $icon;
```

**Affected file:** `bin/grabber_openweather.pl`

---

## Bug Fix: Deprecated readlanguage call ([#40](https://github.com/mschlenstedt/LoxBerry-Plugin-Weather4Lox/issues/40))

**Problem:** `index.cgi` and `geolocation.cgi` use `LoxBerry::Web::readlanguage()` which is deprecated and triggers warnings in newer LoxBerry versions.

**Fix:** Replaced with `LoxBerry::System::readlanguage()` in both files.

**Affected files:** `webfrontend/htmlauth/index.cgi`, `webfrontend/htmlauth/geolocation.cgi`

---

## Fix: Cloud Weather Emulator returns "Data currently not available"

**Problem:** The emulator CGI at `webfrontend/html/emu/forecast/index.cgi` checks for `index.txt` using a relative path (`-e "index.txt"`). This depends on Apache's current working directory being the same as the script directory, which is not guaranteed. When Apache sets a different working directory, the file is not found and the Miniserver receives "Data currently not available" instead of weather data.

**Fix (two-part):**

1. **`index.cgi`**: Changed to use the absolute path `REPLACELBPLOGDIR/index.txt` (the placeholder is resolved during plugin installation). The CGI now reads `index.txt` directly from the ramdisk where `datatoloxone.pl` writes it, eliminating the dependency on Apache's working directory.

2. **`datatoloxone.pl`**: Additionally copies `index.txt` to the emulator forecast directory (`$lbphtmldir/emu/forecast/`) after creation as a fallback.

**Affected files:** `webfrontend/html/emu/forecast/index.cgi`, `bin/datatoloxone.pl`

---

## Fix: show.cgi crashes on fresh install or empty ramdisk

**Problem:** `show.cgi` uses `die()` when it cannot open `.dat` files (`current.dat`, `dailyforecast.dat`, `hourlyforecast.dat`). On a fresh install or after a reboot before the first weather fetch, these files may not exist, causing the CGI to crash with an Internal Server Error instead of showing a helpful message.

**Fix:** Replaced all four `die()` calls with graceful error handling that prints a user-friendly HTML message ("No weather data available yet. Please fetch weather data first.") and exits cleanly.

**Affected file:** `webfrontend/htmlauth/show.cgi`

---

## Fix: Generated HTML files and index.txt not web-accessible

**Problem:** `datatoloxone.pl` generates webpage HTML files (`webpage.html`, `webpage.dfc.html`, `webpage.hfc.html`, `webpage.map.html`, `weatherdata.html`) in the ramdisk log directory (`$lbplogdir`), but the web server serves files from `$lbphtmldir`. Without copying them, the weather pages are not accessible via the browser at `/plugins/weather4lox/`.

**Fix:**
1. **`datatoloxone.pl`**: After creating the HTML files, copies them to `$lbphtmldir` (the web-accessible plugin directory). Added `use File::Copy` for this purpose.
2. **`daemon`**: At boot, after restoring `.dat` and HTML files from persistent storage to ramdisk, copies them to the web-accessible directory (`$LBHOMEDIR/webfrontend/html/plugins/$pluginname/`). Also copies `index.txt` to the emulator forecast directory.

**Affected files:** `bin/datatoloxone.pl`, `daemon/daemon`

---

## Fix: MQTT password logged in cleartext

**Problem:** `datatoloxone.pl` logs the MQTT password in a debug message: `LOGDEB "MQTT Login with Username and Password: Sending $mqtt_username $mqtt_password"`. This exposes credentials in log files.

**Fix:** Replaced `$mqtt_password` with `********` in the log message.

**Affected file:** `bin/datatoloxone.pl`

---

## Minor Fixes

| File | Fix |
|------|-----|
| `bin/grabber_openweather.pl` | Wrong variable `$lbpconfigdir` in error message → corrected to `$lbplogdir` |
| `bin/grabber_openweather.pl` | Double semicolon `;;` → `;` |
| `bin/datatoloxone.pl` | Double semicolon `;;` → `;` |
| `webfrontend/htmlauth/index.cgi` | Duplicate `$cfg->param("SERVER.WUGRABBER", ...)` line removed |

---

## Files Changed (17)

| File | Changes |
|------|---------|
| `bin/cronjob.pl` | Log fix |
| `bin/fetch.pl` | Log fix |
| `bin/datatoloxone.pl` | Log fix, HTML copy, index.txt copy, MQTT password, double semicolon, File::Copy |
| `bin/grabber_openweather.pl` | Log fix, icon/code swap, wrong variable, double semicolon |
| `bin/grabber_visualcrossing.pl` | Log fix |
| `bin/grabber_weatherflow.pl` | Log fix |
| `bin/grabber_wttrin.pl` | Log fix |
| `bin/grabber_wetteronline.pl` | Log fix |
| `bin/grabber_loxone.pl` | Log fix |
| `bin/grabber_foshk.pl` | Log fix |
| `bin/grabber_wu.pl` | Log fix |
| `bin/grabber_pwscatchupload.pl` | Log fix |
| `daemon/daemon` | HTML + index.txt copy at boot |
| `webfrontend/html/emu/forecast/index.cgi` | Absolute path for index.txt |
| `webfrontend/htmlauth/index.cgi` | readlanguage fix, duplicate WUGRABBER removed |
| `webfrontend/htmlauth/geolocation.cgi` | readlanguage fix |
| `webfrontend/htmlauth/show.cgi` | Graceful error handling |
