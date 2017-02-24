#!/bin/bash

# TODO: Branch for non-dev release
# TODO: If nubis-deploy terraform modules are pinned to master (not a version) they will not be caught by these regexes.
# TODO: enable patch release, hook for checking out previous release instead of master
# TODO: upload_assets should check timestamp and not upload if there are no updates (improves speed)
# TODO: Create docker container with all dependancies

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
    echo "ERROR: '$BASH_SOURCE' Line: '$LINENO'"
    exit 2
fi
log_term () {
    if [ ${VERBOSE_INTERNAL:-0} -ge 0 ] && [ ${1} == 0 ]; then
        $($LOGGER -p local7.warning -t nubis-release "$2")
        if [ ${VERBOSE_SILENT:-0} != 1 ]; then
            echo ${3} "${2}" 1>&2
        fi
    fi
    if [ ${VERBOSE_INTERNAL:-0} -gt 0 ] && [ ${1} == 1 ]; then
        $($LOGGER -p local7.warning -t nubis-release "$2")
        if [ ${VERBOSE_TERMINAL:-0} == 1 ] && [ ${VERBOSE_SILENT:-0} != 1 ]; then
            echo ${3} "${2}" 1>&2
        fi
    fi
    if [ ${VERBOSE_INTERNAL:-0} -gt 1 ] && [ ${1} == 2 ]; then
        $($LOGGER -p local7.warning -t nubis-release "$2")
        if [ ${VERBOSE_TERMINAL:-0} == 1 ] && [ ${VERBOSE_SILENT:-0} != 1 ]; then
            echo ${3} "${2}" 1>&2
        fi
    fi
    if [ ${VERBOSE_INTERNAL:-0} -gt 2 ] && [ ${1} == 3 ]; then
        $($LOGGER -p local7.warning -t nubis-release "$2")
        if [ ${VERBOSE_TERMINAL:-0} == 1 ] && [ ${VERBOSE_SILENT:-0} != 1 ]; then
            echo ${3} "${2}" 1>&2
        fi
    fi
}

# Source the variables file
if [ -f ./variables.sh ]; then
    log_term 2 "Sourcing: ./variables.sh"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
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
        if [ -f ./bin/${FILE} ]; then
        log_term 2 "Sourcing: ./bin/${FILE}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            source ./bin/${FILE}
        else
            log_term 0 "ERROR: File './bin/${FILE}' not found"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            exit 1
        fi
    done
}

instructions () {
    test_for_rvm
    echo "rvm use 2.1"
    echo "RELEASE='v1.4.0'"
    echo "$0 --non-interactive build-and-release-all \${RELEASE}"
    echo "$0 close-milestones \${RELEASE}"
    echo "Update \"RELEASE_DATES\" in variables.sh"
    echo "vi ./variables.sh"
    echo "$0 generate-csv"
    echo "Create a release presentation and export the pdf to be added to the nubis-docs/presentations folder:"
    echo "https://docs.google.com/a/mozilla.com/presentation/d/1IEyH3eDbAha1eFCfeDtHryME-1-2xeGcSgOy1HJmVgc/edit?usp=sharing"
    echo "Using the nubis-docs/templates/announce.txt send an email to:"
    echo "nubis-announce@googlegroups.com infra-systems@mozilla.com infra-webops@mozilla.com itleadership@mozilla.com moc@mozilla.com"
    echo "RELEASE='v1.X.0' # For the next release"
    echo "$0 create-milestones \${RELEASE}"
    echo "$0 --non-interactive build-all \${RELEASE}-dev"
}

# Grab and setup called options
while [ "$1" != "" ]; do
    case $1 in
        -s | --silent)
            VERBOSE_SILENT=1
            log_term 2 "Terminal output silent set to: ${VERBOSE_SILENT}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -v | --info )
            VERBOSE_INTERNAL=1
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -vv | --verbose )
            VERBOSE_INTERNAL=2
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            ;;
        -vvv | --debug )
            VERBOSE_INTERNAL=3
            log_term 2 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            VERBOSE_TERMINAL=1
            log_term 2 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}. Disable with '--silent'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -T | --terminal )
            VERBOSE_TERMINAL=1
            log_term 1 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        ;;
        -x | --setx )
            log_term 1 "Setting 'set -x'"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            set -x
        ;;
        -p | --path )
            # The path to where the nubis repositories are checked out
            NUBIS_PATH=$2
            shift
        ;;
        -l | --login )
            # The github login to fork new repositories against
            GITHUB_LOGIN=$2
            shift
        ;;
        -P | --profile )
            # The profile to use to upload the files
            PROFILE=$2
            shift
        ;;
        -y | --non-interactive )
            # Set to skip interactive prompts
            NON_INTERACTIVE='yes'
        ;;
         -h | -H | --help )
            echo -en "$0\n\n"
            echo -en "Usage: $0 [options] command [repository]\n\n"
            echo -en "Commands:\n"
            echo -en "  update [repo]              Update repository [repo]\n"
            echo -en "  update-all                 Update all repositories\n"
            echo -en "  create-milestones [rel]    Create all milestones in Github\n"
            echo -en "  close-milestones [rel]     Close all milestones in Github\n"
            echo -en "  upload-assets [rel]        Upload aritfacts to S3\n"
            echo -en "  build [repo] [rel]         Build AMIs for [REPO] repository at [REL] release\n"
            echo -en "  release [repo] [rel]       Release [REPO] repository at [REL] release\n"
            echo -en "  build-and-release          Build and release named repository\n\n"
            echo -en "  build-and-release-all      Build and release all repositories (set in variables file)\n\n"
            echo -en "  build-all                  Build all infrastructure repositories (set in variables file)\n\n"
            echo -en "  generate-csv [file]        Generate CSV file of release issues. Optionally declare [file]name\n\n"
            echo -en "  instructions               Echo build steps\n\n"
            echo -en "  install-rvm                Attempt to install rvm EXPERIMENTAL\n\n"
            echo -en "Options:\n"
            echo -en "  --help      -h          Print this help information and exit\n"
            echo -en "  --path      -p          Specify a path where your nubis repositories are checked out\n"
            echo -en "                            Defaults to '${NUBIS_PATH}'\n"
            echo -en "  --login     -l          Specify a login to use when forking repositories\n"
            echo -en "                            Defaults to '${GITHUB_LOGIN}'\n"
            echo -en "  --profile   -P          Specify a profile to use when uploading the files\n"
            echo -en "                            Defaults to '$PROFILE'\n"
            echo -en "  --non-interactive -y    Set to skip all interactive prompts\n"
            echo -en "  --info      -v          Turn on info, should be set before other arguments\n"
            echo -en "  --verbose   -vv         Turn on verbosity, should be set before other arguments\n"
            echo -en "  --debug     -vvv        Turn on debugging, should be set before other arguments\n"
            echo -en "  --setx      -x          Turn on bash setx, should be set before other arguments\n"
            echo -en "                            Basically set -x\n\n"
            exit 0
        ;;
        update )
            REPOSITORY="${2}"
            shift
            source_files
            update_repository
            GOT_COMMAND=1
        ;;
        update-all )
            source_files
            update_all_repositories
            GOT_COMMAND=1
        ;;
        create-milestones )
            RELEASE="${2}"
            shift
            source_files
            create_milestones ${RELEASE}
            GOT_COMMAND=1
        ;;
        close-milestones )
            RELEASE="${2}"
            shift
            source_files
            close_milestones ${RELEASE}
            GOT_COMMAND=1
        ;;
        upload-assets )
            RELEASE="${2}"
            shift
            source_files
#            upload_stacks ${RELEASE}
            upload_lambda_functions ${RELEASE}
            GOT_COMMAND=1
        ;;
        build )
            REPOSITORY="${2}"
            RELEASE="${3}"
            shift
            source_files
            build_amis "${REPOSITORY}" "${RELEASE}"
            GOT_COMMAND=1
        ;;
        release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            shift
            source_files
            release_repository "${REPOSITORY}" "${RELEASE}"
            GOT_COMMAND=1
        ;;
        build-and-release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            shift
            source_files
            build_and_release "${REPOSITORY}" "${RELEASE}"
            GOT_COMMAND=1
        ;;
        build-and-release-all )
            RELEASE="${2}"
            shift
            source_files
            build_and_release_all "${RELEASE}"
            GOT_COMMAND=1
        ;;
        build-all )
            RELEASE="${2}"
            shift
            source_files
            build_and_release_all "${RELEASE}" 'skip-release'
            GOT_COMMAND=1
        ;;
        generate-csv )
            CSV_FILE="${2}"
            shift
            source_files
            generate_release_csv "${CSV_FILE}"
            GOT_COMMAND=1
        ;;
        instructions )
            source_files
            instructions
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
            shift
            GOT_COMMAND=1
        ;;
    esac
    shift
done

# If we did not get a valid command print the help message
if [ ${GOT_COMMAND:-0} == 0 ]; then
    $0 --help
fi

# fin
