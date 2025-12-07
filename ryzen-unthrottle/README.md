# Ryzen Unthrottle
This script requires [RyzenAdj](https://github.com/FlyGoat/RyzenAdj/releases) to be installed.
This script requires sudo privileges.

Ryzen Unthrottle temporarily disables Skin Temperature Aware Power Management (STAPM) by raising it's temperature/current limit settings. It prevents STAPM from prematurely throttling the laptop when the core temperature is alright, but the external skin temperature is incorrectly inferred to be "too hot".

The script must be rerun every time the laptop is put under load, but fixes performance for periods of sustained load (games, etc). The script doesn't require arguments and can be run with `./ryzen-unthrottle.sh`