#!/bin/sh

# Script meant to workaround a couple of Tailscale Update issues on Synology DSM devices :
#   - Outdated packages in Synology Package Center : https://tailscale.com/kb/1131/synology#schedule-automatic-updates
#   - Broken client capabilities after updating : https://github.com/tailscale/tailscale/issues/12203

PackageName="Tailscale"

# SCRAPE SCRIPT PATH INFO
SrceFllPth=$(readlink -f "${BASH_SOURCE[0]}")
SrceFolder=$(dirname "$SrceFllPth")
SrceFileNm=${SrceFllPth##*/}

# REDIRECT STDOUT TO TEE IN ORDER TO DUPLICATE THE OUTPUT TO THE TERMINAL AS WELL AS A .LOG FILE
exec > >(tee "$SrceFllPth.log") 2>"$SrceFllPth.debug"
# ENABLE XTRACE OUTPUT FOR DEBUG FILE
set -x

# SCRIPT VERSION
SpuscrpVer=1.0.0

# PRINT OUR GLORIOUS HEADER BECAUSE WE ARE FULL OF OURSELVES
printf "\n"
printf "%s\n" "SYNO.$PackageName UPDATE SCRIPT v$SpuscrpVer for DSM"
printf "\n"

# CHECK IF ROOT
if [ "$EUID" -ne "0" ]; then
  printf ' %s\n' "* This script MUST be run as root - exiting.."
  /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "$PackageName\n\nSyno.$PackageName Update task failed. Script was not run as root."}'
  printf "\n"
  exit 1
fi

# Function to add key-value pairs along with comments to the config file if missing
add_config_with_comment() {
  local key="$1"
  local value="$2"
  local comment="$3"
  if ! grep -q "^$key=" "$ConfigFile"; then
    printf '%s\n' "$comment"    >> "$ConfigFile"
    printf '%s\n' "$key=$value" >> "$ConfigFile"
  fi
}

# CHECK IF DEFAULT CONFIG FILE EXISTS, IF NOT CREATE IT
ConfigFile="$SrceFolder/config.ini"
if [ ! -f "$ConfigFile" ]; then
  printf '%s\n\n' "* CONFIGURATION FILE (config.ini) IS MISSING, CREATING DEFAULT SETUP.."
  touch "$ConfigFile"
fi

# Setup default configurations if missing
add_config_with_comment "NetTimeout"      "900" "# NETWORK TIMEOUT IN SECONDS (900s = 15m)"
add_config_with_comment "FixCapabilities" "1"   "# SCRIPT WILL ENSURE OUTBOUND CONNECTION CAPABILITIES ARE RETAINED IF SET TO 1"
add_config_with_comment "SelfUpdate"      "0"   "# SCRIPT WILL SELF-UPDATE IF SET TO 1"

# LOAD CONFIG FILE IF IT EXISTS
if [ -f "$SrceFolder/config.ini" ]; then
  source "$SrceFolder/config.ini"
fi

# PRINT SCRIPT STATUS/DEBUG INFO
printf '%16s %s\n' "Script:"     "$SrceFileNm"
printf '%16s %s\n' "Script Dir:" "$(fold -w 72 -s     < <(printf '%s' "$SrceFolder") | sed '2,$s/^/                 /')"

# OVERRIDE SETTINGS WITH CLI OPTIONS
while getopts ":mh" opt; do
  case ${opt} in
	m) # UPDATE TO MAIN BRANCH (NON-RELEASE)
      MasterUpdt=true
      printf '%16s %s\n' "Override:" "-m, Forcing script update from main branch"
      ;;
    h) # HELP OPTION
      printf '\n%s\n\n' "Usage: $SrceFileNm [-m] [-h]"
	  printf ' %s\n'    "-m: Update script from the main branch (non-release version)"
      printf ' %s\n\n'  "-h: Display this help message"
      exit 0
      ;;
    \?) # INVALID OPTION
      printf '\n%16s %s\n\n' "Bad Option:" "-$OPTARG, Invalid"
      exit 1
      ;;
    :) # MISSING ARGUMENT
      printf '\n%16s %s\n\n' "Bad Option:" "-$OPTARG, Requires an argument"
      exit 1
      ;;
  esac
done

# CHECK IF SCRIPT IS ARCHIVED
ScriptPrefix="syno.tailscaleupdate"
if [ ! -d "$SrceFolder/Archive/Scripts" ]; then
  mkdir -p "$SrceFolder/Archive/Scripts"
fi

if [ ! -f "$SrceFolder/Archive/Scripts/$ScriptPrefix.v$SpuscrpVer.sh" ]; then
  cp "$SrceFllPth" "$SrceFolder/Archive/Scripts/$ScriptPrefix.v$SpuscrpVer.sh"
else
  cmp -s "$SrceFllPth" "$SrceFolder/Archive/Scripts/$ScriptPrefix.v$SpuscrpVer.sh"
  if [ "$?" -ne "0" ]; then
    cp "$SrceFllPth" "$SrceFolder/Archive/Scripts/$ScriptPrefix.v$SpuscrpVer.sh"
  fi
fi

# GET EPOCH TIMESTAMP FOR AGE CHECKS
TodaysDate=$(date +%s)

# SCRAPE GITHUB WEBSITE FOR LATEST INFO
GitHubRepo=jman420/syno.tailscaleupdate
GitHubHtml=$(curl -i -m "$NetTimeout" -Ls https://api.github.com/repos/$GitHubRepo/releases?per_page=1)
if [ "$?" -eq "0" ]; then
  # AVOID SCRAPING SQUARED BRACKETS BECAUSE GITHUB IS INCONSISTENT
  GitHubJson=$(grep -oPz '\{\s{0,6}\"\X*\s{0,4}\}'          < <(printf '%s' "$GitHubHtml") | tr -d '\0')
  # ADD SQUARED BRACKETS BECAUSE ITS PROPER AND JQ NEEDS IT
  GitHubJson=$'[\n'"$GitHubJson"$'\n]'
  GitHubHtml=$(grep -oPz '\X*\{\W{0,6}\"'                   < <(printf '%s' "$GitHubHtml")  | tr -d '\0' | sed -z 's/\W\[.*//')
  # SCRAPE CURRENT RATE LIMIT
  SpusApiRlm=$(grep -oP '^x-ratelimit-limit: \K[\d]+'       < <(printf '%s' "$GitHubHtml"))
  SpusApiRlr=$(grep -oP '^x-ratelimit-remaining: \K[\d]+'   < <(printf '%s' "$GitHubHtml"))
  #if [[ -n "$SpusApiRlm" && -n "$SpusApiRlr" ]]; then
  #  SpusApiRla=$((SpusApiRlm - SpusApiRlr))
  #fi
  # SCRAPE API MESSAGES
  SpusApiMsg=$(jq -r '.[].message'                          < <(printf '%s' "$GitHubJson"))
  SpusApiDoc=$(jq -r '.[].documentation_url'                < <(printf '%s' "$GitHubJson"))
  # SCRAPE EXPECTED RELEASE-RELATED INFO
  SpusNewVer=$(jq -r '.[].tag_name'                         < <(printf '%s' "$GitHubJson"))
  SpusNewVer=${SpusNewVer#v}
  SpusRlDate=$(jq -r '.[].published_at'                     < <(printf '%s' "$GitHubJson"))
  SpusRlDate=$(date --date "$SpusRlDate" +'%s')
  SpusRelAge=$(((TodaysDate-SpusRlDate)/86400))
  if [ "$MasterUpdt" = "true" ]; then
    SpusDwnUrl=https://raw.githubusercontent.com/$GitHubRepo/main/$ScriptPrefix.sh
    SpusRelDes=$'* Check GitHub for master branch commit messages and extended descriptions'
  else
    SpusDwnUrl=https://raw.githubusercontent.com/$GitHubRepo/v$SpusNewVer/$ScriptPrefix.sh
    SpusRelDes=$(jq -r '.[].body'                             < <(printf '%s' "$GitHubJson"))
  fi
  SpusHlpUrl=https://github.com/$GitHubRepo/issues
else
  printf ' %s\n\n' "* UNABLE TO CHECK FOR LATEST VERSION OF SCRIPT.."
  ExitStatus=1
fi

printf '%16s %s\n' "Running Ver:" "$SpuscrpVer"
if [ "$SpusNewVer" = "null" ]; then
  printf "%16s %s\n" "GitHub API Msg:" "$(fold -w 72 -s     < <(printf '%s' "$SpusApiMsg") | sed '2,$s/^/                 /')"
  printf "%16s %s\n" "GitHub API Lmt:" "$SpusApiRlm connections per hour per IP"
  printf "%16s %s\n" "GitHub API Doc:" "$(fold -w 72 -s     < <(printf '%s' "$SpusApiDoc") | sed '2,$s/^/                 /')"
  ExitStatus=1
elif [ "$SpusNewVer" != "" ]; then
  printf '%16s %s\n' "Online Ver:" "$SpusNewVer (attempts left $SpusApiRlr/$SpusApiRlm)"
  printf '%16s %s\n' "Released:" "$(date --rfc-3339 seconds --date @"$SpusRlDate") ($SpusRelAge+ days old)"
fi

# COMPARE SCRIPT VERSIONS
if [[ "$SpusNewVer" != "null" ]]; then
  if /usr/bin/dpkg --compare-versions "$SpusNewVer" gt "$SpuscrpVer" || [[ "$MasterUpdt" == "true" ]]; then
    if [[ "$MasterUpdt" == "true" ]]; then
      printf '%17s%s\n' '' "* Updating from main branch!"
    else
      printf '%17s%s\n' '' "* Newer version found!"
    fi
    # DOWNLOAD AND INSTALL THE SCRIPT UPDATE
    if [ "$SelfUpdate" -eq "1" ]; then
      if [ "$SpusRelAge" -ge "$MinimumAge" ] || [ "$MasterUpdt" = "true" ]; then
        printf "\n"
        printf "%s\n" "INSTALLING NEW SCRIPT:"
        printf "%s\n" "----------------------------------------"
        /bin/wget -nv -O "$SrceFolder/Archive/Scripts/$SrceFileNm" "$SpusDwnUrl"                               2>&1
        if [ "$?" -eq "0" ]; then
          # MAKE A COPY FOR UPGRADE COMPARISON BECAUSE WE ARE GOING TO MOVE NOT COPY THE NEW FILE
          cp -f -v "$SrceFolder/Archive/Scripts/$SrceFileNm"     "$SrceFolder/Archive/Scripts/$SrceFileNm.cmp" 2>&1
          # MOVE-OVERWRITE INSTEAD OF COPY-OVERWRITE TO NOT CORRUPT RUNNING IN-MEMORY VERSION OF SCRIPT
          mv -f -v "$SrceFolder/Archive/Scripts/$SrceFileNm"     "$SrceFolder/$SrceFileNm"                     2>&1
          printf "%s\n" "----------------------------------------"
          cmp -s   "$SrceFolder/Archive/Scripts/$SrceFileNm.cmp" "$SrceFolder/$SrceFileNm"
          if [ "$?" -eq "0" ]; then
            printf '%17s%s\n' '' "* Script update succeeded!"
            /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "$PackageName\n\nSyno.$PackageName Update\n\nSelf-Update completed successfully"}'
            ExitStatus=1
            if [ -n "$SpusRelDes" ]; then
              # SHOW RELEASE NOTES
              printf "\n"
              printf "%s\n" "RELEASE NOTES:"
              printf "%s\n" "----------------------------------------"
              printf "%s\n" "$SpusRelDes"
              printf "%s\n" "----------------------------------------"
              printf "%s\n" "Report issues to: $SpusHlpUrl"
            fi
          else
            printf '%17s%s\n' '' "* Script update failed to overwrite."
            /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "$PackageName\n\nSyno.$PackageName Update\n\nSelf-Update failed."}'
            ExitStatus=1
          fi
        else
          printf '%17s%s\n' '' "* Script update failed to download."
          /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "$PackageName\n\nSyno.$PackageName Update\n\nSelf-Update failed to download."}'
          ExitStatus=1
        fi
      else
        printf ' \n%s\n' "Update newer than $MinimumAge days - skipping.."
      fi
      # DELETE TEMP COMPARISON FILE
      find "$SrceFolder/Archive/Scripts" -type f -name "$SrceFileNm.cmp" -delete
    fi
  else
    printf '%17s%s\n' '' "* No new version found."
  fi
fi
printf "\n"

# Check Tailscale CLI for Update
versionJson=$(tailscale version --upstream --json)
installedVer=$(echo "$versionJson" | grep 'short":' | cut -d\" -f4)
upstreamVer=$(echo "$versionJson" | grep 'upstream":' | cut -d\" -f4)
if [ "$installedVer" -ne "$upstreamVer" ]; then
  # Store current Tailscale Daemon capabilities
  printf '%s\n' "Retrieving Tailscale Daemon capabilities..."
  PreUpdateCapabilities=$(getcap /var/packages/Tailscale/target/bin/tailscaled)
  printf '%s\n' "  $PreUpdateCapabilities"

  # Update Tailscale via CLI
  printf '%s\n' "Updating Tailscale via CLI..."
  tailscale update --yes
  if [ "$?" -eq "0" ]; then UpdatePerformed="true"; else UpdatePerformed="false"; fi
  printf '%s\n' "  Update performed : $UpdatePerformed"

  # Restore Tailscale Daemon capabilities if needed
  PostUpdateCapabilities=$(getcap /var/packages/Tailscale/target/bin/tailscaled)
  if [ "$UpdatePerformed" -eq "true" ]; then
    if [ "$FixCapabilities" -eq "1" && "$PreUpdateCapabilities" -ne "$PostUpdateCapabilities" ]; then
      printf '%s\n' "Restoring Tailscale Daemon capabilities..."
      /var/packages/Tailscale/target/bin/tailscale configure-host
      synosystemctl restart pkgctl-Tailscale.service
    fi
  
    /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "$PackageName\n\nSyno.$PackageName Update task completed successfully"}'
    ExitStatus=1
  fi
else
  printf '%s\n' "No new Tailscale updates found."
fi
printf "\n"

# CLOSE AND NORMALIZE THE LOGGING REDIRECTIONS
exec >&- 2>&- 1>&2

# EXIT NORMALLY BUT POSSIBLY WITH FORCED EXIT STATUS FOR SCRIPT NOTIFICATIONS
if [ -n "$ExitStatus" ]; then
  exit "$ExitStatus"
fi
