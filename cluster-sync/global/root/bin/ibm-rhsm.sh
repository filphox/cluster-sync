#!/bin/bash
Version=0.10.6
############################################################################
#
#               ------------------------------------------
#               THIS SCRIPT PROVIDED AS IS WITHOUT SUPPORT
#               ------------------------------------------
#
# Questions/feedback: https://ltc.linux.ibm.com/support/ltctools.php
#
# Description: Wrapper script for subscription-manager to register RHEL 6,
#              7, 8, 9 systems with the internal Red Hat Satellite using
#              FTP3 credentials.
#
# The following environment variables can be used:
#
#   FTP3USER=user@cc.ibm.com        FTP3 Account
#   FTP3PASS=mypasswd               FTP3 Password
#   FTP3FORCE=y                     FTP3 force registration
#
# You must be root to perform registration activities with this script. The user
# id and password will be prompted for if the environment variables are not set.
#
# example uses might be:
#
#  1.  ./ibm-rhsm.sh --register
#  2.  FTP3USER=user@cc.ibm.com ./ibm-rhsm.sh --register
#  3.  ./ibm-rhsm.sh --list-systems
#  4.  ./ibm-rhsm.sh --delete-systems
#
# The first example is a good way to test this script.
# The second example shows how to set the FTP3USER environment variable on
# the command line.
# The third example gets the list of registered systems you own.
# The fourth example removes all systems you own from your subscription.
#
# NOTE: Some parts of this script were extracted
#       from the good old ibm-yum.sh script.
#
############################################################################

## if xtrace flag activated the activate also verbose for debugging
[[ $(set -o |grep xtrace|cut -d' ' -f10|cut -f2) == "on" ]] && set -o verbose

if [ -z "$IBM_RHSM_REG_LOG" ] ; then
    IBM_RHSM_REG_LOG="ibm-rhsm.log"
fi
## default host
[[ -z "$FTP3HOST" ]] && FTP3HOST="ftp3.linux.ibm.com"
API_URL=
SUPPORT_URL=https://ltc.linux.ibm.com/support/ltctools.php

## supported values
SUPPORTED_RELEASES=(6 7 8 9)
SUPPORTED_VERSIONS=(server workstation client release)
SUPPORTED_ARCHS=(x86_64 ppc64le ppc64 s390x)

## Script progress
##   warmup:  beginning of the process, mostly checking small things ; it has no meaning to clean up on exit
##   parsing:  processing user input
##   initializing:  preparing to perform the specified action
##   reporting:  running an action other than registering
##   registering: running the real stuff ; clean up and log data on exit
##   ok: registration completed successfully
PROGRESS="warmup"

## CLI action
ACTION=

## Functions

## log string and/or command to $IBM_RHSM_REG_LOG
##   logthis -E "send string to both console and log"
##   logthis -n "send string to console without newline, and to log (with newline)"
##   logthis -s "send string to log only"
## The command and its result will be logged:
##   logthis cmd arg1 arg2 ...
## Combination of string and following command:
##   logthis -s "send string and output of following command to log" cmd arg1 arg2 ...
## warning: | and " must be escaped
logthis() {
    arg=$1
    if [[ $arg == "-E" || $arg == "-n" ]]; then
        echo $1 "$2"
        arg="-s"
    fi
    if [[ $arg == "-s" ]]; then
        echo "$2" >> $IBM_RHSM_REG_LOG
        shift 2
    fi
    [[ $# -le 0 ]] && return
    echo "---- $*" >> $IBM_RHSM_REG_LOG
    eval $* &>> $IBM_RHSM_REG_LOG
}

## $1: string to print
## $2: color code as defined 0 = green; 1 = red; 2 = yellow
formatted_echo() {
    value=0
    case $2 in
        0) value=32 ;;
        1) value=31 ;;
        2) value=33 ;;
    esac
    echo -e "\r\t\t\t\t\t\t\t\e[${value}m$1\e[0m"
}

## $1: action, one of:
##     CREATE_KEY
##     DELETE_SYSTEMS
##     SHOW_KEY
##     SHOW_SATELLITE
##     LIST_SATELLITES
##     LIST_SYSTEMS
##     SCRIPT_VERSION
## $2: username
## $3: password
## $4: type (could be empty)
## $5: satellite (could be empty)
## $6: system (could be empty)
run_curl() {
    action=$1
    user=$2
    realpass=$3

    if [ "$FTP3DEBUG" == "" ]; then fakepass="PASSWORD" ; else fakepass=$realpass ; fi

    version_data=1
    user_data=1
    type_data=1
    satellite_data=1
    system_data=0
    case "$action" in
        CREATE_KEY)
            command="user.create_activation_key2"
            ;;
        DELETE_SYSTEMS)
            command="user.delete_registered_systems2"
            system_data=1
            ;;
        SHOW_KEY)
            command="user.find_activation_key"
            ;;
        SHOW_SATELLITE)
            command="user.show_satellite"
            user_data=0
            ;;
        LIST_SATELLITES)
            command="user.list_satellites"
            user_data=0
            type_data=0
            satellite_data=0
            ;;
        LIST_SYSTEMS)
            command="user.list_registered_systems2"
            ;;
        SCRIPT_VERSION)
            command="user.registration_script_version"
            user_data=0
            version_data=0
            type_data=0
            satellite_data=0
            ;;
        *)
            return 1
    esac

    if [ $version_data -eq 1 ]; then
        version_param="<param><value>$Version</value></param>"
    else
        version_param=
    fi

    if [ $user_data -eq 1 ]; then
        user_param="<param><value>$user</value></param>"
        realpass_param="<param><value>$realpass</value></param>"
        fakepass_param="<param><value>$fakepass</value></param>"
    else
        user_param=
        realpass_param=
        fakepass_param=
    fi

    if [ $type_data -eq 1 ]; then
        type_param="<param><value>$4</value></param>"
    else
        type_param=
    fi

    if [ $satellite_data -eq 1 ]; then
        satellite_param="<param><value>$5</value></param>"
    else
        satellite_param=
    fi

    if [ $system_data -eq 1 ]; then
        system_param="<param><value>$6</value></param>"
    else
        system_param=
    fi

    cmd="curl -ks $API_URL -H \"Content-Type: text/xml\" -d \"<?xml version='1.0' encoding='UTF-8'?><methodCall><methodName>${command}</methodName> <params> $version_param $user_param $fakepass_param $type_param $satellite_param $system_param </params> </methodCall>\""
    logthis -s "$cmd"
    result=$(curl -ks $API_URL -H "Content-Type: text/xml" -d "<?xml version='1.0' encoding='UTF-8'?><methodCall><methodName>${command}</methodName> <params> $version_param $user_param $realpass_param $type_param $satellite_param $system_param </params> </methodCall>")
    if [[ $? -ne 0 ]]; then
        case "$action" in
            CREATE_KEY)
                echo "An error has occurred while trying to create the activation key."
                ;;
            DELETE_SYSTEMS)
                echo "An error has occurred while trying to delete registered systems."
                ;;
            SHOW_KEY)
                echo "An error has occurred while trying to query the activation key."
                ;;
            SHOW_SATELLITE)
                echo "An error has occurred while trying to get the name of the LTC Redhat Satellite."
                ;;
            LIST_SATELLITES)
                echo "An error has occurred while trying to get the list of active satellites."
                ;;
            LIST_SYSTEMS)
                echo "An error has occurred while trying to get the list of registered systems."
                ;;
            SCRIPT_VERSION)
                echo "An error has occurred while trying to determine the latest registration script version."
                ;;
        esac
        return 1
    fi
    echo "$result" | grep -oPm1 "(?<=<string>)[^<]+"
    return 0
}

## $1: action, one of:
##     CREATE_KEY
##     DELETE_SYSTEMS
##     SHOW_KEY
##     SHOW_SATELLITE
##     LIST_SATELLITES
##     LIST_SYSTEMS
## $2: exit code from curl
## $3: curl result
check_curl_result() {
    action=$1
    curl_rc=$2
    curl_result=$3
    case "$action" in
        CREATE_KEY | DELETE_SYSTEMS | SHOW_KEY | SHOW_SATELLITE | LIST_SATELLITES | LIST_SYSTEMS | SCRIPT_VERSION)
            ;;
        *)
            return
            ;;
    esac
    if [[ $curl_rc -ne 0 ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

$3
Aborting...

EOF
        exit $curl_rc
    elif [[ -z "$curl_result" ]]; then
        formatted_echo "FAIL" 1
        echo
        case "$action" in
            CREATE_KEY | SHOW_KEY)
                cat <<EOF
An error has occurred: No activation key.
There was a problem while querying or creating your activation key.
Please, make sure you are connected to the IBM network and using a valid FTP3 account.
Aborting.
EOF
                ;;
            DELETE_SYSTEMS)
                echo "No registered systems found."
                ;;
            SHOW_SATELLITE)
                echo "Unable to retrieve name of LTC Redhat Satellite."
                ;;
            LIST_SATELLITES)
                echo "No active satellites found."
                ;;
            LIST_SYSTEMS)
                echo "No registered systems found."
                ;;
        esac
        echo
        exit 1
    elif [[ "$curl_result" == "Account not found" || "$curl_result" == "Wrong username or password" ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: $curl_result
Please, make sure you're using the correct FTP3 username and password.
Aborting.

EOF
        exit 1
    elif [[ "$curl_result" == "The account $FTP3USER does not have access to Red Hat content" ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: $curl_result
You may request access on the "My Account" page: https://$FTP3HOST/myaccount/access.php.
Aborting.

EOF
        exit 1
    elif [[ "$3" == "No activation key was found" ]]; then # This could only happen if $1 is DELETE_SYSTEMS or LIST_SYSTEMS
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: No activation key.
Please, make sure you are connected to the IBM network and using a valid FTP3 account.
Aborting.

EOF
        exit 1
    elif [[ "$curl_result" == "Two (or more) activation keys were found" ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: $curl_result
You may open a ticket here: ${SUPPORT_URL}?Tool=FTP3
Please, add this message to the new ticket.
Aborting.

EOF
        exit 1
    elif [[ "$action" == "DELETE_SYSTEMS" && "$curl_result" == "Unable to find this system: "* ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF

An error has occurred: $curl_result
Please, make sure you own the system you're trying to delete and that you're using the correct hostname.
To check which registered systems you own: $0 --list-systems

EOF
         exit 1
    elif [[ "$action" == "DELETE_SYSTEMS" && "$curl_result" == *"KO:"* ]]; then
         if [[ "$curl_result" == *"OK:"* ]]; then
             formatted_echo "WARN" 2
         else
             formatted_echo "FAIL" 1
         fi
    else
         formatted_echo "OK" 0
    fi
}

## print usage
usage() {
    result=1
    [[ $1 != "" ]] && result=$1
    cat <<EOF
IBM Linux Technology Center Redhat Satellite registration script.
Use of this script requires a $FTP3HOST user account.

Usage:
  $0 [OPTIONS] ACTION

OPTIONS:
  --force
      Don't ask for confirmation before re-registering a system that is already
      registered.

  --ftp3 <hostname>
      Use a specific host name to refer to the FTP3 server.  This should only be
      used for testing, debugging, or as directed by LTC support personnel.
      The FTP3HOST environment variable will be queried if this value is not
      specified, otherwise the default value of ftp3.linux.ibm.com will be used.

  --satellite <hostname>
      Use a specific Redhat Satellite host for all subsequent operations.  This
      should only be used for testing, debugging, or as directed by LTC support
      personnel.

  --type <satellite-type>
      Only consider Redhat Satellites of a specific type.  This should only be
      used for testing, debugging, or as directed by LTC support personnel.  The
      default type is "production".  A pseudo value of "all" is allowed.

  --user <ftp3-ID>
      The name of your FTP3 user ID.  The FTP3USER environment variable will be
      queried if this value is not specified, otherwise the program will prompt
      for this value.

  --password <ftp3-password>
      The password of your FTP3 user ID.  The FTP3PASS environment variable will
      be queried if this value is not specified, otherwise the program will
      prompt for this value.

ACTIONs:
  --delete-systems [<system>]
      Delete all the registered systems you own or just the given one.  Must be
      specified as the last parameter if an argument is given.

  --list-satellites
      Print the names of all defined LTC Rehat Satellites.

  --list-systems
      Print the registered systems assigned to your activation key.

  --register
      Register this system with the LTC Redhat Satellite.

  --show-key
      Display any existing activation key associated with your FTP3 ID.

  --show-satellite
      Query and display the name of the production LTC Redhat Satellite.

  --version
      Display program version number and exit.

  Actions are mutually exclusive.  There is no default action.

EOF
    exit $result
}

KATELLO_CERT_RPM="uninitialized"
## this is called on exit
clean_up() {
    result=$?
    [[ "$PROGRESS" == "parsing" \
    || "$PROGRESS" == "initializing" \
    || "$PROGRESS" == "reporting" ]] && exit $result
    [[ "$PROGRESS" == "ok" ]] && exit 0

    if [[ "$PROGRESS" == "registering" ]]; then
        logthis -s "-- Cleaning on exit ----------------------------------------------------"
        if rpm --quiet -q $KATELLO_CERT_RPM; then
            echo "Cleaning up..."
            logthis -s "$KATELLO_CERT_RPM is installed, removing."
            rpm --quiet -e $KATELLO_CERT_RPM
        fi
        logthis subscription-manager facts
        logthis tail -30 /var/log/rhsm/rhsm.log
    fi
    exit 1
}

## clean up proper if something goes bad
trap clean_up EXIT HUP INT QUIT TERM;

get_argument() {
    variable=$1
    parameter=$2
    argument=$3
    if [[ $# -eq 3 ]]; then
        eval "$variable=$argument"
    else
        echo "The $parameter option requires an argument."
        echo "Run \"$0 --help\" for assistance."
        exit 2
    fi
    return 0
}

## check CLI parameters
PROGRESS="parsing"
action_count=0
SATELLITE=""
TYPE="production"
DELETE_SYSTEMS=
while [[ $# -gt 0 ]]; do
    if [[ "$1" == -* ]]; then
        parameter="$1"
        case "$parameter" in
            --force)
                FTP3FORCE=y
                ;;
            --ftp3)
                shift
                get_argument FTP3HOST $parameter $1
                ;;
            --user)
                shift
                get_argument FTP3USER $parameter $1
                ;;
            --password)
                shift
                get_argument FTP3PASS $parameter $1
                ;;
            --list-satellites)
                ACTION="LIST_SATELLITES"
                ((action_count++))
               ;;
            --list-systems)
                ACTION="LIST_SYSTEMS"
                ((action_count++))
               ;;
            --satellite)
                shift
                get_argument SATELLITE $parameter $1
                ;;
            --type)
                shift
                # Because the --type argument is allowed to be the empty string,
                # we must quote all instances of it.
                if [[ $# -eq 0 ]]; then
                    get_argument TYPE $parameter $1
                else
                    get_argument TYPE $parameter "$1"
                fi
                ;;
            --register)
                ACTION="REGISTER"
                ((action_count++))
               ;;
            --show-key)
                ACTION="SHOW_KEY"
                ((action_count++))
               ;;
            --show-satellite)
                ACTION="SHOW_SATELLITE"
                ((action_count++))
               ;;
            --delete-systems)
                ACTION="DELETE_SYSTEMS"
                ((action_count++))
                shift
                # Optional argument
                if [[ -n "$1" ]]; then
                    DELETE_SYSTEMS="$1"
                fi
                ;;
            --help)
                usage 0
                ;;
            --version)
                echo "version $Version"
                exit 0
                ;;
            *)
                echo "Invalid parameter: $1"
                echo "Run \"$0 --help\" for assistance."
                exit 2
                ;;
        esac
        shift
    else
        break
    fi
done
if [ $action_count -eq 0 ]; then
    echo "No action was specified."
    echo "Run \"$0 --help\" for assistance."
    exit 2
fi
if [ $action_count -gt 1 ]; then
    echo "Action parameters are mutually exclusive."
    echo "Run \"$0 --help\" for assistance."
    exit 2
fi
[[ $# -gt 0 ]] && usage

if [[ "$ACTION" == "REGISTER" || "$ACTION" == "DELETE_SYSTEMS" ]]; then
    ## must be root to register
    if [[ $(whoami) != "root" ]] ; then
        echo "You must be root to run registration operations. Goodbye."
        echo
        exit 1
    fi
fi

## The API through which we talk to FTP3
API_URL="https://$FTP3HOST/rpc/index.php"

## Force path with /usr/sbin for subscription-manager need
export PATH=/usr/sbin:$PATH

## initialize the log file
rm -f $IBM_RHSM_REG_LOG
logthis -s "-- $IBM_RHSM_REG_LOG --------------------------------------------------------"
logthis -s "On $(date)"
logthis -s "Script version: $Version"
logthis -s "System: $(uname -a)"
logthis lscpu
logthis cat /etc/redhat-release

PROGRESS="initializing"

logthis -s "-- Query latest script version -----------------------------------------"
echo -n "Querying script version..."
SCRIPT_VERSION=$(run_curl SCRIPT_VERSION)
RET=$?
logthis -s "return code: $RET"
logthis -s "result: $SCRIPT_VERSION"
check_curl_result SCRIPT_VERSION $RET "$SCRIPT_VERSION"
latest=$(printf "%03d%03d%03d" ${SCRIPT_VERSION//./ })
this=$(printf "%03d%03d%03d\n" ${Version//./ })
if [ "$latest" \> "$this" ]; then
    if [ -z "$FTP3USER" ]; then
        user="<ftp3-id>"
    else
        user=$FTP3USER
    fi
    logthis -E "Obsolete script version $Version; please download version $SCRIPT_VERSION."
    logthis -E "The latest version of the script can be downloaded with the following command:"
    logthis -E "wget --user $user --ask-password -O ibm-rhsm.sh ftp://$FTP3HOST/redhat/ibm-rhsm.sh"
    exit 1
fi

# See if the version of this script was overridden (for debugging purposes only!):
if [ -v FTP3VER ]; then Version=$FTP3VER ; fi

if [[ "$ACTION" == "LIST_SATELLITES" ]]; then
    echo -n "Searching for defined satellites... "
fi

logthis -s "-- Query defined satellites --------------------------------------------"
DEFINED_SATELLITES=$(run_curl LIST_SATELLITES)
RET=$?
logthis -s "return code: $RET"
logthis -s "result: $DEFINED_SATELLITES"

S=""
ACTIVE_SATELLITES=""
# Each satellitte entry has the form:
#     host(name1=value1:name2=value2:name3=value3)
for defined_satellite in $DEFINED_SATELLITES; do
    # Isolate the host name
    host=${defined_satellite%(*}
    # Remove leading host name and open paren
    attributes=${defined_satellite#*(}
    # Remove the closing paren
    attributes=${attributes%)}
    # Convert colons to spaces
    attributes=${attributes//:/ }
    for attribute in $attributes ; do
        name=${attribute%=*}
        value=${attribute#*=}
        if [[ "$name" == "state" && ("$value" == "active" || "$value" == "obsolete") ]] ; then
            ACTIVE_SATELLITES="${ACTIVE_SATELLITES}${S}${host}"
            S=" "
        fi
    done
done
logthis -s "Active satellites: $ACTIVE_SATELLITES"

if [[ "$ACTION" == "LIST_SATELLITES" ]]; then
    logthis -s "-- List satellites -----------------------------------------------------"
    check_curl_result LIST_SATELLITES $RET "$DEFINED_SATELLITES"
    echo
    echo $DEFINED_SATELLITES | tr ' ' '\n' | sed "s/^/    /"
    echo
    for defined_satellite in $DEFINED_SATELLITES; do
        logthis -s "    $defined_satellite"
    done
    exit 0
fi

# Get the name of the production LTC Redhat Satellite
logthis -s "-- Query satellite -----------------------------------------------------"
RESULT=$(run_curl SHOW_SATELLITE "" "" "$TYPE" "$SATELLITE")
if [[ "$RESULT" == SCRIPT_OBSOLETE* ]]; then
    logthis -s "$RESULT"
    echo $RESULT
    exit 1
fi
if [[ "$RESULT" == "" ]]; then
    logthis -s "No eligible satellites found."
    echo "No eligible satellites found."
    exit 1
fi
LTC_SATELLITE=$RESULT
logthis -s "LTC Redhat Satellite: $LTC_SATELLITE"

# Default to current production satellite
[[ "$SATELLITE" == "" ]] && SATELLITE=$LTC_SATELLITE

if [ $action_count -gt 0 ]; then
  PROGRESS="reporting"
fi

if [[ "$ACTION" == "SHOW_SATELLITE" ]]; then
    logthis -s "-- Show satellite ------------------------------------------------------"
    logthis -s "result: $LTC_SATELLITE"
    echo $LTC_SATELLITE
    exit 0
fi

## -----------------------------------------------------------------------------
## All actions after this point require authentication
## -----------------------------------------------------------------------------

## get the userid
if [[ -z "$FTP3USER" ]] ; then
    echo -n "User ID: "
    read FTP3USER

    if [[ -z "$FTP3USER" ]] ; then
        cat <<EOF

Missing userid.
Either set the environment variable FTP3USER to your user id
or enter a user id when prompted.
Goodbye.

EOF
        exit 1
    fi
fi

## get the password
if [[ -z "$FTP3PASS" ]] ; then
    echo -n "Password for $FTP3USER: "
    stty -echo
    read -r FTP3PASS
    stty echo
    echo

    if [[ -z "$FTP3PASS" ]] ; then
        cat <<EOF

Missing password.
Either set the environment variable FTP3PASS to your user password
or enter a password when prompted.
Goodbye.

EOF
        exit 1
    fi
fi

## Encode the username for use in URLs
FTP3USERENC=$(echo $FTP3USER | sed s/@/%40/g)

## Encode user password for use in URLs
FTP3PASSENC=$(echo $FTP3PASS | od -tx1 -An | tr -d '\n' | sed 's/ /%/g')


if [[ "$ACTION" == "LIST_SYSTEMS" ]]; then
    echo -n "Searching for registered systems... "

    RESULT=$(run_curl LIST_SYSTEMS $FTP3USERENC $FTP3PASSENC "$TYPE" $SATELLITE)
    RET=$?
    logthis -s "-- List systems --------------------------------------------------------"
    logthis -s "return code: $RET"
    logthis -s "result: $RESULT"
    check_curl_result LIST_SYSTEMS $RET "$RESULT"
    echo
    echo $RESULT | tr ' ' '\n' | sort -h | sed "s/^/    /"
    echo
    exit 0
fi

if [[ "$ACTION" == "SHOW_KEY" ]]; then
    echo -n "Searching for an existing activation key... "

    RESULT=$(run_curl SHOW_KEY $FTP3USERENC $FTP3PASSENC "$TYPE" $SATELLITE)
    RET=$?
    logthis -s "-- Show key ------------------------------------------------------------"
    logthis -s "return code: $RET"
    logthis -s "result: $RESULT"
    check_curl_result SHOW_KEY $RET "$RESULT"
    echo
    echo $RESULT | tr ' ' '\n' | sort -h | sed "s/^/    /"
    echo
    exit 0
fi

if [[ "$ACTION" == "DELETE_SYSTEMS" ]]; then
    echo -n "Deleting registered systems... "

    RESULT=$(run_curl DELETE_SYSTEMS $FTP3USERENC $FTP3PASSENC "$TYPE" $SATELLITE $DELETE_SYSTEMS)
    RET=$?
    logthis -s "-- Delete systems ------------------------------------------------------"
    logthis -s "return code: $RET"
    logthis -s "result: $RESULT"
    check_curl_result DELETE_SYSTEMS $RET "$RESULT"
    echo $RESULT | tr ' ' '\n' | sed -e "s/^/    /" -e "s/    OK:/\nDeleted systems:/" -e "s/    KO:/\nUnable to delete systems:/"
    echo
    [[ "$RESULT" == *"KO:"* ]] && exit 1
    exit 0
fi

if [[ "$ACTION" != "REGISTER" ]]; then
    logthis -E "Indeterminate action: $ACTION"
    exit 1
fi

if [[ ! -x /usr/sbin/subscription-manager ]]; then
    logthis -s "-- subscription-manager ------------------------------------------------"
    logthis -s "/usr/sbin/subscription-manager is missing"
    logthis rpm -q subscription-manager
    cat <<EOF
The subscription-manager command can't be found.
Check with your administrator to install this package: subscription-manager

EOF
    exit 1
fi

logthis -E "Starting the registration process..."

logthis -n "* Performing initial checks... "
logthis -s "-- Checking hostname ---------------------------------------------------"
HOSTNAME=$(hostname 2>/dev/null)
if [[ $? -ne 0 ]]; then
    formatted_echo "FAIL" 1
    cat <<EOF
Failed to find system hostname.
Please run the command "hostname" to set and check the system hostname.

EOF
    logthis -s "Error while calling: hostname"
    exit 1
fi
# get long hostname if -f is available
tmp=$(hostname -f 2>/dev/null)
[[ $? -eq 0 ]] && HOSTNAME=$tmp
logthis -s "Hostname: $HOSTNAME"
formatted_echo "OK" 0

PROGRESS="registering"
CLEAN_ALL=0

logthis -n "* Querying the server certificate... "
CERT_URL="http://$LTC_SATELLITE/pub/katello-ca-consumer-latest.noarch.rpm"
cmd="curl -o /dev/null --silent -Iw %{http_code} ${CERT_URL}"
logthis -s "$cmd"
result=$($cmd)
retcode=$?
if [[ $retcode -ne 0 ]]; then
    formatted_echo "FAIL" 1
    logthis -E "Error $retcode querying server certificate"
    exit 1
fi
if [[ "$result" != "200" ]]; then
    formatted_echo "FAIL" 1
    logthis -E "Unexpected response $result querying server certificate"
    exit 1
fi
formatted_echo "OK" 0

## is the system already registered?
logthis -s "-- Checking if the system is already registered ------------------------"
for ACTIVE_SATELLITE in $ACTIVE_SATELLITES ; do
    logthis -n "* Checking ${ACTIVE_SATELLITE}..."
    RESULT=$(run_curl LIST_SYSTEMS $FTP3USERENC $FTP3PASSENC "$TYPE" $ACTIVE_SATELLITE)
    logthis -s "registered systems: $RESULT"
    if grep -qw $HOSTNAME <<< "$RESULT"; then
        formatted_echo "WARN" 2
        logthis -E "This system is already registered with $ACTIVE_SATELLITE."
        PROCEED="y"
        if [[ "${FTP3FORCE,,}" != "y" ]]; then
            logthis -n "Would you like to proceed? (y/n): "
            read PROCEED
        fi
        if [[ "${PROCEED,,}" != "y" ]]; then
            logthis -E "Aborting..."
            echo
            exit 1
        fi
        FTP3FORCE="y"
        CLEAN_ALL=1
        # Delete the current system from the satellite
        logthis -n "* Unregistering from $ACTIVE_SATELLITE..."
        logthis -s "Unregistering $HOSTNAME from $ACTIVE_SATELLITE"
        RESULT=$(run_curl DELETE_SYSTEMS $FTP3USERENC $FTP3PASSENC "$TYPE" $ACTIVE_SATELLITE $HOSTNAME)
        RET=$?
        logthis -s "return code: $RET"
        logthis -s "result: $RESULT"
        check_curl_result DELETE_SYSTEMS $RET "$RESULT"
    else
        formatted_echo "OK" 0
        logthis -s "current system isn't registered with $ACTIVE_SATELLITE"
    fi
done
if [ $CLEAN_ALL -ne 0 ]; then
    # Clean subscription data as status not always relevant
    logthis -n "* Cleaning registration data... "
    logthis -s "-- Cleaning registration data ------------------------------------------"
    logthis subscription-manager unregister
    logthis subscription-manager unsubscribe --all
    logthis subscription-manager clean
    logthis yum clean all
    formatted_echo "OK" 0
fi

logthis -n "* Checking the current system... "
logthis -s "-- Checking release, version and arch ----------------------------------"
## get the version and release, most likely only works on RHEL
VERREL=$(rpm -qf --qf "%{NAME}-%{VERSION}" /etc/redhat-release)
if [[ $? -ne 0 ]] ; then
    formatted_echo "FAIL" 1
    cat <<EOF
Failed to find system version and release with the
command "rpm -q redhat-release". Is this system
running Red Hat Enterprise Linux?

EOF
    logthis -s "Error while calling: rpm -qf --qf \"%{NAME}-%{VERSION}\" /etc/redhat-release"
    logthis -s "Result: $VERREL"
    exit 1
fi

# Leading word is almost certainly "redhat" but we use a wildcard just in case.
major_minor=${VERREL#*-release-*}
# Older releases might have an embedded "server-" or "workstation-"
major_minor=${major_minor#*-}
major=${major_minor%.*}
minor=${major_minor#*.}
if [[ $major == $major_minor && $minor == $major_minor ]]; then
  major=${major_minor:0:1}
  minor=${major_minor:1}
fi

#  **FIRST DETERMINE IF THIS IS VERSION 8 OR GREATER.  DIFFERENT SPLIT REQUIRED**
## FIRST split something like "redhat-release-8.0" into "8" and "release"
RELEASE=$major
if [[ $RELEASE -ge 8 ]] ; then
#  VERSION=$(echo $VERREL | cut -f2 -d"-")
  VERSION="server"
else
   ## split something like "redhat-release-server-7.1" into "7" and "server"
   RELEASE=$(echo $VERREL | cut -f4 -d"-" | cut -b1)
   VERSION=$(echo $VERREL | cut -f3 -d"-")
fi

VALID=

## verify support for this release and this version
grep -qvw $RELEASE <<< ${SUPPORTED_RELEASES[@]} && VALID=no && logthis -s "Unknown or unsupported release: $RELEASE"
grep -qvw $VERSION <<< ${SUPPORTED_VERSIONS[@]} && VALID=no && logthis -s "Unknown or unsupported version: $VERSION"
if [[ -n "$VALID" ]] ; then
    formatted_echo "FAIL" 1
    cat <<EOF
Unknown or unsupported system version and release: $VERREL
This could be reported at: $SUPPORT_URL
Please do not forget to add the $IBM_RHSM_REG_LOG file to the request.

EOF
    exit 1
fi

## get the system arch
ARCH=$(uname -m)

## verify support for this arch
grep -qvw $ARCH <<< ${SUPPORTED_ARCHS[@]} && VALID=no && logthis -s "Unknown or unsupported arch: $ARCH"
[[ "$VERSION" == "client" && "$ARCH" != "x86_64" ]] && VALID=no && logthis -s "Unsupported combo version+arch: $VERSION+$ARCH"
if [[ -n "$VALID" ]] ; then
    formatted_echo "FAIL" 1
    cat <<EOF
Unsupported system architecture: $ARCH
This could be reported at: $SUPPORT_URL
Please do not forget to add the $IBM_RHSM_REG_LOG file to the request.

EOF
    exit 1
fi

## set LABEL
case $ARCH in
    x86_64 )
        if [[ $RELEASE -ge 8 ]] ; then
          LABEL="for-x86_64"
        else
          LABEL="$VERSION"
        fi
        ;;
    ppc64le )
        if [[ $(subscription-manager facts | grep lscpu.model_name | cut -f2 -d' '| cut -f1 -d',') == "POWER9" ]] ; then
            LABEL="for-power-9"
            if [[ $RELEASE -ge 8 ]] ; then
               LABEL="for-ppc64le"
            fi
        elif [[ $RELEASE -ge 8 ]] ; then
            LABEL="for-ppc64le"
        else
            LABEL="for-power-le"
        fi
        ;;
    ppc64 )
        LABEL="for-power"
        if [[ $RELEASE -ge 8 ]] ; then
           LABEL="for-ppc64"
        fi
               ;;
    s390x )
        LABEL="for-system-z"
        if [[ $RELEASE -ge 8 ]] ; then
           LABEL="for-s390x"
        fi
        ;;
esac

formatted_echo "OK" 0
logthis -s "Detected a RHEL $RELEASE $VERSION on $ARCH, $LABEL"

## system is registered to the old RHN Satellite?
logthis -s "-- Checking the system is registered to the old RHN --------------------"
if rpm --quiet -q rhn-org-trusted-ssl-cert; then
    echo "This system is registered to the old RHN Satellite." | tee -a $IBM_RHSM_REG_LOG
    echo -n "Would like to proceed and remove current associations? (y/n): "
    read PROCEED

    if [[ "${PROCEED,,}" != "y" ]]; then
        echo "Aborting..."
        echo
        exit 1
    fi
    logthis yum remove rhn-org-trusted-ssl-cert -y
else
    logthis -s "No"
fi

## Force disabling of rhn plugin
if [[ -f /etc/yum/pluginconf.d/rhnplugin.conf ]]; then
    sed -i 's/enabled\ =\ 1/enabled\ =\ 0/g' /etc/yum/pluginconf.d/rhnplugin.conf
fi

logthis -n "* Checking the server certificate... "
logthis -s "-- Checking the certificate --------------------------------------------"
KATELLO_CERT_RPM="katello-ca-consumer-$LTC_SATELLITE"
logthis -s "Consumer certificate RPM name: $KATELLO_CERT_RPM"
if ! rpm --quiet -q $KATELLO_CERT_RPM; then
    formatted_echo "Not Installed" 2
    logthis -s "The server certificate is not installed."

    rpms=$(rpm -qa | grep katello-ca)
    if [ "$rpms" != "" ]; then
        logthis -s "* Removing traces of previous certificates."
        logthis rpm -e $rpms
        if [[ $? -eq 0 ]]; then
            rm -fr /etc/pki/consumer/*
        fi
    fi

    logthis -n "* Installing server certificate... "
    logthis rpm -Uv $CERT_URL
    RET=$?
    logthis subscription-manager config
    if [[ $RET -ne 0 ]]; then
        formatted_echo "FAIL" 1
        cat <<EOF
An error has occurred while trying to install the server certificate.
This could be reported at: $SUPPORT_URL
Please do not forget to add the $IBM_RHSM_REG_LOG file to the request.
Aborting...

EOF
        exit 1
    else
        formatted_echo "OK" 0
    fi
else
    formatted_echo "OK" 0
    logthis -s "Server certificate is already installed."
fi

## Get activation key
## in case an existing key is not found, a new one will be created.
logthis -n "* Searching for an activation key... "
logthis -s "-- Activation key ------------------------------------------------------"
ACTIVATION_KEY=$(run_curl CREATE_KEY $FTP3USERENC $FTP3PASSENC "$TYPE" $SATELLITE)
RET=$?
logthis -s "return code: $RET"
logthis -s "activation key (or error message): $ACTIVATION_KEY"
logthis -s "(You may copy this activation key for future use)"
check_curl_result CREATE_KEY $RET "$ACTIVATION_KEY"

## system registration
logthis -n "* Registering the system... "
logthis -s "-- Registering the system ----------------------------------------------"
REGSTATUS=$(subscription-manager register --org Default_Organization --activationkey="$ACTIVATION_KEY" --force 2>&1)
if [[ $(grep -c "The system has been registered" <<< "$REGSTATUS") -ne 1 ]]; then
    formatted_echo "FAIL" 1
    logthis -s "Registration failed!"
    logthis -s "Registration error: $REGSTATUS"
    cat <<EOF
An error has occurred while trying to register the system.
You may try to register it later using the following command:
subscription-manager register --org Default_Organization --activationkey="$ACTIVATION_KEY" --force
This could be reported at: $SUPPORT_URL
Please do not forget to add the $IBM_RHSM_REG_LOG file to the request.

EOF
    exit 1
else
    logthis -s "System successfully registered"
    formatted_echo "OK" 0
fi

logthis subscription-manager facts \| egrep "\"distribution|net\""

## Disable all repositories
logthis -n "* Disabling all repositories... "
logthis -s "-- Disabling repositories ----------------------------------------------"
logthis subscription-manager repos --disable="\"*\""
if [[ $? -ne 0 ]]; then
    formatted_echo "FAIL" 1
    logthis subscription-manager repos --list \| grep "\"Repo ID:\""
else
    formatted_echo "OK" 0
fi

## Enable RHEL repositories
logthis -E "* Enabling RHEL $RELEASE repositories"
logthis -s "-- list of current repos available --"
logthis subscription-manager repos --list
logthis -s "-- Enabling repositories -----------------------------------------------"
[[ $LABEL == "for-power-9" ]] && extra="" || extra="supplementary"
[[ $(subscription-manager repos --list |grep rhel-$RELEASE-$LABEL-extras-rpms) ]] && extra="$extra extras"

if [[ $RELEASE -ge 8 ]] ; then
   for REPO in appstream supplementary baseos; do
       logthis -n "    ${REPO^}... "
       logthis subscription-manager repos --enable=rhel-$RELEASE-$LABEL-$REPO-rpms
       [[ $? -eq 0 ]] && formatted_echo "OK" 0 || formatted_echo "FAIL" 1
   done
else
   for REPO in common optional $extra; do
       logthis -n "    ${REPO^}... "
       [[ $REPO != "common" ]] && str="$REPO-" || str=""
       logthis subscription-manager repos --enable=rhel-$RELEASE-$LABEL-${str}rpms
       [[ $? -eq 0 ]] && formatted_echo "OK" 0 || formatted_echo "FAIL" 1
   done
fi

echo
echo "Registration completed!" | tee -a $IBM_RHSM_REG_LOG

echo "If you need to add more repositories like extras you can issue commands like:" | tee -a $IBM_RHSM_REG_LOG
echo "subscription-manager repos --enable=rhel-$RELEASE-$LABEL-extras-rpms" | tee -a $IBM_RHSM_REG_LOG

PROGRESS="ok"

exit 0
