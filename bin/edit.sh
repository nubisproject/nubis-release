#!/bin/bash
# shellcheck disable=SC1117
#
# Here are all of the functions to edit various files during a release
#

# Update project_version to the current release
edit_project_json () {
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 edit help
        exit 1
    fi
    test_for_jq
    local _FILE="${REPOSITORY_PATH}/${_REPOSITORY}/nubis/builder/project.json"
    if [ -f "${_FILE}" ]; then
        local _EDIT_PROJECT_VERSION; _EDIT_PROJECT_VERSION=$(grep -c 'project_version' "${_FILE}")
        if [ "${_EDIT_PROJECT_VERSION:-0}" -ge 1 ]; then
            log_term 0 "Updating project_version in \"${_FILE}\"." -e
            # Preserve any build data appended to the version
            local _BUILD; _BUILD=$(jq --raw-output '"\(.variables.project_version)"' "${_FILE}" | cut -s -d'_' -f2-)
            local _EDIT_FILE; _EDIT_FILE=$(jq ".variables.project_version|=\"${_RELEASE}${_BUILD:+_${_BUILD}}\"" "${_FILE}")
            echo "${_EDIT_FILE}" > "${_FILE}"
        else
            if [ "${NON_INTERACTIVE:-NULL}" == 'NULL' ]; then
                log_term 0 "Variable project_version does not exist in \"${_FILE}\"." -e
                log_term 0  "Contine? [y/N]"
                read -r CONTINUE
            else
                log_term 1 "Variable project_version does not exist in \"${_FILE}\". Skipping edit." -e
                CONTINUE='y'
            fi
            if [ ${CONTINUE:-n} == "N" ] || [ ${CONTINUE:-n} == "n" ]; then
                log_term 0 "Aborting....."
                log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
                exit 1
            fi
            return
        fi
         local _EDIT_SOURCE; _EDIT_SOURCE=$(grep -c 'source_ami_project_version' "${_FILE}")
         if [ "${_EDIT_SOURCE:-0}" -ge 1 ]; then
             _EDIT_FILE=$(jq ".variables.source_ami_project_version|=\"${_RELEASE}\"" "${_FILE}")
            echo "${_EDIT_FILE}" > "${_FILE}"
         fi
    fi
}

# This is a special edit to update the pinned version number to the current $RELEASE for the consul and vpc modules in nubis-deploy
edit_deploy_templates () {
    local -r _RELEASE="${1}"
    local -r _GIT_SHA="${2}"
    local _REF
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 edit help
        exit 1
    fi
    if [ "${_GIT_SHA:-NULL}" == 'NULL' ]; then
        _REF="${_RELEASE}"
    else
        _REF="${_GIT_SHA}"
    fi

    ENTRY_PWD=$(pwd)

    local _VPC_FILE="${REPOSITORY_PATH}/nubis-deploy/modules/vpc/main.tf"

    # This matches a release (v1.3.0) a dev release (v1.3.0-dev) or master or develop
    local _RELEASE_REGEX="\(\(v\(0\|[1-9]\d*\)\.\(0\|[1-9]\d*\)\.\(0\|[1-9]\d*\)\(-dev\)\{0,1\}\)\|master\|develop\)"

    sed -i "s:nubis-consul//nubis/terraform?ref=${_RELEASE_REGEX}:nubis-consul//nubis/terraform?ref=${_REF}:g" "${_VPC_FILE}"

    sed -i "s:nubis-jumphost//nubis/terraform?ref=${_RELEASE_REGEX}:nubis-jumphost//nubis/terraform?ref=${_REF}:g" "${_VPC_FILE}"
    sed -i "s:nubis-fluent-collector//nubis/terraform?ref=${_RELEASE_REGEX}:nubis-fluent-collector//nubis/terraform?ref=${_REF}:g" "${_VPC_FILE}"
    sed -i "s:nubis-prometheus//nubis/terraform?ref=${_RELEASE_REGEX}:nubis-prometheus//nubis/terraform?ref=${_REF}:g" "${_VPC_FILE}"
    sed -i "s:nubis-ci//nubis/terraform?ref=${_RELEASE_REGEX}:nubis-ci//nubis/terraform?ref=${_REF}:g" "${_VPC_FILE}"
    sed -i "s:nubis-sso//nubis/terraform?ref=${_RELEASE_REGEX}:nubis-sso//nubis/terraform?ref=${_REF}:g" "${_VPC_FILE}"
    sed -i "s:nubis-terraform-vpn?ref=${_RELEASE_REGEX}:nubis-terraform-vpn?ref=${_REF}:g" "${_VPC_FILE}"
    sed -i "s:nubis-terraform//images?ref=${_RELEASE_REGEX}:nubis-terraform//images?ref=${_REF}:g" "${_VPC_FILE}"

    # Check in the edits
    #+ Unless we are on master or develop (assume these are test builds)
    local _CURRENT_BRANCH; _CURRENT_BRANCH=$(git branch | cut -d' ' -f 2)
    local _SKIP_BRANCHES="^(master|develop)$"
    local _RELEASE_REGEX="^(v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))-dev$"
    if [[ ! "${_CURRENT_BRANCH}" =~ ${_SKIP_BRANCHES} ]] || [[ "${_RELEASE}" =~ ${_RELEASE_REGEX} ]]; then
        cd "${REPOSITORY_PATH}"/'nubis-deploy' || exit 1
        if [ "${_CURRENT_BRANCH}" == 'develop' ]; then
            repository_set_permissions 'nubis-deploy' 'develop' 'unset'
        fi
        check_in_changes 'nubis-deploy' "Update pinned release version for ${_RELEASE} release"
        if [ "${_CURRENT_BRANCH}" == 'develop' ]; then
            repository_set_permissions 'nubis-deploy' 'develop'
        fi
    fi
    cd "${ENTRY_PWD}" || exit 0
}

modify () {
    # Grab and setup called options
    while [ "$1" != "" ]; do
        case $1 in
            -gs | --git-sha )
                # Specify a git sha to use as the current release
                GIT_SHA="${2}"
                shift
            ;;
            -p | --path )
                # The path to where repository is checked out
                REPOSITORY_PATH="${2}"
                shift
            ;;
            -r | --release )
                # Specify a release number for the current release
                RELEASE="${2}"
                shift
            ;;
            -R | --repository )
                # Specify a repository to edit project.json
                REPOSITORY="${2}"
                shift
            ;;
            -h | -H | --help )
                echo -en "\n$0\n\n"
                echo -en "Usage: $0 edit --release 'vX.X.X' [options] command\n\n"
                echo -en "Commands:\n"
                echo -en "  nubis-deploy    Edit version string for files in nubis-deploy\n"
                echo -en "  project-json    Edit JSON file for current project\n\n"
                echo -en "Options:\n"
                echo -en "  --help         -h    Print this help information and exit\n"
                echo -en "  --path         -p    The path to where repository is checked out\n"
                echo -en "  --release      -r    Specify a release number for the current release\n"
                echo -en "  --repository   -R    Specify a repository to edit project.json\n"
                echo -en "  --git-sha      -gs   Specify a git sha to use as the current release\n"
                echo -en "                         This overrides the release number in nubis-deploy only\n\n"
                exit 0
            ;;
            nubis-deploy )
                # Edit version string for files in nubis-deploy
                edit_deploy_templates "${RELEASE}" "${GIT_SHA}"
                GOT_COMMAND=1
            ;;
            project-json )
                # Edit JSON file for current project
                edit_project_json "${RELEASE}" "${REPOSITORY}"
                GOT_COMMAND=1
            ;;
        esac
        shift
    done

    # If we did not get a valid command print the help message
    if [ ${GOT_COMMAND:-0} == 0 ]; then
        $0 edit --help
    fi
}
