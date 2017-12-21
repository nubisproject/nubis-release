#!/bin/bash

# Make sure we capture failures from pipe commands
set -o pipefail

# Required to trim characters
shopt -s extglob

# Set up our path for later use
SCRIPT_PATH="$PWD"

# This function sets up logging, debugging and terminal output on std error
# Level 0 is always logged
# Level 1 through 3 are set on the command line
# The level is escalating, so everything in level 1 is shown in level 2 and 3 etc...
# Duplicate output on command line also here
#
# Usage:
# Level 0 'log_term 0 "message" [echo options]'
# Level 1 'log_term 1 "message" [echo options]'
# Level 2 'log_term 2 "message" [echo options]'
# Level 3 'log_term 3 "message" [echo options]'
LOGGER=/usr/bin/logger
if [ ! -x $LOGGER ]; then
    echo "ERROR: 'logger' binary not found - Aborting"
    echo "ERROR: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    exit 2
fi
log_term () {
    if [ "${VERBOSE_INTERNAL:-0}" -ge 0 ] && [ "${1}" == 0 ]; then
        $LOGGER -p local7.warning -t nubis-release "$2"
        if [ "${VERBOSE_SILENT:-0}" != 1 ]; then
            echo "${3}" "${2}" 1>&2
        fi
    fi
    if [ "${VERBOSE_INTERNAL:-0}" -gt 0 ] && [ "${1}" == 1 ]; then
        $LOGGER -p local7.warning -t nubis-release "$2"
        if [ "${VERBOSE_TERMINAL:-0}" == 1 ] && [ "${VERBOSE_SILENT:-0}" != 1 ]; then
            echo "${3}" "${2}" 1>&2
        fi
    fi
    if [ "${VERBOSE_INTERNAL:-0}" -gt 1 ] && [ "${1}" == 2 ]; then
        $LOGGER -p local7.warning -t nubis-release "$2"
        if [ "${VERBOSE_TERMINAL:-0}" == 1 ] && [ "${VERBOSE_SILENT:-0}" != 1 ]; then
            echo "${3}" "${2}" 1>&2
        fi
    fi
    if [ "${VERBOSE_INTERNAL:-0}" -gt 2 ] && [ "${1}" == 3 ]; then
        $LOGGER -p local7.warning -t nubis-release "$2"
        if [ "${VERBOSE_TERMINAL:-0}" == 1 ] && [ "${VERBOSE_SILENT:-0}" != 1 ]; then
            echo "${3}" "${2}" 1>&2
        fi
    fi
}

# Source the local variables file if it exists
if [ -f ./variables_local.sh ]; then
    # https://github.com/koalaman/shellcheck/wiki/SC1091
    # shellcheck disable=SC1091
    source ./variables_local.sh
else
    log_term 0 "You need to set up your 'variables_local.sh' file"
    log_term 0 "Try copying the 'variables_local.sh-dist' file and editing it"
    exit 1
fi

# Set up the main.sh command
setup_main_command () {
    if [ "${USE_DOCKER:-'NULL'}" == NULL ]; then
        declare -a MAIN_EXEC=( './main.sh' '--non-interactive' "${VERBOSE}" '--oath-token' "${GITHUB_OATH_TOKEN}" )
    else
        declare -a DOCKER_COMMAND=( 'docker' 'run' '-it' '-v' '/var/run/docker.sock:/var/run/docker.sock' 'nubis-release' )
        declare -a MAIN_EXEC=( "${DOCKER_COMMAND[@]}" '--non-interactive' "${VERBOSE}" '--oath-token' "${GITHUB_OATH_TOKEN}" )
    fi
    AWS_VAULT_EXEC_MAIN=( "${AWS_VAULT_EXEC[@]}" "${MAIN_EXEC[@]}" )
}

test_for_parallel () {
    if ! parallel --version > /dev/null 2>&1; then
        log_term 0 "ERROR: parallel must be installed and on your path!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

upload_lambda_functions () {
    local -r _RELEASE="${1}"
    local -r _S3_BUCKET="${2}"
    local -r _SKIP_RELEASE="${3}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "${MAIN_EXEC[@]}" help
        exit 1
    fi
    cd "${SCRIPT_PATH}/bin" || exit 1
    # Bundle, Upload and Release all lambda functions
    local _COUNT=1
    # https://github.com/koalaman/shellcheck/wiki/SC2153
    # shellcheck disable=SC2153
    for LAMBDA_FUNCTION in "${LAMBDA_FUNCTIONS[@]}"; do
        if [ "${_SKIP_RELEASE:-NULL}" == 'NULL' ]; then
            log_term 1 "\nSetup releasing repository \"${LAMBDA_FUNCTION}\" at \"${_RELEASE}\". (${_COUNT} of ${#LAMBDA_FUNCTIONS[*]})" -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            "${MAIN_EXEC[@]}" setup-release "${LAMBDA_FUNCTION}" "${_RELEASE}" || exit 1

            log_term 2 "\nUploading Lambda function: \"${LAMBDA_FUNCTION}\"" -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            "${AWS_VAULT_EXEC_MAIN[@]}" upload-assets --skip-clone --multi-region --bucket "${_S3_BUCKET}" --release "${_RELEASE}" push-lambda "${LAMBDA_FUNCTION}" || exit 1

            log_term 1 "\nComplete releasing repository \"${LAMBDA_FUNCTION}\" at \"${_RELEASE}\". (${_COUNT} of ${#LAMBDA_FUNCTIONS[*]})" -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            "${MAIN_EXEC[@]}" complete-release "${LAMBDA_FUNCTION}" "${_RELEASE}" || exit 1
        else
            log_term 2 "\nUploading Lambda function: \"${LAMBDA_FUNCTION}\"" -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            "${AWS_VAULT_EXEC_MAIN[@]}" upload-assets --multi-region --bucket "${_S3_BUCKET}" --release "${_RELEASE}" push-lambda "${LAMBDA_FUNCTION}" || exit 1

        fi
        let _COUNT=${_COUNT}+1
    done
    unset LAMBDA_FUNCTION
}

# Release all non-infrastructure repositories
release_no_build_repositories () {
    local -r _RELEASE="${1}"
    local -r _SKIP_RELEASE="${2}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "${MAIN_EXEC[@]}" help
        exit 1
    fi
    cd "${SCRIPT_PATH}/bin" || exit 1

    local -r _RELEASE_REGEX="^(v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))-dev$"
    if [ "${_SKIP_RELEASE:-NULL}" == 'NULL' ]; then
        local _COUNT=1
        for REPOSITORY in "${RELEASE_REPOSITORIES[@]}"; do
            log_term 1 "\nReleasing repository \"${REPOSITORY}\" at \"${_RELEASE}\". (${_COUNT} of ${#RELEASE_REPOSITORIES[*]})" -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            if ! "${MAIN_EXEC[@]}" release "${REPOSITORY}" "${RELEASE}" ; then
                log_term 0 "\n******** Release of repository\"${REPOSITORY}\" Failed! ********" -e
                log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            fi
            let _COUNT=${_COUNT}+1
        done
        unset REPOSITORY
    # This is a special edit to update the pinned version number to 'develop' for terraform modules in nubis-deploy
    #+ We need to do this only if we are building a vX.X.X-dev release (See _RELEASE_REGEX above)
    elif [[ "${_RELEASE}" =~ ${_RELEASE_REGEX} ]]; then
        # https://github.com/koalaman/shellcheck/wiki/SC1091
        # shellcheck disable=SC1091
        source edit.sh
        "${MAIN_EXEC[@]}" edit --release "${_RELEASE}" --git-sha 'develop' nubis-deploy
    fi
}

# Build and release nubis-base
release_nubis_base_repository () {
    test_for_parallel
    local -r _RELEASE="${1}"
    local -r _SKIP_RELEASE="${2}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "${MAIN_EXEC[@]}" help
        exit 1
    fi
    cd "${SCRIPT_PATH}/bin" || exit 1
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        COMMAND='build-and-release'
    else
        COMMAND='build'
    fi
    log_term 1 "\nBuilding and Releasing \"nubis-base\" at \"${_RELEASE}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    parallel --no-notice --output-as-files --results logs "${AWS_VAULT_EXEC_MAIN[@]}" "${COMMAND}" '{1}' "${_RELEASE}" ::: 'nubis-base'
    # https://github.com/koalaman/shellcheck/wiki/SC2181
    # shellcheck disable=SC2181
    if [ $? != '0' ]; then
        log_term 0 "Build for 'nubis-base' failed. Unable to continue."
        log_term 0 "Aborting....."
        exit 1
    fi
}

# Build and release all infrastructure components using the latest nubis-base
release_build_repositories () {
    test_for_parallel
    local -r _RELEASE="${1}"
    local -r _SKIP_RELEASE="${2}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "${MAIN_EXEC[@]}" help
        exit 1
    fi
    cd "${SCRIPT_PATH}/bin" || exit 1
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        COMMAND='build-and-release'
    else
        COMMAND='build'
    fi
    log_term 1 "\nBuilding and Releasing \"${#BUILD_REPOSITORIES[*]}\" repositories at \"${_RELEASE}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    parallel --no-notice --output-as-files --results logs --progress --jobs "${#BUILD_REPOSITORIES[@]}" "${AWS_VAULT_EXEC_MAIN[@]}" "${COMMAND}" '{1}' "${_RELEASE}" ::: "${BUILD_REPOSITORIES[@]}"; _RV=$?
    if [ "${_RV:-0}" != '0' ]; then
        log_term 0 "\n!!!!! ${_RV} builds failed failed. Inspect output logs. !!!!!" -e
    fi; unset _RV
}

build_and_release_all () {
    local -r _RELEASE="${1}"
    local _SKIP_RELEASE="${2}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "${MAIN_EXEC[@]}" help
        exit 1
    fi
    if [ "${_SKIP_RELEASE:-NULL}" == 'NULL' ]; then
        _SKIP_RELEASE='NULL'
    fi

    # Upload lambda functions
    log_term 1 "\nUploading Lambda functions" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#    upload_lambda_functions "${_RELEASE}" "${S3_BUCKET}" "${_SKIP_RELEASE}"

    # Release repositories with no AMI build requirement
    log_term 1 "\nReleasing repositories with no AMI build requirement" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    release_no_build_repositories "${_RELEASE}" "${_SKIP_RELEASE}"

    # Expire any sessions for the build account and generate a new session
    # This should enable us to complete the builds before the session expires
    _VAULT_ACCOUNT=$(echo "${PROFILE}" | cut -d'-' -f 1,2)
    aws-vault rm -s "${_VAULT_ACCOUNT}"
    "${AWS_VAULT_EXEC[@]}" aws ec2 describe-regions > /dev/null || exit 1
    unset _VAULT_PROFILE _VAULT_ACCOUNT

    log_term 0 '\nIf you care to monitor the build progress:' -e
    log_term 0 'tail -f logs/1/*/stdout logs/1/*/stderr'

    # Build and release nubis-base
    # All other infrastructure builds are built from nubis-base, we need to build it first
    log_term 1 "\nBuilding nubis-base" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    release_nubis_base_repository "${_RELEASE}" "${_SKIP_RELEASE}"

    # AWS is slow to propogate the AMI ID of nubis-base, lets sleep for a while
    #+ TODO: Search for the AMI ID and continue once we see it
    sleep 60

    # Build and release all infrastructure components using the latest nubis-base
    log_term 1 "\nBuilding all nubis-base dependant repositories" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    release_build_repositories "${_RELEASE}" "${_SKIP_RELEASE}"
}

create-milestones () {
    local -r _RELEASE="${1}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "${MAIN_EXEC[@]}" help
        exit 1
    fi
    declare -a MILESTONE_REPOSITORY_ARRAY=( 'nubis-base' "${RELEASE_REPOSITORIES[@]}" "${BUILD_REPOSITORIES[@]}" )
    "${MAIN_EXEC[@]}" create-milestones "${RELEASE}" "${MILESTONE_REPOSITORY_ARRAY[@]}"
}

instructions () {
    test_for_rvm
    echo -e "\n\e[1;4;33mNormal Release Instructions:\e[0m\n"
    echo "rvm use 2.1"
    echo "RELEASE='v2.0.x'"
    echo "$0 -v build-and-release-all \${RELEASE}"
    echo "Update \"RELEASE_DATES\" in variables_local.sh"
    echo "vi ./variables_local.sh"
    echo "$0 generate-csv"
    echo "Create a release presentation and export the pdf to be added to the nubis-docs/presentations folder:"
    echo "https://docs.google.com/a/mozilla.com/presentation/d/1IEyH3eDbAha1eFCfeDtHryME-1-2xeGcSgOy1HJmVgc/edit?usp=sharing"
    echo "$0 --get-release-stats"
    echo "Using the nubis-docs/templates/announce.txt send an email to:"
    echo "nubis-announce@googlegroups.com infra-systems@mozilla.com infra-webops@mozilla.com itleadership@mozilla.com moc@mozilla.com"
    echo "RELEASE='v2.x.0-dev' # For the next release"
    echo "$0 create-milestones \${RELEASE}"
    echo "$0 -v build-all \${RELEASE}"

    echo -e "\n\n\e[1;4;33mPatch release Instructions:\e[0m\n"
    echo "rvm use 2.1"
    echo "RELEASE='v2.0.2' # The new release number."
    echo "RELEASE_TO_PATCH='v2.0.1' # The previous release we are going to patch."
    echo "$0 -v --patch \${RELEASE_TO_PATCH} build-and-release-all \${RELEASE}"
    echo "Using the nubis-docs/templates/announce.txt send an email to:"
    echo "nubis-announce@googlegroups.com infra-systems@mozilla.com infra-webops@mozilla.com itleadership@mozilla.com moc@mozilla.com"
    echo -e "\n"
}

# Grab and setup called options
while [ "$1" != "" ]; do
    case $1 in
         -h | -H | --help )
            echo -en "\nUsage: $0 [options] command [repository]\n\n"
            echo -en "Commands:\n"
            echo -en "  build-all [REL]                Build all infrastructure repositories (set in variables file)\n"
            echo -en "  build-and-release-all [REL]    Build and release all repositories (set in variables file)\n"
            echo -en "  generate-csv [DATES]           Help for generating stats for release documentation\n"
            echo -en "  upload-lambda [REL]            Upload lambda functions to S3\n\n"
            echo -en "Options:\n"
            echo -en "  --help            -h      Print this help information and exit\n"
            echo -en "  --bucket          -b      The name of a s3 bucket to upload lambda functions to\n"
            echo -en "  --docker          -d      Use the nubis-release docker container for all operations\n"
            echo -en "  --instructions    -i      Echo build steps\n"
            echo -en "  --patch                   The release number to patch from\n"
            echo -en "  --profile         -P      Specify a profile to use when uploading the files\n"
            echo -en "                              Defaults to '$PROFILE'\n"
            echo -en "  --silent          -s      Silence terminal output.\n"
            echo -en "                              Default: OFF\n"
            echo -en "  --terminal        -T      Duplicate all log and debug messages to the terminal\n"
            echo -en "                              Default: ON\n"
            echo -en "  --info            -v      Turn on info, should be set before other arguments\n"
            echo -en "  --verbose         -vv     Turn on verbosity, should be set before other arguments\n"
            echo -en "  --debug           -vvv    Turn on debugging, should be set before other arguments\n"
            echo -en "  --setx            -x      Turn on bash setx, should be set before other arguments\n\n"
            exit 0
        ;;
        -b | --bucket )
            # The name of a s3 bucket to upload lambda functions to
            S3_BUCKET="${2}"
            shift
        ;;
        -d | --docker )
            # Use the nubis-release docker container for all operations
            USE_DOCKER='TRUE'
        ;;
        -i | --instructions )
            $0 instructions
            GOT_COMMAND=1
        ;;
        --patch )
            # The release number to patch from (tag to check out as starting point for release)
            RELEASE_TO_PATCH="${2}"
            MAIN_EXEC=( "${MAIN_EXEC[@]}" '--patch' "${RELEASE_TO_PATCH}" )
            shift
        ;;
        -P | --profile )
            # The profile to use to upload files
            PROFILE="${2}"
            shift
        ;;
        -s | --silent)
            VERBOSE_SILENT=1
            log_term 2 "Terminal output silent set to: ${VERBOSE_SILENT}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -T | --terminal )
            VERBOSE_TERMINAL=1
            log_term 1 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -v | --info )
            VERBOSE='-v'
            VERBOSE_INTERNAL=1
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -vv | --verbose )
            VERBOSE='-vv'
            VERBOSE_INTERNAL=2
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            ;;
        -vvv | --debug )
            VERBOSE='-vvv'
            VERBOSE_INTERNAL=3
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -x | --setx )
            log_term 1 "Setting 'set -x'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            set -x
        ;;
        build-all )
            setup_main_command
            RELEASE="${2}"
            build_and_release_all "${RELEASE}" 'skip-release'
            GOT_COMMAND=1
        ;;
        build-and-release-all )
            setup_main_command
            RELEASE="${2}"
            build_and_release_all "${RELEASE}"
            GOT_COMMAND=1
        ;;
        create-milestones )
            setup_main_command
            RELEASE="${2}"
            create-milestones "${RELEASE}"
            GOT_COMMAND=1
        ;;
        generate-csv )
            setup_main_command
            RELEASE="${2}"
            "${MAIN_EXEC[@]}" generate-csv "${RELEASE_DATES}"
            GOT_COMMAND=1
        ;;
        get-release-stats )
            setup_main_command
            # NOTE: RELEASE_DATES set in local variables file
            "${MAIN_EXEC[@]}" --get-release-stats "${RELEASE_DATES}"
            GOT_COMMAND=1
        ;;
        upload-lambda )
            setup_main_command
            RELEASE="${2}"
            upload_lambda_functions "${RELEASE}" "${S3_BUCKET}" 'skip-release'
            GOT_COMMAND=1
        ;;
    esac
    shift
done

# If we did not get a valid command print the help message
if [ "${GOT_COMMAND:-0}" == 0 ]; then
    $0 --help
fi
