#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

branch="master" # will be replaced by install script
homeDir="/home/geota/.config/unms" # will be replaced by install script
appDir="${homeDir}/app"
requestUpdateFile="${homeDir}/data/update/request-update"
updateLogFile="${homeDir}/data/update/update.log"
lastUpdateFile="${homeDir}/data/update/last-update"
tmpDir="${homeDir}/tmp"
installScript="${tmpDir}/unms_install.sh"
installScriptUrl="https://raw.githubusercontent.com/Ubiquiti-App/UNMS/${branch}/install.sh"
rollbackDir="${homeDir}/rollback"
defaultDockerImage="ubnt/unms"

# update the update daemon's last activity timestamp
date +%s > "${lastUpdateFile}"

cron=false
if [ "$*" = "--cron" ]; then
  cron=true
fi

# if run by crontab, check if UNMS requested an update
if [ "${cron}" = false ] || [ -f "${requestUpdateFile}" ]; then
  if [ "${cron}" = true ]; then
    # if running as a cron job, redirect output to log file
    exec > ${updateLogFile} 2>&1
  fi

  echo "$(date) Updating UNMS..."

  # read target version from update request file
  version=
  if [ "${cron}" = true ] && [ -f "${requestUpdateFile}" ]; then
    version=$(<"${requestUpdateFile}")
    echo "Requested update to version ${version}"
  fi

  # remove the update request file
  if ! rm -f "${requestUpdateFile}"; then
    echo "$(date) Failed to remove update request file"
    exit 1
  fi

  # create temporary directory to download new installation files
  rm -rf "${tmpDir}"
  if ! mkdir -p "${tmpDir}"; then
    echo "$(date) Failed to create temp dir ${tmpDir}"
    exit 1
  fi

  # download install script
  if ! curl -fsSL "${installScriptUrl}" > "${installScript}"; then
    echo "$(date) Failed to download install script"
    exit 1
  fi

  # backup files necessary for rollback
  rm -rf "${rollbackDir}"
  mkdir -p "${rollbackDir}"
  if ! cp -r "${appDir}/." "${rollbackDir}/"; then
    echo "$(date) Failed to backup configuration"
    exit 1
  fi

  # run installation
  success=true
  chmod +x "${installScript}"
  args=( "--update" "--unattended" "--branch" "${branch}" "--docker-image" "${defaultDockerImage}" )
  if [ ! -z "${version}" ]; then
    args+=("--version" "${version}")
  fi
  echo "Starting UNMS installation with: ${args[@]}"
  if ! "${installScript}" "${args[@]}" "$@"; then
    echo "UNMS install script failed. Attempting rollback..."

    mv -f "${rollbackDir}/unms.conf" "${appDir}/unms.conf"

    if ! "${rollbackDir}/install-full.sh" --update --unattended; then
      echo "Rollback failed"
    else
      echo "Rollback successful"
    fi
    success=false
  fi

  # remove temporary directories
  rm -rf "${tmpDir}"
  rm -rf "${rollbackDir}"

  if [ "$success" = true ]; then
    echo "$(date) UNMS update finished"
    exit 0
  else
    echo "$(date) UNMS update failed"
    exit 1
  fi
fi

echo "$(date) UNMS update not requested."
exit 0
