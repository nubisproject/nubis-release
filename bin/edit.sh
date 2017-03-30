#!/bin/bash
#
# Here are all of the functions to edit various files during a release
#

# Update project_versoin to the current release
edit_project_json () {
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
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
    local _RELEASE="${1}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi

    local _CONSUL_FILE="${REPOSITORY_PATH}/nubis-deploy/modules/consul/main.tf"
    local _VPC_FILE="${REPOSITORY_PATH}/nubis-deploy/modules/vpc/main.tf"

    sed -i "s:nubis-consul//nubis/terraform/multi?ref=v[0-9].[0-9].[0-9]*:nubis-consul//nubis/terraform/multi?ref=${_RELEASE}:g" "${_CONSUL_FILE}"

    sed -i "s:nubis-jumphost//nubis/terraform?ref=v[0-9].[0-9].[0-9]*:nubis-jumphost//nubis/terraform?ref=${_RELEASE}:g" "${_VPC_FILE}"
    sed -i "s:nubis-fluent-collector//nubis/terraform/multi?ref=v[0-9].[0-9].[0-9]*:nubis-fluent-collector//nubis/terraform/multi?ref=${_RELEASE}:g" "${_VPC_FILE}"
    sed -i "s:nubis-prometheus//nubis/terraform?ref=v[0-9].[0-9].[0-9]*:nubis-prometheus//nubis/terraform?ref=${_RELEASE}:g" "${_VPC_FILE}"
    sed -i "s:nubis-ci//nubis/terraform?ref=v[0-9].[0-9].[0-9]*:nubis-ci//nubis/terraform?ref=${_RELEASE}:g" "${_VPC_FILE}"

    # Check in the edits
    #+ Unless we are on master or develop (assume these are test builds)
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1
    local _CURRENT_BRANCH; _CURRENT_BRANCH=$(git branch | cut -d' ' -f 2)
    declare -a SKIP_BRANCHES=( 'master' 'develop' )
    if [[ ! " ${SKIP_BRANCHES[@]} " =~ ${_CURRENT_BRANCH} ]]; then
        check_in_changes 'nubis-deploy' "Update pinned release version for ${_RELEASE} release"
    fi
    unset SKIP_BRANCHES
}

# This function is depricated as nubis-builder is on its own release cadance now
# This is a special edit to update the pinned version number to the current $RELEASE for nubis-ci
# edit_ci_template () {
#     local _RELEASE="${1}"
#     if [ ${_RELEASE:-NULL} == 'NULL' ]; then
#         log_term 0 "Relesae number required"
#         log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#         $0 help
#         exit 1
#     fi
#
#     local _CI_FILE="${REPOSITORY_PATH}/nubis-ci/nubis/puppet/builder.pp"
#
#     sed -i "s:revision => 'v[0-9].[0-9].[0-9]*',:revision => '${_RELEASE}',:g" "${_CI_FILE}"
# }
