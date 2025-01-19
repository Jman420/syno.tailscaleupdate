# syno-tailscale-update
Custom shell script to handle auto-updating Tailscale on Synology DMS devices

Inspired by https://github.com/michealespinola/syno.plexupdate & https://www.synoforum.com/resources/tailscale-update-notifications-and-automatic-updates.206/

# Description
The script will use the built-in Synology tools and the Tailscale CLI to try to update Tailscale to the latest version.  It can also optionally preserve the Tailscale Daemon executable capabilities to address https://github.com/tailscale/tailscale/issues/12203.  The Synology Notification system is used to send notifications about failures and successful updates.  The script also has an optional self-updating feature.

# Usage
In DSM Control Panel --> Task Scheduler :
  - Create --> Scheduled Task --> User defined script
  - General --> User : root
  - Schedule --> Date : Daily
  - Task Settings --> User-defined script : /bin/bash /volume1/syno.tailscaleupdate.sh

# Configuration File
If a `config.ini` file is missing at execution time a default file will be created.

Configuration file settings :
  - NetTimeout - NETWORK TIMEOUT IN SECONDS (default 900s = 15m)
  - FixCapabilities - SCRIPT WILL ENSURE OUTBOUND CONNECTION CAPABILITIES ARE RETAINED IF SET TO 1 (default 1)
  - SelfUpdate - SCRIPT WILL SELF-UPDATE IF SET TO 1 (default 0)
