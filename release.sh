#!/bin/bash

# Make sure we capture failures from pipe commands
set -o pipefail
# Required to trim characters
shopt -s extglob

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
    declare -a LIB_FILES=( build.sh dependencies.sh edit.sh git_functions.sh testing.sh upload_assets.sh )
    log_term 3 "${LIB_FILES[*]}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    for FILE in ${LIB_FILES[*]}; do
        if [ -f ./bin/"${FILE}" ]; then
        log_term 2 "Sourcing: ./bin/${FILE}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            # https://github.com/koalaman/shellcheck/wiki/SC1090
            # shellcheck source=/dev/null.
            # https://github.com/koalaman/shellcheck/wiki/SC1091
            # shellcheck disable=SC1091
            source ./bin/"${FILE}"
        else
            log_term 0 "ERROR: File './bin/${FILE}' not found"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            exit 1
        fi
    done
}

instructions () {
    test_for_rvm
    echo -e "\n\e[1;4;33mNormal Release:\e[0m\n"
    echo "rvm use 2.1"
    echo "RELEASE='v1.4.0'"
    echo "$0 --non-interactive build-and-release-all \${RELEASE}"
    echo "Update \"RELEASE_DATES\" in variables.sh"
    echo "vi ./variables.sh"
    echo "$0 generate-csv"
    echo "Create a release presentation and export the pdf to be added to the nubis-docs/presentations folder:"
    echo "https://docs.google.com/a/mozilla.com/presentation/d/1IEyH3eDbAha1eFCfeDtHryME-1-2xeGcSgOy1HJmVgc/edit?usp=sharing"
    echo "$0 get-release-stats"
    echo "Using the nubis-docs/templates/announce.txt send an email to:"
    echo "nubis-announce@googlegroups.com infra-systems@mozilla.com infra-webops@mozilla.com itleadership@mozilla.com moc@mozilla.com"
    echo "RELEASE='v1.X.0' # For the next release"
    echo "$0 create-milestones \${RELEASE}"
    echo "$0 --non-interactive build-all \${RELEASE}-dev"

    echo -e "\n\n\e[1;4;33mPatch release:\e[0m\n"
    echo "rvm use 2.1"
    echo "RELEASE='v1.4.1'"
    echo "PREVIOUS_RELEASE='v1.4.0' # This is the release the patch will use as a starting point, a git ref."
    echo "$0 --non-interactive patch-release-setup \${RELEASE} \${PREVIOUS_RELEASE}"
    echo "Perform manual patching"
    echo "$0 --non-interactive patch-release-complete \${RELEASE}"
    echo "Using the nubis-docs/templates/announce.txt send an email to:"
    echo "nubis-announce@googlegroups.com infra-systems@mozilla.com infra-webops@mozilla.com itleadership@mozilla.com moc@mozilla.com"
    echo -e "\n"
}

release_stats () {
    echo -e "\nYou should update the release dates in the variables.sh file to get accurate links with this function."
    echo -e "\n\e[1;4;33mPull Requests Merged:\e[0m\n"
    echo "https://github.com/pulls?utf8=%E2%9C%93&q=is%3Apr+user%3ANubisproject+merged%3A${RELEASE_DATES}+"
    echo -e "\n\e[1;4;33mIssues Opened Since Last Release:\e[0m\n"
    echo "https://github.com/issues?utf8=%E2%9C%93&q=is%3Aissue+user%3Anubisproject+created%3A${RELEASE_DATES}+"
    echo -e "\n\e[1;4;33mIssues Closed:\e[0m\n"
    echo "https://github.com/issues?utf8=%E2%9C%93&q=is%3Aclosed+is%3Aissue+user%3Anubisproject+closed%3A${RELEASE_DATES}"
    echo -e "\n\e[1;4;33mIssues Remaining:\e[0m\n"
    echo "https://github.com/issues?utf8=%E2%9C%93&q=is%3Aopen+is%3Aissue+user%3Anubisproject"
}

# Grab and setup called options
while [ "$1" != "" ]; do
    case $1 in
        -s | --silent)
            export VERBOSE_SILENT=1
            log_term 2 "Terminal output silent set to: ${VERBOSE_SILENT}"
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
        -T | --terminal )
            export VERBOSE_TERMINAL=1
            log_term 1 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -x | --setx )
            log_term 1 "Setting 'set -x'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            set -x
            export SET_X=1
        ;;
        -p | --path )
            # The path to where repositories are checked out
            export REPOSITORY_PATH=$2
            shift
        ;;
        -l | --login )
            # The github login to fork new repositories against
            export GITHUB_LOGIN=$2
            shift
        ;;
        -P | --profile )
            # The profile to use to upload files
            export PROFILE=$2
            shift
        ;;
        -y | --non-interactive )
            # Set to skip interactive prompts
            export NON_INTERACTIVE='yes'
        ;;
        -i | --instructions )
            source_files
            instructions
            GOT_COMMAND=1
        ;;
        -S | --get-release-stats )
            source_files
            release_stats
            GOT_COMMAND=1
        ;;
         -h | -H | --help )
            echo -en "$0\n\n"
            echo -en "Usage: $0 [options] command [repository]\n\n"
            echo -en "Commands:\n"
            echo -en "  create-milestones [REL]             Create all milestones in Github\n"
            echo -en "  close-milestones [REL]              Close all milestones in Github\n"
            echo -en "  upload-assets [REL]                 Upload aritfacts to S3\n"
            echo -en "  build [REPO] [REL]                  Build AMIs for [REPO] repository at [REL] release\n"
            echo -en "  setup-release [REPO] [REL] [REF]    Checks out repository [REPO] repository for [REL] release at [REF]\n"
            echo -en "  complete-release [REPO] [REL]       Release [REPO] repository at [REL] release\n"
            echo -en "  release [REPO] [REL]                Release [REPO] repository at [REL] release\n"
            echo -en "  build-and-release [REPO] [REL]      Build and release named repository\n\n"
            echo -en "  build-and-release-all [REL]         Build and release all repositories (set in variables file)\n\n"
            echo -en "  build-all [REL]                     Build all infrastructure repositories (set in variables file)\n\n"
            echo -en "  patch-release-setup  [REL] [REF]    Checks out repositories at a given ref\n\n"
            echo -en "  patch-release-complete [REL]        Updates files and releases repositories\n\n"
            echo -en "  generate-csv [file]                 Generate CSV file of release issues. Optionally declare [file]name\n\n"
            echo -en "  install-rvm                         Attempt to install rvm EXPERIMENTAL\n\n"
            echo -en "Options:\n"
            echo -en "  --help              -h      Print this help information and exit\n"
            echo -en "  --instructions      -i      Echo build steps\n\n"
            echo -en "  --get-release-stats -S      Help for generating stats for release documentation\n\n"
            echo -en "  --path              -p      Specify a path where your nubis repositories are checked out\n"
            echo -en "                                Defaults to '${REPOSITORY_PATH}'\n"
            echo -en "  --login             -l      Specify a login to use when forking repositories\n"
            echo -en "                                Defaults to '${GITHUB_LOGIN}'\n"
            echo -en "  --profile           -P      Specify a profile to use when uploading the files\n"
            echo -en "                                Defaults to '$PROFILE'\n"
            echo -en "  --non-interactive   -y      Set to skip all interactive prompts\n"
            echo -en "  --info              -v      Turn on info, should be set before other arguments\n"
            echo -en "  --verbose           -vv     Turn on verbosity, should be set before other arguments\n"
            echo -en "  --debug             -vvv    Turn on debugging, should be set before other arguments\n"
            echo -en "  --setx              -x      Turn on bash setx, should be set before other arguments\n"
            echo -en "                                Basically set -x\n\n"
            exit 0
        ;;
        create-milestones )
            RELEASE="${2}"
            source_files
            create_milestones "${RELEASE}"
            GOT_COMMAND=1
        ;;
        close-milestones )
            RELEASE="${2}"
            source_files
            close_milestones "${RELEASE}"
            GOT_COMMAND=1
        ;;
        upload-assets )
            RELEASE="${2}"
            source_files
            upload_lambda_functions "${RELEASE}"
            GOT_COMMAND=1
        ;;
        build )
            REPOSITORY="${2}"
            RELEASE="${3}"
            source_files
            build_amis "${REPOSITORY}" "${RELEASE}"
            GOT_COMMAND=1
        ;;
        setup-release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            GIT_REF="${4}"
            source_files
            repository_setup_release "${REPOSITORY}" "${RELEASE}" "${GIT_REF}"
            GOT_COMMAND=1
        ;;
        complete-release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            source_files
            repository_complete_release "${REPOSITORY}" "${RELEASE}"
            GOT_COMMAND=1
        ;;
        release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            SKIP_SETUP="${4}"
            source_files
            if [ "${SKIP_SETUP:-NULL}" == 'NULL' ]; then
                $0 setup-release "${REPOSITORY}" "${RELEASE}"
            fi
            $0 complete-release "${REPOSITORY}" "${RELEASE}"
            GOT_COMMAND=1
        ;;
        build-and-release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            SKIP_SETUP="${4}"
            source_files
            if [ "${SKIP_SETUP:-NULL}" == 'NULL' ]; then
                # Set up release
                log_term 1 "\nSetting up release: \"${REPOSITORY}\"." -e
                log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
                $0 setup-release "${REPOSITORY}" "${RELEASE}"
                if [ "${?}" != '0' ]; then
                    log_term 0 "Setting up release for '${REPOSITORY}' failed. Unable to continue."
                    log_term 0 "Aborting....."
                    exit 1
                fi
            fi
            # Build the AMI
            log_term 1 "\nBuilding AMIs for repository: \"${REPOSITORY}\"." -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            $0 build "${REPOSITORY}" "${RELEASE}"
            if [ "${?}" != '0' ]; then
                log_term 0 "Building for '${REPOSITORY}' failed. Unable to continue."
                log_term 0 "Aborting....."
                exit 1
            fi
            # Release repository
            log_term 1 "\nReleasing repository: \"${REPOSITORY}\"." -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            $0 complete-release "${REPOSITORY}" "${RELEASE}"
            if [ "${?}" != '0' ]; then
                log_term 0 "Release for '${REPOSITORY}' failed. Unable to continue."
                log_term 0 "Aborting....."
                exit 1
            fi
            GOT_COMMAND=1
        ;;
        build-and-release-all )
            RELEASE="${2}"
            source_files
            build_and_release_all "${RELEASE}"
            GOT_COMMAND=1
        ;;
        build-all )
            RELEASE="${2}"
            source_files
            build_and_release_all "${RELEASE}" 'skip-release'
            GOT_COMMAND=1
        ;;
        patch-release-setup )
            RELEASE="${2}"
            GIT_REF="${3}"
            source_files
            patch_release_setup "${RELEASE}" "${GIT_REF}"
            GOT_COMMAND=1
        ;;
        patch-release-complete )
            RELEASE="${2}"
            source_files
            build_and_release_all "${RELEASE}" 'skip-setup'
            GOT_COMMAND=1
        ;;
        generate-csv )
            CSV_FILE="${2}"
            source_files
            generate_release_csv "${CSV_FILE}"
            GOT_COMMAND=1
        ;;
        install-rvm )
            source_files
            install_rvm
            GOT_COMMAND=1
        ;;
        testing )
            RELEASE="${2}"
            source_files
            RET=$(testing "${RELEASE}")
            echo "RET: $RET"
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
