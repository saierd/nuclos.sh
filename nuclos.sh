#!/bin/bash

# Copyright (c) 2014-2016 Daniel Saier
# This project is licensed under the terms of the MIT license. See the LICENSE file.

URL="http://localhost:80"
INSTANCE="nuclos"

USER="nuclos"
PASSWORD=""

POSTGRESQL_URL="localhost:5432"
POSTGRESQL_USER="nuclos"
POSTGRESQL_PASSWORD="nuclos"
POSTGRESQL_DATABASE="nuclos"
POSTGRESQL_SCHEMA="nuclos"

CONFIGURATION_FILE="nuclos.xml"

# Credentials for the Nuclos FTP server.
readonly NUCLOS_FTP="ftp.nuclos.de"
readonly NUCLOS_FTP_USER="nightly"
NUCLOS_FTP_PASSWORD=""

default_configuration() {
    echo "<?xml version=\"1.0\"?>
<nuclos>
  <server>
    <home>/opt/nuclos</home>
    <name>${INSTANCE}</name>
    <http>
      <enabled>true</enabled>
      <port>${PORT}</port>
    </http>
    <https>
      <enabled>false</enabled>
      <port>\$443</port>
      <keystore>
        <file>/home/.keystore</file>
        <password>keystore-password</password>
      </keystore>
    </https>
    <shutdown-port>8005</shutdown-port>
    <heap-size>1024</heap-size>
    <java-home></java-home>
    <launch-on-startup>true</launch-on-startup>
  </server>
  <client>
    <singleinstance>false</singleinstance>
  </client>
  <database>
    <adapter>postgresql</adapter>
    <driver>org.postgresql.Driver</driver>
    <driverjar></driverjar>
    <connection-url>jdbc:postgresql://${POSTGRESQL_URL}/${POSTGRESQL_DATABASE}</connection-url>
    <username>${POSTGRESQL_USER}</username>
    <password>${POSTGRESQL_PASSWORD}</password>
    <schema>${POSTGRESQL_SCHEMA}</schema>
    <tablespace></tablespace>
    <tablespace-index></tablespace-index>
  </database>
</nuclos>"
}

info() {
    echo "$@"
}

error() {
    echo "$@" >&2
}

#################################
# INSTALLATION OF PREREQUISITES #
#################################

install_curl() {
    if ! dpkg --get-selections | grep -q "^curl[[:space:]]*install$" >/dev/null; then
        sudo apt-get update
        sudo apt-get -y install curl
    fi
}

install_java() {
    if ! dpkg --get-selections | grep -q "^oracle-java7-installer[[:space:]]*install$" >/dev/null; then
        info "Installing Java."

        sudo add-apt-repository -y ppa:webupd8team/java
        sudo apt-get update
        echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
        echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections

        if ! sudo apt-get -y install oracle-java7-installer oracle-java7-set-default; then
            error "Error installing Java."
        fi
    fi
}

install_prerequisites() {
    install_curl
    install_java
}

##############################
# INSTALLATION OF POSTGRESQL #
##############################

setup_postgresql() {
    info "Setting up PostgreSQL."

    sudo -u postgres createuser -d ${POSTGRESQL_USER}
    sudo -u postgres psql -c "ALTER USER ${POSTGRESQL_USER} WITH PASSWORD '${POSTGRESQL_PASSWORD}';"
    sudo -u postgres createdb -O ${POSTGRESQL_USER} ${POSTGRESQL_DATABASE}
    sudo -u postgres psql -c "CREATE SCHEMA ${POSTGRESQL_SCHEMA} AUTHORIZATION ${POSTGRESQL_USER};"
}

install_postgresql() {
    if ! dpkg --get-selections | grep -q "^postgresql[[:space:]]*install$" >/dev/null; then
        sudo apt-get update
        if ! sudo apt-get -y install postgresql; then
            error "Error installing PostgreSQL."
        fi
    fi

    setup_postgresql
}

##########################
# INSTALLATION OF NUCLOS #
##########################

check_configuration() {
    if [ ! -f ${CONFIGURATION_FILE} ]; then
        info "Creating a configuration file."

        echo $(default_configuration) >> $CONFIGURATION_FILE
    fi
}

download_nuclos() {
    version="$1"
    target_file="$2"

    ftp_jar_file="nuclos-${version}-installer-generic.jar"

    if [ ! -f ${target_file} ]; then
        info "Downloading the Nuclos installer."
        if ! curl --fail --output ${installer_file} ftp://${NUCLOS_FTP_USER}:${NUCLOS_FTP_PASSWORD}@${NUCLOS_FTP}/nuclos-${version}/${ftp_jar_file}; then
            if ! curl --fail --output ${installer_file} ftp://${NUCLOS_FTP_USER}:${NUCLOS_FTP_PASSWORD}@${NUCLOS_FTP}/nuclos-${version}-J1.7/${ftp_jar_file}; then
                error "Could not download the Nuclos installer!"
                return 1
            fi
        fi
    fi
}

install_nuclos() {
    version="$1"
    if [ -z "${version}" ]; then
        error "Please specify a version to install."
        exit 1
    fi

    install_prerequisites

    check_configuration

    installer_file="nuclos-installer-${version}.jar"

    if download_nuclos ${version} ${installer_file}; then
        info "Installing Nuclos."
        sudo java -jar ${installer_file} -s ${CONFIGURATION_FILE}

        start
    fi
}

##########################
# NUCLOS SERVER COMMANDS #
##########################

start() {
    info "Starting the Nuclos server."
    sudo service nuclos.${INSTANCE} start &> /dev/null
}

stop() {
    info "Stopping the Nuclos server."
    sudo service nuclos.${INSTANCE} stop &> /dev/null
}

restart() {
    stop
    start
}

status() {
    output=$(curl -sS -w "\n%{http_code}" "${REST_URI}/maintenance/mode")
    status_code=$(echo "${output}" | tail -n1)
    message=$(echo "${output}" | head -n-1)

    if [ "${status_code}" -ne "200" ]; then
        error "No connection."
    elif [ "${message}" = "on" ]; then
        echo "Maintenance mode."
    elif [ "${message}" = "initialized" ]; then
        echo "Starting the maintenance mode."
    else
        echo "Running."
    fi
}

check_connection() {
    # Ping the version URL to check whether the server responds with OK.
    output=$(curl -sS -w "\n%{http_code}" "${REST_URI}/version")
    status_code=$(echo "${output}" | tail -n1)

    if [ "${status_code}" -ne "200" ]; then
        error "Connection to the Nuclos server failed!"
        exit 1
    fi
}

version() {
    check_connection

    echo $(curl -sS "${REST_URI}/version")
}

login() {
    check_connection

    status_code="406"
    first_try=1

    while [ ${status_code} -eq "406" ]; do
        credentials="{\"username\":\"${USER}\",\"password\":\"${PASSWORD}\"}"
        output=$(curl -sS -w "\n%{http_code}" -X POST -H "Accept: application/json" -H "Content-Type: application/json" --data "${credentials}" "${REST_URI}/")
        status_code=$(echo "${output}" | tail -n1)
        message=$(echo "${output}" | head -n-1)

        if [ "${status_code}" -eq "406" ]; then
            if [ "${first_try}" -ne 1 ]; then
                error "Authentication failed."
            fi

            # Ask for a new password
            read -s -p "Password for Nuclos user '${USER}': " PASSWORD
            printf "\n" >&2
        else
            session_id=$(echo ${message} | grep -Po "\"sessionId\":\"\K[a-zA-Z0-9]+")
        fi

        first_try=0
    done

    echo "${session_id}"
}

logout() {
    curl -sS -H "Cookie:JSESSIONID=$1" ${REST_URI} -X DELETE
}

start_maintenance_with_session() {
    session_id="$1"

    info "Starting maintenance mode."
    curl -sS -o /dev/null -H "Cookie:JSESSIONID=${session_id}" "${REST_URI}/maintenance/start"
}

start_maintenance() {
    session_id=$(login)

    start_maintenance_with_session "${session_id}"
    logout "${session_id}"
}

end_maintenance_with_session() {
    session_id="$1"

    info "Ending maintenance mode."
    curl -sS -H "Cookie:JSESSIONID=${session_id}" "${REST_URI}/maintenance/end"
}

end_maintenance() {
    session_id=$(login)

    end_maintenance_with_session "${session_id}"
    logout "${session_id}"
}

import_nuclet() {
    nuclet_file="$1"

    session_id=$(login)

    start_maintenance_with_session "${session_id}"

    info "Importing the Nuclet."
    curl -sS -H "Cookie:JSESSIONID=${session_id}" -F "file=@${nuclet_file}" "${REST_URI}/maintenance/nucletimport"

    end_maintenance_with_session "${session_id}"

    logout "${session_id}"
}

export_nuclet() {
    nuclet_id="$1"
    filename="$2"

    if [ -z "${filename}" ]; then
        error "Please specify a filename."
        exit 1
    fi

    session_id=$(login)

    info "Exporting the Nuclet."
    curl -sS -o "${filename}" -H "Cookie:JSESSIONID=${session_id}" "${REST_URI}/maintenance/nucletexport/${nuclet_id}"

    logout "${session_id}"
}

###########################
# NUCLOS.SH CONFIGURATION #
###########################

apply_configuration() {
    REST_URI=${URL}/${INSTANCE}/rest
}

read_configuration_file() {
    filename=$1

    if [ -r "${filename}" ]; then
        # Check whether the configuration file contains code that is not a
        # variable assignment.
        if ! egrep -q -v '^#|^[^ ]*=[^;]*' "${filename}"; then
            # Reset the configuration variables.
            url=
            instance=
            user=
            password=
            postgresql_url=
            postgresql_user=
            postgresql_password=
            postgresql_database=
            postrgesql_schema=
            nuclos_ftp_password=

            # Read the configuration file.
            source "${filename}"

            # Apply the new configuration values.
            if [ -n "${url}" ]; then
                URL="${url}"
            fi
            if [ -n "${instance}" ]; then
                INSTANCE="${instance}"
            fi

            if [ -n "${user}" ]; then
                USER="${user}"
            fi
            if [ -n "${password}" ]; then
                PASSWORD="${password}"
            fi

            if [ -n "${postgresql_url}" ]; then
                POSTGRESQL_URL="${postgresql_url}"
            fi
            if [ -n "${postgresql_user}" ]; then
                POSTGRESQL_USER="${postgresql_user}"
            fi
            if [ -n "${postgresql_password}" ]; then
                POSTGRESQL_PASSWORD="${postgresql_password}"
            fi
            if [ -n "${postgresql_database}" ]; then
                POSTGRESQL_DATABASE="${postgresql_database}"
            fi
            if [ -n "${postgresql_schema}" ]; then
                POSTGRESQL_SCHEMA="${postgresql_schema}"
            fi
            if [ -n "${nuclos_ftp_password}" ]; then
                NUCLOS_FTP_PASSWORD="${nuclos_ftp_password}"
            fi
        else
            error "Configuration file contains code. Not reading it."
        fi
    fi
}

usage() {
    echo "Usage: nuclos.sh [OPTIONS] COMMAND"
    echo ""
    echo "Possible commands for managing the server:"
    echo "  status"
    echo "    Check the status of the Nuclos server"
    echo "  start"
    echo "    Start the Nuclos server"
    echo "  stop"
    echo "    Stop the Nuclos server"
    echo "  restart"
    echo "    Restart the Nuclos server"
    echo "  version"
    echo "    Find out the version of the Nuclos server"
    echo "  maintenance"
    echo "    Start the maintenance mode"
    echo "  maintenance end"
    echo "    End the maintenance mode"
    echo "  import <filename>"
    echo "    Import the given Nuclet"
    echo "  export <identifier> <filename>"
    echo "    Export the given Nuclet to the specified file"
    echo ""
    echo "Possible commands for installation:"
    echo "  install postgres"
    echo "    Install PostgreSQL locally and set it up for usage with Nuclos"
    echo "  install <version>"
    echo "    Install the given Nuclos version as well as its prerequisites"
    echo "    Uses the configuration file 'nuclos.xml' by default (can be changed with"
    echo "    the -c flag)"
    echo "    If the configuration file does not exist it is created with default values"
    echo ""
    echo "Possible options:"
    echo -e "  -h\tShow this message"
    echo -e "  -a\tThe URL of the Nuclos server"
    echo -e "  -c\tThe name of a Nuclos configuration file"
    echo -e "  -i\tSet the Nuclos instance"
    echo -e "  -u\tSet the Nuclos user"

    exit 0
}

main() {
    # Read configuration files.
    read_configuration_file "~/.nuclosrc"
    read_configuration_file ".nuclosrc"
    read_configuration_file "nuclosrc"

    # Read command line options.
    while getopts "h?a:c:i:p:u:" option; do
        case "${option}" in
            "a")
                URL="${OPTARG}"
                ;;
            "c")
                CONFIGURATION_FILE="${OPTARG}"
                ;;
            "i")
                INSTANCE="${OPTARG}"
                ;;
            "u")
                USER="${OPTARG}"
                ;;
            *)
                usage
                ;;
        esac
    done
    shift $((OPTIND-1))

    command="$1"
    shift 1

    apply_configuration

    case "${command}" in
        "status")
            status
            ;;
        "start")
            start
            ;;
        "stop")
            stop
            ;;
        "restart")
            restart
            ;;
        "version")
            version
            ;;
        "maintenance")
            case "$1" in
                "end" | "stop")
                    end_maintenance
                    ;;
                *)
                    start_maintenance
                    ;;
            esac
            ;;
        "import")
            import_nuclet "$@"
            ;;
        "export")
            export_nuclet "$@"
            ;;
        "install")
            case "$1" in
                "postgres" | "postgresql")
                    install_postgresql
                    ;;
                *)
                    install_nuclos "$@"
                    ;;
            esac
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
