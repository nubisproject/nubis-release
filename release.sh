#!/bin/bash


# DONE: tag nubis-builder before building [nubis-ci]/nubis/puppet/builder.pp
# DONE: if a nubis/Puppetfile exists do the librarian-puppet dance (nubis-nat - edit versions)
# TODO: Close release issues
# TODO: If nubis-deploy terraform modules are pinned to master (not a version) they will not be caught by these regexes.



# Make sure we capture failures from pipe commands
set -o pipefail

# This function sets up logging, debugging and terminal output
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
#    if [ ! $SESSION_NUMBER ]; then
#        SESSION_NUMBER=$$
#    fi
    if [ ${VERBOSE_INTERNAL:-0} -ge 0 ] && [ $1 == 0 ]; then
        $($LOGGER -p local7.warning -t nubis-release "$2")
#        echo $3 "[$(date)] [Session $SESSION_NUMBER] $2" >> $RELEASE_LOG
        if [ ${VERBOSE_SILENT:-0} != 1 ]; then
            echo $3 "$2"
        fi
    fi
    if [ ${VERBOSE_INTERNAL:-0} -gt 0 ] && [ $1 == 1 ]; then
        $($LOGGER -p local7.warning -t nubis-release "$2")
#        echo $3 "[$(date)] [Session $SESSION_NUMBER] $2" >> $RELEASE_LOG
        if [ ${VERBOSE_TERMINAL:-0} == 1 ] && [ ${VERBOSE_SILENT:-0} != 1 ]; then
            echo $3 "$2"
        fi
    fi
    if [ ${VERBOSE_INTERNAL:-0} -gt 1 ] && [ $1 == 2 ]; then
        $($LOGGER -p local7.warning -t nubis-release "$2")
#        echo $3 "[$(date)] [Session $SESSION_NUMBER] $2" >> $RELEASE_LOG
        if [ ${VERBOSE_TERMINAL:-0} == 1 ] && [ ${VERBOSE_SILENT:-0} != 1 ]; then
            echo $3 "$2"
        fi
    fi
    if [ ${VERBOSE_INTERNAL:-0} -gt 2 ] && [ $1 == 3 ]; then
        $($LOGGER -p local7.warning -t nubis-release "$2")
#        echo $3 "[$(date)] [Session $SESSION_NUMBER] $2" >> $RELEASE_LOG
        if [ ${VERBOSE_TERMINAL:-0} == 1 ] && [ ${VERBOSE_SILENT:-0} != 1 ]; then
            echo $3 "$2"
        fi
    fi
}

# Source the variables file
if [ -f ./variables.sh ]; then
    source ./variables.sh
else
    log_term 0 "ERROR: No 'variables.sh' file found"
    exit 1
fi

source_files () {
    declare -a LIB_FILES=( build.sh dependencies.sh edit.sh generate_release_csv.sh git_functions.sh testing.sh upload_assets.sh )
    log_term 3 "${LIB_FILES[*]}"

    for FILE in ${LIB_FILES[*]}; do
        if [ -f ./bin/${FILE} ]; then
        log_term 1 "sourcing: ./bin/${FILE}"
            source ./bin/${FILE}
        else
            log_term 0 "ERROR: File './bin/${FILE}' not found"
            exit 1
        fi
    done
}

instructions () {
    test_for_rvm
    echo "rvm use 2.1"
#    echo "cd ${NUBIS_PATH}/nubis-base/nubis/ && librarian-puppet clean; cd -"
#    echo "rm ${NUBIS_PATH}/nubis-base/nubis/Puppetfile.lock"
    echo "RELEASE='v1.4.0'"
    echo "$0 file-release \${RELEASE}"
    echo "$0 update-all"
    echo "$0 upload-assets \${RELEASE}"
#    echo "export AWS_VAULT_BACKEND=kwallet"
    echo "$0 build-infrastructure \${RELEASE}"
    echo "$0 release-all \${RELEASE}"
#    echo "Take care of nubis-ci bullshit"
#    echo "Update nubis-builder version to currentl release in:"
#    echo "vi ${NUBIS_PATH}/nubis-ci/nubis/puppet/builder.pp"
#    echo "$0 build nubis-ci \${RELEASE}"
#    echo "$0 release nubis-ci \${RELEASE}"
    echo "Close all release issues"
    echo "https://github.com/issues?q=is%3Aissue+user%3ANubisproject+\${RELEASE}+in%3Atitle+is%3Aopen"
    echo "Update date range in generate_release_csv.sh"
    echo "vi ./bin/generate_release_csv.sh"
    echo "./bin/generate_release_csv.sh"
    echo "inport into milestone tracker at:"
    echo "https://docs.google.com/spreadsheets/d/1tClKynjyng50VEq-xuMwSP_Pkv-FsXWxEejWs-SjDu8/edit?usp=sharing"
    echo "Create a release presentation and export the pdf to be added to the nubis-docs/presentations folder:"
    echo "https://docs.google.com/a/mozilla.com/presentation/d/1IEyH3eDbAha1eFCfeDtHryME-1-2xeGcSgOy1HJmVgc/edit?usp=sharing"
    echo "Using the nubis-docs/templates/announce.txt send an email to:"
    echo "nubis-announce@googlegroups.com infra-systems@mozilla.com infra-webops@mozilla.com itleadership@mozilla.com moc@mozilla.com"
    echo "$0 create-milestones v1.X.0 # For the next release"
    echo "$0 upload-assets v1.X.0-dev # For the next release"
    echo "$0 build-infrastructure v1.X.0-dev # For the next release"
    echo "$0 build nubis-ci v1.X.0-dev # For the next release"
}


# Grab and setup called options
while [ "$1" != "" ]; do
    case $1 in
        -s | --silent)
            VERBOSE_SILENT=1
            log_term 2 "Terminal output silent set to: ${VERBOSE_SILENT}"
        ;;
        -v | --info )
            VERBOSE_INTERNAL=1
            log_term 0 "Verbosity level set to: ${VERBOSE_INTERNAL}"
        ;;
        -vv | --verbose )
            VERBOSE_INTERNAL=2
            log_term 0 "Verbosity level set to: ${VERBOSE_INTERNAL}"
            ;;
        -vvv | --debug )
            VERBOSE_INTERNAL=3
            log_term 0 "Verbosity level set to: ${VERBOSE_INTERNAL}"
        ;;
        -T | --terminal )
            VERBOSE_TERMINAL=1
            log_term 0 "Duplicate log to terminal set to: ${VERBOSE_TERMINAL}"
        ;;
        -x | --setx )
            log_term 0 "Setting 'set -x'"
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
         -h | -H | --help )
            echo -en "$0\n\n"
            echo -en "Usage: $0 [options] command [repository]\n\n"
            echo -en "Commands:\n"
            echo -en "  update [repo]                 Update repository [repo]\n"
            echo -en "  update-all                    Update all repositories\n"
            echo -en "  file-release [rel]            File all release issues in GitHub\n"
            echo -en "  create-milestones [rel]       Create all milestones in Github\n"
            echo -en "  upload-assets [rel]           Upload nested stacks to S3\n"
            echo -en "  build [repo] [rel]            Build AMIs for [REPO] repository at [REL] release\n"
            echo -en "  build-infrastructure [rel]    Build all infrastructure components\n"
            echo -en "  release [repo] [rel]          Release [REPO] repository at [REL] release\n"
            echo -en "  release-all [rel]             Release all ${GITHUB_ORGINIZATION} repositories\n"
            echo -en "  instructions                  Echo build steps\n\n"
            echo -en "Options:\n"
            echo -en "  --help      -h    Print this help information and exit\n"
            echo -en "  --path      -p    Specify a path where your nubis repositories are checked out\n"
            echo -en "                      Defaults to '${NUBIS_PATH}'\n"
            echo -en "  --login     -l    Specify a login to use when forking repositories\n"
            echo -en "                      Defaults to '${GITHUB_LOGIN}'\n"
            echo -en "  --profile   -P    Specify a profile to use when uploading the files\n"
            echo -en "                      Defaults to '$PROFILE'\n"
            echo -en "  --verbose   -v    Turn on verbosity, this should be set as the first argument\n"
            echo -en "                      Basically set -x\n\n"
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
        file-release )
            RELEASE="${2}"
            shift
            source_files
            file_release_issues ${RELEASE}
            GOT_COMMAND=1
        ;;
        create-milestones )
            RELEASE="${2}"
            shift
            source_files
            create_milestones ${RELEASE}
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
            echo -e "\n Building AMIs for \"${REPOSITORY}\"."
            build_amis "${RELEASE}" "${REPOSITORY}"
            GOT_COMMAND=1
        ;;
        build-infrastructure )
            RELEASE="${2}"
            shift
            source_files
            build_infrastructure_amis ${RELEASE}
            GOT_COMMAND=1
        ;;
        release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            shift
            source_files
            echo -e "\n Releasing repository \"${REPOSITORY}\". (${_COUNT} of ${#REPOSITORY_ARRAY[*]})"
            release_repository "${RELEASE}" "${REPOSITORY}"
            GOT_COMMAND=1
        ;;
        release-all )
            RELEASE="${2}"
            shift
            source_files
            release_all_repositories ${RELEASE}
            GOT_COMMAND=1
        ;;
        instructions )
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
#            RET=$(testing "$2" "nubis-base")
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
