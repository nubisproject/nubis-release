#!/bin/bash
#
# These functions drive nubis-builder
#

# Clean up any librarian-puppet files
clean_librarian_puppet () {
    local _REPOSITORY="${1}"
    if [ ${_REPOSITORY:-NULL} == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    if [ -f "${NUBIS_PATH}/${_REPOSITORY}/nubis/Puppetfile" ]; then
        log_term 1 "Cleaning librarian-puppet files..."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exec 5>&1
        OUTPUT=$(cd "${NUBIS_PATH}/${_REPOSITORY}" && librarian-puppet clean | tee >(cat - >&5))
        if [ -f "${NUBIS_PATH}/${_REPOSITORY}/nubis/Puppetfile.lock" ]; then
            OUTPUT=$(rm "${NUBIS_PATH}/${_REPOSITORY}/nubis/Puppetfile.lock" | tee >(cat - >&5))
        fi
        exec 5>&-
    fi
}

# Build new AMIs for the named repository
build_amis () {
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    if [ ${_REPOSITORY:-NULL} == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    test_for_nubis_builder
    edit_project_json "${_RELEASE}" "${_REPOSITORY}"
    clean_librarian_puppet "${_REPOSITORY}"

    # Special hook for nubis-ci
    if [ ${_REPOSITORY:-NULL} == 'nubis-ci' ]; then
        edit_ci_template "${_RELEASE}"
    fi

    log_term 0 "Running nubis-builder for ${_REPOSITORY}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    exec 5>&1
    OUTPUT=$(cd "${NUBIS_PATH}/${_REPOSITORY}" && nubis-builder build --spot --instance-type c3.large | tee >(cat - >&5))
    if [ $? != '0' ]; then
# Timeout waiting for SSH
        log_term 0 "Build for ${_REPOSITORY} failed. Aborting....."
        echo "$OUTPUT"
        exit 1
    fi
    exec 5>&-

    echo "$OUTPUT"

    # nubis-builder outputs some build artifacts. Lets check them in here
    check_in_changes "${_REPOSITORY}" "Update builder artifacts for ${RELEASE} release"
}

build_and_release () {
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    if [ ${_REPOSITORY:-NULL} == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi

    # Update repository
    log_term 1 "\n Updating repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    update_repository ${_REPOSITORY}

    # File release issue
    log_term 1 "\n Filing release issue for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    local _ISSUE_TITLE="Tag ${_RELEASE} release"
    local _ISSUE_BODY="Tag a release of the ${_REPOSITORY} repository for the ${_RELEASE} release of the Nubis project."
    local _MILESTONE=$(get_set_milestone "${_RELEASE}" "${_REPOSITORY}")
    # We do not need multiple release issues
    _ISSUE_EXISTS=$(get_release_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_MILESTONE}")
    if [ $? == 0 ]; then
        log_term 2 "Release issue exists. Returned: '${_ISSUE_EXISTS}'. Skipping 'file_issue'."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    else
        file_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_ISSUE_BODY}" "${_MILESTONE}"
    fi

    # Build AMI
    log_term 1 "\n Building AMIs for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    $($0 build "${_REPOSITORY}" "${_RELEASE}")
    if [ $? != '0' ]; then
        if [ "${NON_INTERACTIVE:-NULL}" == 'NULL' ]; then
            log_term 0 "Build for ${_REPOSITORY} failed. Contine? [y/N]"
            read CONTINUE
            if [ ${CONTINUE:-n} == "N" ] || [ ${CONTINUE:-n} == "n" ]; then
                log_term 0 "Aborting....."
                exit 1
            fi
            continue
        else
            log_term 0 "Build for ${_REPOSITORY} failed."
            log_term 0 "Aborting....."
#            echo "$OUTPUT"
            exit 1
        fi
    fi

    # Release repository
    log_term 0 "\n Releasing repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    release_repository "${_REPOSITORY}" "${_RELEASE}"

    # Close release issue
    log_term 0 "\n Closing release issue for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    _ISSUE_NUMBER=$(get_release_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_MILESTONE}")
    if [ $? != 0 ]; then
        log_term 1 "Warning: 'get_release_issue' returned: '${_ISSUE_NUMBER}'. Skipping 'close_issue'."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    else
        local _MESSAGE="Release of repository ${_REPOSITORY} for the ${_RELEASE} release complete. Closing issue."
        close_issue "${_REPOSITORY}" "${_MESSAGE}" "${_ISSUE_NUMBER}"
    fi

    unset _REPOSITORY _RELEASE _ISSUE_TITLE _ISSUE_BODY _MILESTONE _ISSUE_EXISTS _ISSUE_NUMBER _MESSAGE
}

build_and_release_all () {
    local _RELEASE="${1}"
    local _SKIP_RELEASE="${2}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    # Set up some arrays for end reporting
    declare -a RELEASED_REPOSITORIES BUILT_REPOSITORIES

    # Get list of repositories
    # Sets: ${REPOSITORY_LIST_ARRAY[*]} ${REPOSITORY_BUILD_ARRAY[*]}  ${REPOSITORY_RELEASE_ARRAY[*]}  ${REPOSITORY_EXCLUDE_ARRAY[*]}
    get_repositories

    # Upload assets for release
    log_term 1 "\nUploading assets for release: \"${_RELEASE}\"" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#    $0 upload-assets "${_RELEASE}"

    # Release all non-infrastructure repositories
    # We do this first as nubis-builder needs to be released before building nubis-ci
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        local _COUNT=1
        for REPOSITORY in ${REPOSITORY_RELEASE_ARRAY[*]}; do
            log_term 1 "\nReleasing repository \"${REPOSITORY}\" at \"${_RELEASE}\". (${_COUNT} of ${#REPOSITORY_RELEASE_ARRAY[*]})" -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            release_repository "${REPOSITORY}" "${_RELEASE}"
            RELEASED_REPOSITORIES=( ${RELEASED_REPOSITORIES[*]} ${REPOSITORY} )
            let _COUNT=${_COUNT}+1
        done
        unset REPOSITORY _COUNT
    else
        log_term 1 "\nReleasing repository \"nubis-builder\" at \"${_RELEASE}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#        release_repository 'nubis-builder' "${_RELEASE}"; _RV=$?
        if [ ${_RV:-0} != '0' ]; then
            log_term 0 "\n!!!!! Releasing 'nubis-builder' failed failed. Inspect output logs. !!!!!" -e
            exit 1
        fi; unset _RV
        RELEASED_REPOSITORIES=( ${RELEASED_REPOSITORIES[*]} 'nubis-builder' )
    fi

    # Hack for aws-vault as server mode seems broken on Ubuntu
    # Expire any sessions for the build account and generate a new session
    # This should enable us to complete the builds before the session expires
    _VAULT_PROFILE=$(jq .variables.aws_vault_profile "${NUBIS_PATH}"/nubis-builder/secrets/variables.json)
    _VAULT_PROFILE=${_VAULT_PROFILE##\"}; _VAULT_PROFILE=${_VAULT_PROFILE%%\"}
    _VAULT_ACCOUNT=$(echo "${_VAULT_PROFILE}" | cut -d'-' -f 1,2)
    aws-vault rm -s "${_VAULT_ACCOUNT}"
    aws-vault exec "${_VAULT_PROFILE}" -- aws ec2 describe-regions 1>&2 > /dev/null
    unset _VAULT_PROFILE _VAULT_ACCOUNT

    # Build and release nubis-base
    # All other infrastructure builds are built from nubis-base, we need to build it first
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        log_term 1 "\nBuild and Release \"nubis-base\" at \"${_RELEASE}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        parallel --no-notice --output-as-files --results logs $0 -vv --non-interactive build-and-release {1} "${_RELEASE}" ::: 'nubis-base'
        if [ $? != '0' ]; then
            log_term 0 "Build for 'nubis-base' failed. Unable to continue."
            log_term 0 "Aborting....."
            exit 1
        fi
        BUILT_REPOSITORIES=( ${BUILT_REPOSITORIES[*]} 'nubis-base' )
        RELEASED_REPOSITORIES=( ${RELEASED_REPOSITORIES[*]} 'nubis-base' )
    else
        log_term 1 "\nBuild \"nubis-base\" at \"${_RELEASE}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        parallel --no-notice --output-as-files --results logs $0 -vv --non-interactive build {1} "${_RELEASE}" ::: 'nubis-base'
        if [ $? != '0' ]; then
            log_term 0 "Build for 'nubis-base' failed. Unable to continue."
            log_term 0 "Aborting....."
            exit 1
        fi
        BUILT_REPOSITORIES=( ${BUILT_REPOSITORIES[*]} 'nubis-base' )
    fi

    # Build and release all infrastructure components using the latest nubis-base
    test_for_parallel
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        log_term 1 "\nBuild and Release \"${#REPOSITORY_BUILD_ARRAY[*]}\" repositories at \"${_RELEASE}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        parallel --no-notice --output-as-files --results logs --progress --jobs "${#REPOSITORY_BUILD_ARRAY[*]}" $0 -vv --non-interactive build-and-release {1} "${_RELEASE}" ::: ${REPOSITORY_BUILD_ARRAY[*]}; _RV=$?
        if [ ${_RV:-0} != '0' ]; then
            log_term 0 "\n!!!!! ${_RV} builds failed failed. Inspect output logs. !!!!!" -e
        fi; unset _RV
        BUILT_REPOSITORIES=( ${BUILT_REPOSITORIES[*]} ${REPOSITORY_BUILD_ARRAY[*]} )
        RELEASED_REPOSITORIES=( ${RELEASED_REPOSITORIES[*]} ${REPOSITORY_BUILD_ARRAY[*]} )
    else
        log_term 1 "\nBuild \"${#REPOSITORY_BUILD_ARRAY[*]}\" repositories at \"${_RELEASE}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        parallel --no-notice --output-as-files --results logs --progress --jobs "${#REPOSITORY_BUILD_ARRAY[*]}" $0 -vv --non-interactive build {1} "${_RELEASE}" ::: ${REPOSITORY_BUILD_ARRAY[*]}; _RV=$?
        if [ ${_RV:-0} != '0' ]; then
            log_term 0 "\n!!!!! ${_RV} builds failed failed. Inspect output logs. !!!!!" -e
        fi; unset _RV
        BUILT_REPOSITORIES=( ${BUILT_REPOSITORIES[*]} ${REPOSITORY_BUILD_ARRAY[*]} )
    fi

    # List what we released and built
    log_term 1 "\nReleased ${#RELEASED_REPOSITORIES[*]} repositories: ${RELEASED_REPOSITORIES[*]}" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    log_term 1 "\nBuilt ${#BUILT_REPOSITORIES[*]} repositories: ${BUILT_REPOSITORIES[*]}" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    unset RELEASED_REPOSITORIES BUILT_REPOSITORIES
}
