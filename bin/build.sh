#!/bin/bash
# shellcheck disable=SC1117
#
# These functions drive nubis-builder
#

# Build new AMIs for the named repository
build_amis () {
    test_for_docker
    local -r _REPOSITORY="${1}"
    local -r _RELEASE="${2}"
    local -r _SKIP_CLONE="${3}"
    if [ "${_REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "$0" help
        exit 1
    fi
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Release number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        "$0" help
        exit 1
    fi
    # Ensure the repository exists in the repository path
    # If we are releaseing, the clone (and branching) has been done already
    #+ In that case we skip the clone here.
    # This will check out the develop or patch branch
    if [ "${_SKIP_CLONE:-NULL}" == 'NULL' ]; then
        log_term 1 "\nCloning repository: \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        clone_repository "${_REPOSITORY}" || exit 1
    fi

    edit_project_json "${_RELEASE}" "${_REPOSITORY}"

    log_term 0 "Running nubis-builder for ${_REPOSITORY}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    exec 5>&1
    cd "${REPOSITORY_PATH}/${_REPOSITORY}" || exit 1
    # Make this command a bit more readable
    #+ NOTE: NUBIS_BUILDER_VERSION and AMI_COPY_REGIONS are set in the top level variables file
    NUBIS_DOCKER=( 'docker' 'run' '-rm' \
                '-u' "$UID:$(id -g)" \
                '--env-file' '/nubis/bin/docker_env' \
                '--mount' 'source=nubis-release,target=/nubis/data' \
                '-e' "GIT_COMMIT_SHA=$(git rev-parse HEAD)" \
                "nubisproject/nubis-builder:${NUBIS_BUILDER_VERSION}" \
                '--volume-path' "${_REPOSITORY}" \
                '--copy-regions' "${AMI_COPY_REGIONS}" \
                'build' \
                '--instance-type' 'c3.large' )
    OUTPUT=$("${NUBIS_DOCKER[@]}" | tee >(cat - >&5))
    # https://github.com/koalaman/shellcheck/wiki/SC2181
    # shellcheck disable=SC2181
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
    local -r _SKIP_BRANCHES="^(master|develop)$"
    local -r _RELEASE_REGEX="^(v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))-dev$"
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
