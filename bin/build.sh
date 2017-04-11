#!/bin/bash
#
# These functions drive nubis-builder
#

# Clean up any librarian-puppet files
clean_librarian_puppet () {
    local _REPOSITORY="${1}"
    if [ "${_REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "$0" help
        exit 1
    fi
    if [ -f "${REPOSITORY_PATH}/${_REPOSITORY}/nubis/Puppetfile" ]; then
        log_term 1 "Cleaning librarian-puppet files..."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exec 5>&1
        OUTPUT=$(cd "${REPOSITORY_PATH}/${_REPOSITORY}" && librarian-puppet clean | tee >(cat - >&5))
        if [ -f "${REPOSITORY_PATH}/${_REPOSITORY}/nubis/Puppetfile.lock" ]; then
            OUTPUT=$(rm "${REPOSITORY_PATH}/${_REPOSITORY}/nubis/Puppetfile.lock" | tee >(cat - >&5))
        fi
        exec 5>&-
    fi
}

# Build new AMIs for the named repository
build_amis () {
    test_for_nubis_builder
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    if [ "${_REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "$0" help
        exit 1
    fi
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "$0" help
        exit 1
    fi
    # Ensure the repository exists in the repository path
    # This will check out the develop branch
    if [ ! -d "${REPOSITORY_PATH}"/"${_REPOSITORY}" ]; then
        log_term 1 "Repository '${_REPOSITORY}' not chekcout out in repository path '${REPOSITORY_PATH}'!"
        log_term 1 "\nCloning repository: \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        clone_repository "${_REPOSITORY}"
    fi

    edit_project_json "${_RELEASE}" "${_REPOSITORY}"
    clean_librarian_puppet "${_REPOSITORY}"

    log_term 0 "Running nubis-builder for ${_REPOSITORY}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    exec 5>&1
    cd "${REPOSITORY_PATH}/${_REPOSITORY}" || exit 1
    OUTPUT=$(nubis-builder build --spot --instance-type c3.large | tee >(cat - >&5))
    if [ $? != '0' ]; then
        if [ "${NON_INTERACTIVE:-NULL}" == 'NULL' ]; then
            log_term 0 "Build for ${_REPOSITORY} failed. Contine? [y/N]"
            read -r CONTINUE
            if [ "${CONTINUE:-n}" == "N" ] || [ "${CONTINUE:-n}" == "n" ]; then
                log_term 0 "Aborting....."
                exit 1
            fi
            return
        else
            log_term 0 "Build for ${_REPOSITORY} failed."
            log_term 0 "Aborting....."
            echo "$OUTPUT"
            exit 1
        fi
    fi
    exec 5>&-

    echo "$OUTPUT"

    # nubis-builder outputs some build artifacts. Lets check them in here
    #+ unless we are on master or develop (assume these are test builds)
    #+ If we are on develop and it is a dev build (vX.X.X-dev) check in also
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1
    local _CURRENT_BRANCH; _CURRENT_BRANCH=$(git branch | cut -d' ' -f 2)
    local _SKIP_BRANCHES="^(master|develop)$"
    local _RELEASE_REGEX="^(v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))-dev$"
    if [[ ! "${_CURRENT_BRANCH}" =~ ${_SKIP_BRANCHES} ]] || [[ "${_RELEASE}" =~ ${_RELEASE_REGEX} ]]; then
        if [ "${_CURRENT_BRANCH}" == 'develop' ]; then
            repository_set_permissions "${_REPOSITORY}" 'develop' 'unset'
        fi
        check_in_changes "${_REPOSITORY}" "Update builder artifacts for ${_RELEASE} release"
        if [ "${_CURRENT_BRANCH}" == 'develop' ]; then
            repository_set_permissions "${_REPOSITORY}" 'develop'
        fi
    fi
}

build_and_release_all () {
    test_for_parallel
    local _RELEASE="${1}"
    local _SKIP_RELEASE="${2}"
    local _SKIP_SETUP="${3}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "$0" help
        exit 1
    fi
    # Set up some arrays for end reporting
    declare -a RELEASED_REPOSITORIES BUILT_REPOSITORIES

    # Get list of repositories
    # Sets: ${REPOSITORY_LIST_ARRAY[*]} ${REPOSITORY_BUILD_ARRAY[*]}  ${REPOSITORY_RELEASE_ARRAY[*]}  ${REPOSITORY_EXCLUDE_ARRAY[*]}
    get_repositories

    # Release all non-infrastructure repositories
    local _RELEASE_REGEX="^(v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))-dev$"
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        local _COUNT=1
        for REPOSITORY in ${REPOSITORY_RELEASE_ARRAY[*]}; do
            log_term 1 "\nReleasing repository \"${REPOSITORY}\" at \"${_RELEASE}\". (${_COUNT} of ${#REPOSITORY_RELEASE_ARRAY[*]})" -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            "$0" release  "${REPOSITORY}" "${_RELEASE}" "${_SKIP_SETUP}"
            RELEASED_REPOSITORIES=( ${RELEASED_REPOSITORIES[*]} ${REPOSITORY} )
            let _COUNT=${_COUNT}+1
        done
        unset REPOSITORY _COUNT
    # This is a special edit to update the pinned version number to 'develop' for terraform modules in nubis-deploy
    #+ We need to do this only if we are building a vX.X.X-dev release (See _RELEASE_REGEX above)
    elif [[ "${_RELEASE}" =~ ${_RELEASE_REGEX} ]]; then
        edit_deploy_templates "${_RELEASE}" 'develop'
    fi

    # Upload assets for release
    # This needs to hapen after the above repositories are released
    #+ as it fetches the latest nubis-stacks release
    log_term 1 "\nUploading assets for release: \"${_RELEASE}\"" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    "$0" upload-assets "${_RELEASE}"

    # Hack for aws-vault as server mode seems broken on Ubuntu
    # Expire any sessions for the build account and generate a new session
    # This should enable us to complete the builds before the session expires
    NUBIS_BUILDER_PATH="$(dirname "$(dirname "$(readlink -f "$(which nubis-builder)")")")"
    _VAULT_PROFILE=$(jq .variables.aws_vault_profile "${NUBIS_BUILDER_PATH}"/secrets/variables.json)
    _VAULT_PROFILE=${_VAULT_PROFILE##\"}; _VAULT_PROFILE=${_VAULT_PROFILE%%\"}
    _VAULT_ACCOUNT=$(echo "${_VAULT_PROFILE}" | cut -d'-' -f 1,2)
    aws-vault rm -s "${_VAULT_ACCOUNT}"
    aws-vault exec "${_VAULT_PROFILE}" -- aws ec2 describe-regions > /dev/null || exit 1
    unset _VAULT_PROFILE _VAULT_ACCOUNT

    log_term 0 '\nIf you care to monitor the build progress:' -e
    log_term 0 'tail -f logs/1/*/stdout logs/1/*/stderr'

    # Build and release nubis-base
    # All other infrastructure builds are built from nubis-base, we need to build it first
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        log_term 1 "\nBuild and Release \"nubis-base\" at \"${_RELEASE}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        parallel --no-notice --output-as-files --results logs "$0" -vv --non-interactive build-and-release '{1}' "${_RELEASE}"  "${_SKIP_SETUP}" ::: 'nubis-base'
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
        parallel --no-notice --output-as-files --results logs "$0" -vv --non-interactive build '{1}' "${_RELEASE}" ::: 'nubis-base'
        if [ $? != '0' ]; then
            log_term 0 "Build for 'nubis-base' failed. Unable to continue."
            log_term 0 "Aborting....."
            exit 1
        fi
        BUILT_REPOSITORIES=( ${BUILT_REPOSITORIES[*]} 'nubis-base' )
    fi

    # AWS is slow to propogate the AMI ID of nubis-base, lets sleep for a while
    #+ Should search for the AMI ID and continue once we see it
    sleep 60

    # Build and release all infrastructure components using the latest nubis-base
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        log_term 1 "\nBuild and Release \"${#REPOSITORY_BUILD_ARRAY[*]}\" repositories at \"${_RELEASE}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        parallel --no-notice --output-as-files --results logs --progress --jobs "${#REPOSITORY_BUILD_ARRAY[@]}" "$0" -vv --non-interactive build-and-release '{1}' "${_RELEASE}"  "${_SKIP_SETUP}" ::: "${REPOSITORY_BUILD_ARRAY[@]}"; _RV=$?
        if [ ${_RV:-0} != '0' ]; then
            log_term 0 "\n!!!!! ${_RV} builds failed failed. Inspect output logs. !!!!!" -e
        fi; unset _RV
        BUILT_REPOSITORIES=( ${BUILT_REPOSITORIES[*]} ${REPOSITORY_BUILD_ARRAY[*]} )
        RELEASED_REPOSITORIES=( ${RELEASED_REPOSITORIES[*]} ${REPOSITORY_BUILD_ARRAY[*]} )
    else
        log_term 1 "\nBuild \"${#REPOSITORY_BUILD_ARRAY[*]}\" repositories at \"${_RELEASE}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        parallel --no-notice --output-as-files --results logs --progress --jobs "${#REPOSITORY_BUILD_ARRAY[@]}" "$0" -vv --non-interactive build '{1}' "${_RELEASE}" ::: "${REPOSITORY_BUILD_ARRAY[@]}"; _RV=$?
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

patch_release_setup () {
    test_for_parallel
    local _RELEASE="${1}"
    local _GIT_REF="${2}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "$0" help
        exit 1
    fi
    if [ "${_GIT_REF:-NULL}" == 'NULL' ]; then
        log_term 0 "Git ref required for patch setup"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "$0" help
        exit 1
    fi
    # Get list of repositories
    # Sets: ${REPOSITORY_LIST_ARRAY[*]} ${REPOSITORY_BUILD_ARRAY[*]}  ${REPOSITORY_RELEASE_ARRAY[*]}  ${REPOSITORY_EXCLUDE_ARRAY[*]}
    get_repositories

    # Clone all relevant repositories
    if [ "${_SKIP_RELEASE:-NULL}" == "NULL" ]; then
        declare -a REPOSITORY_ALL_RELEASE_ARRAY=( ${REPOSITORY_BUILD_ARRAY[*]}  ${REPOSITORY_RELEASE_ARRAY[*]} )
        local _COUNT=1
        for REPOSITORY in ${REPOSITORY_ALL_RELEASE_ARRAY[*]}; do
            log_term 1 "\nCloning repository \"${REPOSITORY}\" for \"${_RELEASE}\" at \"${_GIT_REF}\". (${_COUNT} of ${#REPOSITORY_RELEASE_ARRAY[*]})" -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            $0 setup-release "${REPOSITORY}" "${_RELEASE}" "${_GIT_REF}"
            let _COUNT=${_COUNT}+1
        done
        unset REPOSITORY_ALL_RELEASE_ARRAY REPOSITORY _COUNT
    fi
}
