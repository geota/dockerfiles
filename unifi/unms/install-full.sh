#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATH="${PATH}:/usr/local/bin"

INTERNAL_HTTP_PORT="8080"
INTERNAL_HTTPS_PORT="8443"
INTERNAL_WS_PORT="8443"
ALTERNATIVE_HTTP_PORT="8080"
ALTERNATIVE_HTTPS_PORT="8443"

COMPOSE_PROJECT_NAME="unms"
USERNAME="geota"
HOME_DIR="/home/${USERNAME}/.config/unms"
APP_DIR="${HOME_DIR}/app"
DATA_DIR="${HOME_DIR}/data"
CONFIG_DIR="${APP_DIR}/conf"
CONFIG_FILE="${APP_DIR}/unms.conf"
DOCKER_COMPOSE_FILENAME="docker-compose.yml"
DOCKER_COMPOSE_FILE="${APP_DIR}/${DOCKER_COMPOSE_FILENAME}"
DOCKER_COMPOSE_TEMPLATE_FILENAME="docker-compose.yml.template"
DOCKER_COMPOSE_TEMPLATE="${APP_DIR}/${DOCKER_COMPOSE_TEMPLATE_FILENAME}"

FIRMWARES=(
  "e50-1.9.7-hotfix.2.170818.tar|https://fw-download.ubnt.com/data/e50/773c-edgerouter-v1.9.7_2bhotfix.2-e9ec204a13474d969e9ed4e44c36b1c6.tar"
  "e100-1.9.7-hotfix.2.170818.tar|https://fw-download.ubnt.com/data/e100/86e1-edgerouter-v1.9.7_2bhotfix.2-08fc5d398291429f90f5260d1a4b2206.tar"
  "e200-1.9.7-hotfix.2.170818.tar|https://fw-download.ubnt.com/data/e200/427d-edgerouter-v1.9.7_2bhotfix.2-6ef4105842654debb61fda1683365faf.tar"
  "e1000-1.9.7-hotfix.2.170818.tar|https://fw-download.ubnt.com/data/e1000/5367-edgerouter-v1.9.7_2bhotfix.2-acd4f9f046934d07bb6ce234764cd097.tar"
  "e600-1.0.2.170728.tar|https://fw-download.ubnt.com/data/uf-olt/4a41-linux-v1.0.2-aaed6db6431c4b6e965139795b010f00.tar"
  "SFU-1.1.1.170728.bin|https://fw-download.ubnt.com/data/uf-nano/15a4-linux-v1.1.1-16715d80397f43efa6a4a57b8c05b857.bin"
  "XC-8.3.1-cs.170728.bin|https://fw-download.ubnt.com/data/XC/29f6-airmax-v8.3.1-cs-0c4b7e669ed04e5a9026863588275b7f.bin"
  "XC-8.3.1.170728.bin|https://fw-download.ubnt.com/data/XC/5da0-airmax-v8.3.1-7e17ff7ef079494f83fbed2a990aea95.bin"
  "WA-8.3.1.170728.bin|https://fw-download.ubnt.com/data/WA/5c22-airmax-v8.3.1-15b61ca16b1140039d28cabbc28ae9e5.bin"
  "WA-8.3.1-cs.170728.bin|https://fw-download.ubnt.com/data/WA/4b92-airmax-v8.3.1-cs-8cdeeacc3fa44c0d8af02633ae41461e.bin"
)

PREREQUISITES=( "curl" "sed" "envsubst" "nc" )

if [ "${SCRIPT_DIR}" = "${APP_DIR}" ]; then
  echo "Please don't run the installation script in the application directory ${APP_DIR}"
  exit 1
fi

# parse arguments
VERSION="latest"
PROD="true"
DEMO="false"
USE_LOCAL_IMAGES="false"
DOCKER_IMAGE="ubnt/unms"
DOCKER_USERNAME=""
DOCKER_PASSWORD=""
HTTP_PORT="80"
HTTPS_PORT="443"
WS_PORT=""
PROXY_HTTPS_PORT=""
PROXY_WS_PORT=""
BEHIND_REVERSE_PROXY="false"
SSL_CERT_DIR=""
SSL_CERT=""
SSL_CERT_KEY=""
SSL_CERT_CA=""
HOST_TAG=""
UNATTENDED="false"
NO_AUTO_UPDATE="false"
BRANCH="master"
SUBNET=""
NO_FIRMWARES="false"

read_previous_config() {
  # read WS port settings from existing running container
  # they were not saved to config file in versions <=0.7.18
  if ! oldEnv=$(docker inspect --format '{{ .Config.Env }}' unms); then
    echo "Failed to read WS port config from existing UNMS container"
  else
    WS_PORT=$(docker ps --filter "name=unms$" --filter "status=running" --format "{{.Ports}}" | sed -E "s/.*0.0.0.0:([0-9]+)->8444.*|.*/\1/")
    echo "Setting WS_PORT=${WS_PORT}"
    PROXY_WS_PORT=$(echo "${oldEnv}" | sed -E "s/.*[ []PUBLIC_WS_PORT=([0-9]*).*|.*/\1/")
    echo "Setting PROXY_WS_PORT=${PROXY_WS_PORT}"
  fi

  # read config file
  if [ -f "${CONFIG_FILE}" ]; then
    echo "Reading configuration file ${CONFIG_FILE}"
    cat "${CONFIG_FILE}"
    if ! source "${CONFIG_FILE}"; then
      echo "Failed to read configuration from ${CONFIG_FILE}"
      exit 1
    fi
  else
    echo "Configuration file not found."
  fi
}

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
  --dev)
    echo "Setting PROD=false"
    PROD="false"
    ;;
  --demo)
    echo "Setting DEMO=true"
    DEMO="true"
    ;;
  --update)
    echo "Restoring previous configuration"
    read_previous_config
    ;;
  --behind-reverse-proxy)
    echo "Setting BEHIND_REVERSE_PROXY=true"
    BEHIND_REVERSE_PROXY="true"
    ;;
  --unattended)
    echo "Setting UNATTENDED=true"
    UNATTENDED="true"
    ;;
  --no-auto-update)
    echo "Setting NO_AUTO_UPDATE=true"
    NO_AUTO_UPDATE="true"
    ;;
  --no-firmwares)
    echo "Setting NO_FIRMWARES=true"
    NO_FIRMWARES="true"
    ;;
  --use-local-images)
    echo "Setting USE_LOCAL_IMAGES=true"
    USE_LOCAL_IMAGES="true"
    ;;
  -v|--version)
    echo "Setting VERSION=$2"
    VERSION="$2"
    shift # past argument value
    ;;
  --docker-image)
    echo "Setting DOCKER_IMAGE=$2"
    DOCKER_IMAGE="$2"
    shift # past argument value
    ;;
  --docker-username)
    echo "Setting DOCKER_USERNAME=$2"
    DOCKER_USERNAME="$2"
    shift # past argument value
    ;;
  --docker-password)
    echo "Setting DOCKER_PASSWORD=*****"
    DOCKER_PASSWORD="$2"
    shift # past argument value
    ;;
  --data-dir)
    echo "Setting DATA_DIR=$2"
    DATA_DIR="$2"
    shift # past argument value
    ;;
  --http-port)
    echo "Setting HTTP_PORT=$2"
    HTTP_PORT="$2"
    shift # past argument value
    ;;
  --https-port)
    echo "Setting HTTPS_PORT=$2"
    HTTPS_PORT="$2"
    shift # past argument value
    ;;
  --ws-port)
    echo "Setting WS_PORT=$2"
    WS_PORT="$2"
    shift # past argument value
    ;;
  --public-https-port)
    echo "Setting PROXY_HTTPS_PORT=$2"
    PROXY_HTTPS_PORT="$2"
    shift # past argument value
    ;;
  --public-ws-port)
    echo "Setting PROXY_WS_PORT=$2"
    PROXY_WS_PORT="$2"
    shift # past argument value
    ;;
  --ssl-cert-dir)
    echo "Setting SSL_CERT_DIR=$2"
    SSL_CERT_DIR="$2"
    shift # past argument value
    ;;
  --ssl-cert)
    echo "Setting SSL_CERT=$2"
    SSL_CERT="$2"
    shift # past argument value
    ;;
  --ssl-cert-key)
    echo "Setting SSL_CERT_KEY=$2"
    SSL_CERT_KEY="$2"
    shift # past argument value
    ;;
  --ssl-cert-ca)
    echo "Setting SSL_CERT_CA=$2"
    SSL_CERT_CA="$2"
    shift # past argument value
    ;;
  --host-tag)
    echo "Setting HOST_TAG=$2"
    HOST_TAG="$2"
    shift # past argument value
    ;;
  --branch)
    echo "Setting BRANCH=$2"
    BRANCH="$2"
    shift # past argument value
    ;;
  --subnet)
    echo "Setting SUBNET=$2"
    SUBNET="$2"
    shift # past argument value
    ;;
  *)
    # unknown option
    ;;
esac
shift # past argument key
done

# check that none or all three SSL variables are set
if [ ! -z "${SSL_CERT_DIR}" ] || [ ! -z "${SSL_CERT}" ] || [ ! -z "${SSL_CERT_KEY}" ]; then
  if [ -z "${SSL_CERT_DIR}" ]; then echo "Please set --ssl-cert-dir"; exit 1; fi
  if [ -z "${SSL_CERT}" ]; then echo "Please set --ssl-cert"; exit 1; fi
  if [ -z "${SSL_CERT_KEY}" ]; then echo "Please set --ssl-cert-key"; exit 1; fi
fi

# check subnet and prepare the networks section of docker compose file
IPAM_PUBLIC=""
IPAM_PRIVATE=""
if [ ! -z "${SUBNET}" ]; then
  cidrRegex="^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?$"

  if [[ ! "${SUBNET}" =~ ${cidrRegex} ]]; then
    echo "Value of --subnet is invalid. Please use CIDR notation (ex. 172.45.0.1/24)"
    exit 1
  fi

  IFS=/ read -r subnetIp subnetPrefix <<< "${SUBNET}"
  if [ "${subnetPrefix}" -gt 27 ]; then
    echo Please specify a subnet with 32 or more addresses
    exit 1
  fi

  dec2ip () {
    local ip dec=$@ delim=""
    for e in {3..0}; do
      ((octet = dec / (256 ** e) ))
      ((dec -= octet * 256 ** e))
      ip+=$delim$octet
      delim=.
    done
    printf '%s\n' "$ip"
  }

  ip2dec () {
    local a b c d ip=$@
    IFS=. read -r a b c d <<< "$ip"
    printf '%d\n' "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
  }

  # split subnet into privateSubnet and publicSubnet
  subnetIpDec=$( ip2dec "${subnetIp}" )
  subnetMask=$(( 0xffffffff - 2 ** ( 32 - ${subnetPrefix} ) + 1 ))
  subnetIpMaskedDec=$(( ${subnetIpDec} & ${subnetMask} ))

  newSubnetPrefix=$(( ${subnetPrefix} + 1 ))
  publicSubnetIpDec=$(( ${subnetIpMaskedDec} + 1 ))
  privateSubnetIpDec=$(( ${subnetIpMaskedDec} + 1 + 2**(32 - ${newSubnetPrefix}) ))

  publicSubnetIp=$(dec2ip "${publicSubnetIpDec}")
  privateSubnetIp=$(dec2ip "${privateSubnetIpDec}")

  # prepare subnet section of the docker compose file
  IPAM_PUBLIC=$(printf "ipam:\n      config:\n        - subnet: \"${publicSubnetIp}/${newSubnetPrefix}\"")
  IPAM_PRIVATE=$(printf "ipam:\n      config:\n        - subnet: \"${privateSubnetIp}/${newSubnetPrefix}\"")
fi


export COMPOSE_PROJECT_NAME
export VERSION
export DEMO
export PROD
export DOCKER_IMAGE
export DATA_DIR
export CONFIG_DIR
export HTTP_PORT
export HTTPS_PORT
export BEHIND_REVERSE_PROXY
export SSL_CERT
export SSL_CERT_KEY
export SSL_CERT_CA
export HOST_TAG
export BRANCH
export INTERNAL_HTTP_PORT
export INTERNAL_HTTPS_PORT
export IPAM_PUBLIC
export IPAM_PRIVATE

version_equal_or_newer() {
  if [[ "$1" == "$2" ]]; then return 0; fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
  for ((i=0; i<${#ver1[@]}; i++)); do
    if [[ -z ${ver2[i]} ]]; then ver2[i]=0; fi
    if ((10#${ver1[i]} > 10#${ver2[i]})); then return 0; fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then return 1; fi
  done
  return 0;
}

check_system() {
  local architecture
  architecture=$(uname -m)
  case "${architecture}" in
    amd64|x86_64)
      ;;
    *)
      echo "Unsupported platform '${architecture}'."
      echo "UNMS supports: x86_64/amd64."
      exit 1
      ;;
  esac

  local lsb_dist
  local dist_version

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/lsb-release ]; then
      lsb_dist="$(. /etc/lsb-release && echo "${DISTRIB_ID:-}")"
  fi

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/debian_version ]; then
      lsb_dist="debian"
  fi

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/fedora-release ]; then
      lsb_dist="fedora"
  fi

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/oracle-release ]; then
      lsb_dist="oracleserver"
  fi

  if [ -z "${lsb_dist:-}" ]; then
      if [ -r /etc/centos-release ] || [ -r /etc/redhat-release ]; then
      lsb_dist="centos"
      fi
  fi

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/os-release ]; then
      lsb_dist="$(. /etc/os-release && echo "${ID:-}")"
  fi

  lsb_dist="$(echo "${lsb_dist:-}" | tr '[:upper:]' '[:lower:]')"

  supported_distro=false
  case "${lsb_dist}" in

      ubuntu)
      if [ -z "${dist_version:-}" ] && [ -r /etc/lsb-release ]; then
          dist_version="$(. /etc/lsb-release && echo "${DISTRIB_RELEASE:-}")"
      fi
      if version_equal_or_newer "${dist_version}" "16.04"; then
        supported_distro=true
      fi
      ;;

      debian)
      dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
      if version_equal_or_newer "${dist_version}" "8"; then
        supported_distro=true
      fi
      ;;

      *)
      if [ -z "${dist_version:-}" ] && [ -r /etc/os-release ]; then
        dist_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
      fi
      ;;

  esac

  for prerequisite in "${PREREQUISITES[@]}"; do
    command -v "${prerequisite}" >/dev/null 2>&1 || {
      echo >&2 "This script requires '${prerequisite}'. Please install '${prerequisite}' and try again. Aborting."
      exit 1
    }
  done

  if [ ! "$UNATTENDED" = true ] && [ ! "${supported_distro}" = true ]; then
    echo "Your distribution '${lsb_dist} ${dist_version:-}' is not supported."
    echo "We recommend that you install UNMS on Ubuntu 16.04, Debian 8 or newer."
    read -p "Would you like to continue with the installation anyway? [y/N]" -n 1 -r
    echo
    if ! [[ ${REPLY} =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi

  if [ ! "$UNATTENDED" = true ] && [[ -e /proc/meminfo ]]; then
    local memory
    local memoryUnit
    memory="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    if (which bc > /dev/null 2>&1); then
      memoryUnit=$(echo "scale=2; ${memory}/1024^2" | bc)
      memoryUnit="${memoryUnit} GB"
    else
      memoryUnit="${memory} KB"
    fi

    if [[ "${memory}" -lt 1000000 ]]; then
      echo "ERROR: Your system has only ${memoryUnit} of RAM."
      echo "UNMS requires at least 1 GB of RAM to run and 2 GB is recommended. Installation aborted."
      exit 1
    fi

    if [[ "${memory}" -lt 2000000 ]]; then
      echo "WARNING: Your system has only ${memoryUnit} RAM."
      echo "We recommend at least 2 GB RAM to run UNMS without problems."
    fi
  fi
}

install_docker() {
  if ! which docker > /dev/null 2>&1; then
    echo "Download and install Docker"
    curl -fsSL https://get.docker.com/ | sh
  fi

  if ! which docker > /dev/null 2>&1; then
    echo "Docker not installed. Please check previous logs. Aborting."
    exit 1
  fi
}

install_docker_compose() {
  if ! which docker-compose > /dev/null 2>&1; then
    echo "Download and install Docker compose."
    curl -L "https://github.com/docker/compose/releases/download/1.9.0/docker-compose-$(uname -s)-$(uname -m)" > /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi

  if ! which docker-compose > /dev/null 2>&1; then
    echo "Docker compose not installed. Please check previous logs. Aborting."
    exit 1
  fi

  DOCKER_COMPOSE_VERSION=$(docker-compose -v | sed 's/.*version \([0-9]*\.[0-9]*\).*/\1/');
  DOCKER_COMPOSE_MAJOR=${DOCKER_COMPOSE_VERSION%.*}
  DOCKER_COMPOSE_MINOR=${DOCKER_COMPOSE_VERSION#*.}

  if [ "${DOCKER_COMPOSE_MAJOR}" -lt 2 ] && [ "${DOCKER_COMPOSE_MINOR}" -lt 9 ] || [ "${DOCKER_COMPOSE_MAJOR}" -lt 1 ]; then
    echo "Docker compose version ${DOCKER_COMPOSE_VERSION} is not supported. Please upgrade to version 1.9 or newer."
    if [ "$UNATTENDED" = true ]; then exit 1; fi
    read -p "Would you like to upgrade Docker compose automatically? [y/N]" -n 1 -r
    echo
    if [[ ${REPLY} =~ ^[Yy]$ ]]
    then
      if ! curl -L "https://github.com/docker/compose/releases/download/1.9.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
        echo "Docker compose upgrade failed. Aborting."
        exit 1
      fi
      chmod +x /usr/local/bin/docker-compose
    else
      exit 1
    fi
  fi
}

create_user() {
  if [ -z "$(getent passwd ${USERNAME})" ]; then
    echo "Creating user ${USERNAME}."

    if ! useradd -m ${USERNAME}; then
      echo "Failed to create user '${USERNAME}'"
      exit 1
    fi

    if ! usermod -aG docker ${USERNAME}; then
      echo "Failed to add user '${USERNAME}' to docker group."
      exit 1
    fi
  fi
  chown "${USERNAME}" "/home/${USERNAME}"
  export USER_ID=$(id -u ${USERNAME})
}

backup_mongo() {
  if ! docker inspect unms-mongo &> /dev/null; then
    return 0
  fi

  if ! docker exec unms-mongo mongoexport --jsonArray --db unms --collection logs --out /data/db/logs.json; then
    echo "Failed to export logs from Mongo DB";
    exit 1
  fi
  if ! mv -fT "${DATA_DIR}/mongo/logs.json" "${DATA_DIR}/import/logs.json"; then
    echo "Failed to export logs from Mongo DB";
    exit 1
  fi

  if ! docker exec -t unms-mongo mongoexport --jsonArray --db unms --collection outages --out /data/db/outages.json; then
    echo "Failed to export outages from Mongo DB";
    exit 1
  fi
  if ! mv -fT "${DATA_DIR}/mongo/outages.json" "${DATA_DIR}/import/outages.json"; then
    echo "Failed to export outages from Mongo DB";
    exit 1
  fi

  echo "Stopping unms-mongo"
  docker stop unms-mongo
  echo "Removing unms-mongo"
  docker rm unms-mongo
  echo "Removing ${DATA_DIR}/mongo"
  rm -rf "${DATA_DIR}/mongo"
}

fix_080_permission_issue() {
  testFile="${APP_DIR}/docker-compose.yml"
  containerImage=$(docker ps --filter name=unms$ --format "{{ .Image }}") || true
  targetImage="ubnt/unms:0.8.0"
  tempContainer="unms-temp"
  if [ -f "${testFile}" ] && [ ! -w  "${testFile}" ] && [ "${containerImage}" = "${targetImage}" ]; then
    echo "Fixing 0.8.0 permission issue..."
    docker run --name "${tempContainer}" --entrypoint=/bin/bash -v "${APP_DIR}:/appdir" "${targetImage}" -c "chown -R ${USER_ID} /appdir"
    docker rm "${tempContainer}" || true
  else
    echo "Skipping 0.8.0 permission fix"
  fi
}

migrate_app_files() {
  oldConfigFile="${HOME_DIR}/unms.conf"
  oldDockerComposeFile="${HOME_DIR}/docker-compose.yml"
  oldDockerComposeTemplate="${HOME_DIR}/docker-compose.yml.template"
  oldConfigDir="${HOME_DIR}/conf"

  mkdir -p -m 700 "${APP_DIR}"

  if [ -f "${oldConfigFile}" ]; then mv -u "${oldConfigFile}" "${CONFIG_FILE}"; fi
  if [ -f "${oldDockerComposeFile}" ]; then mv -u "${oldDockerComposeFile}" "${DOCKER_COMPOSE_FILE}"; fi
  if [ -f "${oldDockerComposeTemplate}" ]; then mv -u "${oldDockerComposeTemplate}" "${DOCKER_COMPOSE_TEMPLATE}"; fi
  if [ -d "${oldConfigDir}" ]; then rm -rf "${oldConfigDir}"; fi

  chown -R "${USERNAME}" "${APP_DIR}" || true
}

prepare_templates() {
  echo "Preparing templates"
  cd "${SCRIPT_DIR}"

  # set home dir in update.sh
  if ! sed -i -- "s|##HOMEDIR##|${HOME_DIR}|g" update.sh; then
    echo "Failed update home dir in update.sh"
    exit 1
  fi

  # set branch name in update.sh
  if ! sed -i -- "s|##BRANCH##|${BRANCH}|g" update.sh; then
    echo "Failed update branch name in update.sh"
    exit 1
  fi
}

determine_public_ports() {
  # default for PUBLIC_HTTPS_PORT is HTTPS_PORT
  PUBLIC_HTTPS_PORT="${HTTPS_PORT}"

  # PROXY_HTTPS_PORT overrides PUBLIC_HTTPS_PORT
  if [ ! -z "${PROXY_HTTPS_PORT:-}" ]; then
    PUBLIC_HTTPS_PORT="${PROXY_HTTPS_PORT}"
  fi

  # default for PROXY_WS_PORT is PROXY_HTTPS_PORT
  if [ -z "${PROXY_WS_PORT:-}" ]; then
    PROXY_WS_PORT="${PROXY_HTTPS_PORT}"
  fi

  # default for PUBLIC_WS_PORT is WS_PORT
  PUBLIC_WS_PORT="${WS_PORT}"

  # PROXY_WS_PORT overrides PUBLIC_WS_PORT
  if [ ! -z "${PROXY_WS_PORT:-}" ]; then
    PUBLIC_WS_PORT="${PROXY_WS_PORT}"
  fi

  # if WS port is different from HTTPS port, INTERNAL_WS_PORT must also be different
  WS_PORT_MAPPING=
  if [ ! -z ${WS_PORT} ] && [ ! "${WS_PORT}" = "${HTTPS_PORT}" ]; then
    INTERNAL_WS_PORT=8444
    WS_PORT_MAPPING="- ${WS_PORT}:${INTERNAL_WS_PORT}"
  fi

  export PUBLIC_HTTPS_PORT
  export PUBLIC_WS_PORT
  export INTERNAL_WS_PORT
  export WS_PORT_MAPPING
}

create_docker_compose_file() {
  echo "Creating docker-compose.yml"
  cd "${SCRIPT_DIR}"
  if ! envsubst < "${DOCKER_COMPOSE_TEMPLATE_FILENAME}" > "${DOCKER_COMPOSE_FILENAME}"; then
    echo "Failed to create docker-compose.yml"
    exit 1
  fi
}

login_to_dockerhub() {
  if [[ ${DOCKER_USERNAME} ]]; then
    echo "Logging in to Docker Hub as ${DOCKER_USERNAME}"
    docker login -u="${DOCKER_USERNAME}" -p="${DOCKER_PASSWORD}"
  fi
}

pull_docker_images() {
  if [ ${USE_LOCAL_IMAGES} = true ]; then
    echo "Will try to use local Docker images."
    return 0
  fi

  echo "Pulling docker images."
  cd "${SCRIPT_DIR}"

  if [ -f "${DOCKER_COMPOSE_FILENAME}" ]; then
    if ! docker-compose pull; then
      echo "Failed to pull docker images"
      exit 1
    fi
  fi
}

stop_docker_containers() {
  if [ -f "${DOCKER_COMPOSE_FILE}" ]; then
    echo "Stopping docker containers."
    cd "${APP_DIR}"
    if ! docker-compose down; then
      echo "Failed to stop docker containers"
      exit 1
    fi
  fi
}

check_free_ports() {
  echo "Checking available ports"
  while nc -z 127.0.0.1 "${HTTP_PORT}" >/dev/null 2>&1; do
    if [ "$UNATTENDED" = true ]; then
      echo "ERROR: Port ${HTTP_PORT} is in use."
      exit 1;
    fi
    read -r -p "Port ${HTTP_PORT} is already in use, please choose a different HTTP port for UNMS. [${ALTERNATIVE_HTTP_PORT}]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-$ALTERNATIVE_HTTP_PORT}
  done

  while nc -z 127.0.0.1 "${HTTPS_PORT}" >/dev/null 2>&1; do
    if [ "$UNATTENDED" = true ]; then
      echo "ERROR: Port ${HTTPS_PORT} is in use."
      exit 1;
    fi
    read -r -p "Port ${HTTPS_PORT} is already in use, please choose a different HTTPS port for UNMS. [${ALTERNATIVE_HTTPS_PORT}]: " HTTPS_PORT
    HTTPS_PORT=${HTTPS_PORT:-$ALTERNATIVE_HTTPS_PORT}
  done

  export HTTP_PORT
  export HTTPS_PORT
}

create_data_volumes() {
  echo "Creating data volumes."
  echo  "Will mount ${DATA_DIR}"
  mkdir -p "${DATA_DIR}"

  # cert dir is either a new dir or a symlink to an external existing cert dir
  export CERT_DIR_MAPPING=
  if [ -z "${SSL_CERT_DIR}" ]; then
    mkdir -p -m u+rwX,g-rwx,o-rwx "${DATA_DIR}/cert"
  else
    echo "Will mount ${SSL_CERT_DIR}"
    CERT_DIR_MAPPING="- ${SSL_CERT_DIR}:/home/app/unms/cert"
  fi

  # Redis, Postgres, Fluentd
  mkdir -p -m u+rwX,g-rwx,o-rwx "${DATA_DIR}/redis"

  # containers will change permissions at startup where necessary
  chown -R "${USERNAME}" "${DATA_DIR}" || true
}

deploy_templates() {
  echo "Deploying templates"
  cd "${SCRIPT_DIR}"

  # set home dir in update.sh
  if ! sed -i -- "s|##HOMEDIR##|${HOME_DIR}|g" update.sh; then
    echo "Failed update home dir in update.sh"
    exit 1
  fi

  # set branch name in update.sh
  if ! sed -i -- "s|##BRANCH##|${BRANCH}|g" update.sh; then
    echo "Failed update branch name in update.sh"
    exit 1
  fi

  mkdir -p "${APP_DIR}"
  if ! cp -r ./* "${APP_DIR}/"; then
    echo "Failed to deploy templates to ${APP_DIR}"
    exit 1
  fi
}

save_config() {
  echo "Writing config file"
  if ! cat >"${CONFIG_FILE}" <<EOL
VERSION="${VERSION}"
DEMO="${DEMO}"
PROD="${PROD}"
DOCKER_IMAGE="${DOCKER_IMAGE}"
DATA_DIR="${DATA_DIR}"
HTTP_PORT="${HTTP_PORT}"
HTTPS_PORT="${HTTPS_PORT}"
PROXY_HTTPS_PORT="${PROXY_HTTPS_PORT}"
WS_PORT="${WS_PORT}"
PROXY_WS_PORT="${PROXY_WS_PORT}"
BEHIND_REVERSE_PROXY="${BEHIND_REVERSE_PROXY}"
SSL_CERT_DIR="${SSL_CERT_DIR}"
SSL_CERT="${SSL_CERT}"
SSL_CERT_KEY="${SSL_CERT_KEY}"
SSL_CERT_CA="${SSL_CERT_CA}"
HOST_TAG="${HOST_TAG}"
BRANCH="${BRANCH}"
SUBNET="${SUBNET}"
EOL
  then
    echo "Failed to save config file ${CONFIG_FILE}"
    exit 1
  fi
}

setup_auto_update() {
  if crontab -l -u "${USERNAME}"; then
    if ! crontab -u "${USERNAME}" -r; then
      echo "Failed to clean crontab"
      exit 1
    fi
  fi

  if [ "$NO_AUTO_UPDATE" = true ]; then
    echo "Skipping auto-update setup."
  else
    updateScript="${APP_DIR}/update.sh";
    if ! chmod +x "${updateScript}"; then
      echo "Failed to setup auto-update script"
      exit 1
    fi
    if ! (crontab -l -u "${USERNAME}"; echo "* * * * * ${updateScript} --cron > /dev/null 2>&1 || true") | crontab -u "${USERNAME}" -; then
      echo "Failed to setup auto-update cron job"
      exit 1
    fi
  fi
}

sync_firmwares() {
  if [ "${NO_FIRMWARES}" = "false" ]; then
    fwDir="${DATA_DIR}/firmwares/unms"
    mkdir -p "${fwDir}"

    echo "Deleting obsolete firmwares..."

    isOldFirmware() {
      local fw fwFile fwUrl
      for fw in "${FIRMWARES[@]}"; do
        IFS=\| read -r fwFile fwUrl <<< "${fw}"
        [ "$fwFile" = "$1" ] && return 1
      done
      return 0
    }

    existingFirmwares=( $(find "${fwDir}" -type f -printf "%f\n") )
    if [ ! -z "${existingFirmwares:-}" ]; then
      for firmwareFile in "${existingFirmwares[@]}"; do
        if isOldFirmware "${firmwareFile}"; then
          echo "Deleting ${firmwareFile}"
          rm "${fwDir}/${firmwareFile}"
        fi
      done
    fi

    echo "Downloading new firmwares..."
    for firmware in "${FIRMWARES[@]}"; do
      IFS=\| read -r firmwareFile firmwareUrl <<< "${firmware}"
      fwPath="${fwDir}/${firmwareFile}"
      if [ ! -f "${fwPath}" ]; then
        echo "Downloading ${firmwareFile}"
        if ! curl -L "${firmwareUrl}" -o "${fwPath}"; then
          echo "WARNING: Failed to download firmware ${firmwareFile}"
        fi
      fi
    done
  else
    echo "Skipping firmwares"
  fi
}

change_owner() {
  # only necessary when installing for the first time, as root
  if [ "$EUID" -eq 0 ]; then
    cd "${HOME_DIR}"

    if ! chown -R "${USERNAME}" ./*; then
      echo "Failed to change config files owner"
      exit 1
    fi
  else
    echo "Not running as root - will not change config files owner"
  fi
}

start_docker_containers() {
  echo "Starting docker containers."
  cd "${APP_DIR}"
  if ! docker-compose up -d; then
    echo "Failed to start docker containers"
    exit 1
  fi
}

remove_old_images() {
  echo "Removing old images"
  danglingImages=$(docker images -qf "dangling=true")
  if [ ! -z "${danglingImages}" ]; then docker rmi ${danglingImages} || true; fi

  currentImage=$(docker ps --format "{{.Image}}" --filter name=unms$)
  echo "Current image: ${currentImage}"
  oldImages=($(docker images --format "{{.Repository}}:{{.Tag}}" | grep ubnt/unms: || true) "")
  echo "All UNMS images: ${oldImages[*]}"

  if [ ! -z "${currentImage}" ] && [ ! -z "${oldImages}" ]; then
    tmp=()
    for value in "${oldImages[@]}"; do
      [ ! "${value}" = "${currentImage}" ] && tmp+=(${value})
    done
    oldImages=("${tmp[@]:-}")
  fi

  oldImagesString="${oldImages[*]}"
  echo "Images to remove: '${oldImages[*]}'"

  if [ ! -z "${oldImagesString}" ]; then
    echo "Removing old images '${oldImagesString}'"
    if ! docker rmi ${oldImagesString}; then
      echo "Failed to remove some old images"
    fi
  else
    echo "No old images found"
  fi

}

confirm_success() {
  echo "Waiting for UNMS to start"
  n=0
  until [ ${n} -ge 10 ]
  do
    sleep 3s
    unmsRunning=true
    nc -z 127.0.0.1 "${HTTPS_PORT}" && break
    echo "."
    unmsRunning=false
    n=$((n+1))
  done

  docker ps

  if [ "${unmsRunning}" = true ]; then
    echo "UNMS is running"
  else
    echo "UNMS is NOT running"
    exit 1
  fi
}

check_system
install_docker
install_docker_compose
create_user
backup_mongo
fix_080_permission_issue # fix issue when migrating from 0.8.0
migrate_app_files
prepare_templates
determine_public_ports # need to set all docker compose variables
create_docker_compose_file # compose file for docker-compose down
login_to_dockerhub
pull_docker_images
stop_docker_containers
check_free_ports
determine_public_ports # again - now we have all info
create_data_volumes
create_docker_compose_file # again - compose file for docker-compose up
deploy_templates
save_config
#setup_auto_update
sync_firmwares
change_owner
start_docker_containers
remove_old_images
confirm_success

exit 0
