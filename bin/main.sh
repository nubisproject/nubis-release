#!/bin/bash
# shellcheck disable=SC1117

# Make sure we capture failures from pipe commands
set -o pipefail
# Required to trim characters
shopt -s extglob

# Set up our path for later use
export SCRIPT_PATH="$PWD"

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

# If we set -x and are in a sub-call, reset for sub-shell
if [ "${SET_X:-NULL}" != 'NULL' ]; then
    set -x
fi

# Source the variables file
if [ -f ./variables.sh ]; then
    log_term 2 "Sourcing: ./variables.sh"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    # https://github.com/koalaman/shellcheck/wiki/SC1091
    # shellcheck disable=SC1091
    source ./variables.sh
else
    echo "ERROR: No 'variables.sh' file found"  1>&2
    echo "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"  1>&2
    exit 1
fi

source_files () {
    declare -ar LIB_FILES=( build.sh dependencies.sh edit.sh git_functions.sh testing.sh upload_assets.sh )
    log_term 3 "${LIB_FILES[*]}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    for FILE in ${LIB_FILES[*]}; do
        if [ -f ./"${FILE}" ]; then
        log_term 2 "Sourcing: ./${FILE}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            # https://github.com/koalaman/shellcheck/wiki/SC1090
            # shellcheck source=/dev/null.
            # https://github.com/koalaman/shellcheck/wiki/SC1091
            # shellcheck disable=SC1091
            source ./"${FILE}"
        else
            log_term 0 "ERROR: File './${FILE}' not found"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            exit 1
        fi
    done
}

release_stats () {
    local -r RELEASE_DATES="${2}"
    if [ "${RELEASE_DATES:-'NULL'}" == 'NULL' ]; then
        log_term 0 "\nYou must pass in the release dates to get accurate links with this function." -e
        exit 1
    fi
    echo -e "\n\033[1;4;33mPull Requests Merged:\033[0m\n"
    echo "https://github.com/pulls?utf8=%E2%9C%93&q=is%3Apr+user%3ANubisproject+merged%3A${RELEASE_DATES}+"
    echo -e "\n\033[1;4;33mIssues Opened Since Last Release:\033[0m\n"
    echo "https://github.com/issues?utf8=%E2%9C%93&q=is%3Aissue+user%3Anubisproject+created%3A${RELEASE_DATES}+"
    echo -e "\n\033[1;4;33mIssues Closed:\033[0m\n"
    echo "https://github.com/issues?utf8=%E2%9C%93&q=is%3Aclosed+is%3Aissue+user%3Anubisproject+closed%3A${RELEASE_DATES}"
    echo -e "\n\033[1;4;33mIssues Remaining:\033[0m\n"
    echo "https://github.com/issues?utf8=%E2%9C%93&q=is%3Aopen+is%3Aissue+user%3Anubisproject"
}

# Grab and setup called options
while [ "$1" != "" ]; do
    case $1 in
         -h | -H | --help )
            echo -en "\nUsage: $0 [options] command [repository]\n\n"
            echo -en "Commands:\n"
            echo -en "  build [REPO] [REL]                Build AMIs for [REPO] repository at [REL] release\n"
            echo -en "  build-all [REL]                   Build all infrastructure repositories (set in variables file)\n"
            echo -en "  build-and-release [REPO] [REL]    Build and release named repository\n"
            echo -en "  build-and-release-all [REL]       Build and release all repositories (set in variables file)\n"
            echo -en "  close-milestones [REL]            Close all milestones in Github\n"
            echo -en "  create-milestones [REL]           Create all milestones in Github\n"
            echo -en "  generate-csv [file]               Generate CSV file of release issues. Optionally declare [file]name\n"
            echo -en "  get-release-stats [DATES]         Help for generating stats for release documentation\n"
            echo -en "  release [REPO] [REL]              Release [REPO] repository at [REL] release\n"
            echo -en "  upload-assets [REL]               Upload aritfacts to S3\n\n"
            echo -en "Options:\n"
            echo -en "  --help               -h      Print this help information and exit\n"
            echo -en "  --instructions       -i      Echo build steps\n"
            echo -en "  --oath-token                 The GitHub OATH token to use for API queries\n"
            echo -en "  --patch                      Specify a release tag to base the patch release from\n"
            echo -en "  --path               -p      Specify a path where your nubis repositories are checked out\n"
            echo -en "                                 Defaults to '${REPOSITORY_PATH}'\n"
            echo -en "  --profile            -P      Specify a profile to use when uploading the files\n"
            echo -en "                           Defaults to '$PROFILE'\n"
            echo -en "  --silent             -s      Silence terminal output.\n"
            echo -en "                                 Default: OFF\n"
            echo -en "  --terminal           -T      Duplicate all log and debug messages to the terminsl\n"
            echo -en "                                 Default: ON\n"
            echo -en "  --info               -v      Turn on info, should be set before other arguments\n"
            echo -en "  --verbose            -vv     Turn on verbosity, should be set before other arguments\n"
            echo -en "  --debug              -vvv    Turn on debugging, should be set before other arguments\n"
            echo -en "  --setx               -x      Turn on bash setx, should be set before other arguments\n"
            echo -en "  --non-interactive    -y      Set to skip all interactive prompts\n"
            echo -en "                                 Basically set -x\n\n"
            exit 0
        ;;
        -i | --instructions )
            source_files || exit 1
            instructions
            GOT_COMMAND=1
        ;;
        --oath-token )
            # The GitHub OATH token to use for API queries
            export GITHUB_OATH_TOKEN=$2
            shift
        ;;
        --patch )
            # The release number to patch from (tag to check out as starting point for release)
            export RELEASE_TO_PATCH=$2
            shift
        ;;
        -p | --path )
            # The path to where repositories are checked out
            export REPOSITORY_PATH=$2
            shift
        ;;
        -P | --profile )
            # The profile to use to upload files
            export PROFILE=$2
            shift
        ;;
        -s | --silent)
            export VERBOSE_SILENT=1
            log_term 2 "Terminal output silent set to: ${VERBOSE_SILENT}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -T | --terminal )
            export VERBOSE_TERMINAL=1
            log_term 1 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -v | --info )
            export VERBOSE_INTERNAL=1
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            export VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -vv | --verbose )
            export VERBOSE_INTERNAL=2
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            export VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            ;;
        -vvv | --debug )
            export VERBOSE_INTERNAL=3
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            export VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -x | --setx )
            log_term 1 "Setting 'set -x'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            set -x
            export SET_X=1
        ;;
        -y | --non-interactive )
            # Set to skip interactive prompts
            export NON_INTERACTIVE='yes'
        ;;
        build )
            REPOSITORY="${2}"
            RELEASE="${3}"
            SKIP_CLONE="${4}"
            source_files || exit 1
            build_amis "${REPOSITORY}" "${RELEASE}" "${SKIP_CLONE}"
            GOT_COMMAND=1
        ;;
        build-and-release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            source_files || exit 1
             # Build the AMI
            log_term 1 "\nBuilding AMIs for repository: \"${REPOSITORY}\"." -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            if ! "$0" build "${REPOSITORY}" "${RELEASE}" ; then
                log_term 0 "Building for '${REPOSITORY}' failed. Unable to continue."
                log_term 0 "Aborting....."
                exit 1
            fi
           # Set up release
            log_term 1 "\nSetting up release: \"${REPOSITORY}\"." -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            if ! "$0" setup-release "${REPOSITORY}" "${RELEASE}" 'SKIP_CLONE' ; then
                log_term 0 "Setting up release for '${REPOSITORY}' failed. Unable to continue."
                log_term 0 "Aborting....."
                exit 1
            fi
            # Release repository
            log_term 1 "\nReleasing repository: \"${REPOSITORY}\"." -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            if ! "$0" complete-release "${REPOSITORY}" "${RELEASE}" ; then
                log_term 0 "Release for '${REPOSITORY}' failed. Unable to continue."
                log_term 0 "Aborting....."
                exit 1
            fi
            GOT_COMMAND=1
        ;;
        close-milestones )
            RELEASE="${2}"
            shift 2
            IFS_SAVE="$IFS"; read -r -a MILESTONE_REPOSITORY_ARRAY <<< "${@}"; IFS="$IFS_SAVE"
            source_files || exit 1
            close_milestones "${RELEASE}" "${MILESTONE_REPOSITORY_ARRAY[@]}"
            GOT_COMMAND=1
        ;;
        complete-release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            source_files || exit 1
            repository_complete_release "${REPOSITORY}" "${RELEASE}"
            GOT_COMMAND=1
        ;;
        create-milestones )
            RELEASE="${2}"
            shift 2
            IFS_SAVE="$IFS"; read -r -a MILESTONE_REPOSITORY_ARRAY <<< "${@}"; IFS="$IFS_SAVE"
            source_files || exit 1
            create_milestones "${RELEASE}" "${MILESTONE_REPOSITORY_ARRAY[@]}"
            GOT_COMMAND=1
        ;;
        edit )
            shift
            source_files || exit 1
            # This is treated as a sub command, so lets just pass through all the caller options
            modify "${@}"
            shift ${#}
            GOT_COMMAND=1
        ;;
        generate-csv )
            RELEASE_DATES="${2}"
            CSV_FILE="${3}"
            source_files || exit 1
            generate_release_csv "${RELEASE_DATES}" "${CSV_FILE}"
            GOT_COMMAND=1
        ;;
        get-release-stats )
            RELEASE_DATES="${2}"
            source_files || exit 1
            release_stats "${RELEASE_DATES}"
            GOT_COMMAND=1
        ;;
        release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            source_files || exit 1
            $0 setup-release "${REPOSITORY}" "${RELEASE}" || exit 1
            $0 complete-release "${REPOSITORY}" "${RELEASE}" || exit 1
            GOT_COMMAND=1
        ;;
        setup-release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            GIT_REF="${4}"
            source_files || exit 1
            repository_setup_release "${REPOSITORY}" "${RELEASE}" "${GIT_REF}"
            GOT_COMMAND=1
        ;;
        testing )
            RELEASE="${2}"
            source_files || exit 1
            RET=$(testing "${RELEASE}")
            echo "RET: $RET"
            GOT_COMMAND=1
        ;;
        upload-assets )
            shift
            source_files || exit 1
            # This is treated as a sub command, so lets just pass through all the caller options
            upload-assets "${@}"
            shift ${#}
            GOT_COMMAND=1
        ;;
    esac
    shift
done

# If we did not get a valid command print the help message
if [ "${GOT_COMMAND:-0}" == 0 ]; then
    $0 --help
fi

# fin
