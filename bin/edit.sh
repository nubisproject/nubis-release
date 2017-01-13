#!/bin/bash
#
# Here are all of the functions to edit various files during a release
#

# Update StacksVersion to the current release
edit_main_json () {
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        $0 help
        exit 1
    fi
    test_for_jq
    test_for_sponge
    # Necessary to skip older repositories that are still using Terraform for deployments
    #+ Just silently skip the edit
    local _FILE="${NUBIS_PATH}/${_REPOSITORY}/nubis/cloudformation/main.json"
    if [ -f "${_FILE}" ]; then
        local _EDIT_VERSION=$(cat ${_FILE} | grep -c 'StacksVersion')
        if [ ${_EDIT_VERSION:-0} -ge 1 ]; then
            log_term 0 -e "Updating StacksVersion in \"${_FILE}\"."
            cat "${_FILE}" | jq ".Parameters.StacksVersion.Default|=\"${_RELEASE}\"" | sponge "${_FILE}"
        fi
    fi
}

# Update project_versoin to the current release
edit_project_json () {
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        $0 help
        exit 1
    fi
    test_for_jq
    test_for_sponge
    local _FILE="${NUBIS_PATH}/${_REPOSITORY}/nubis/builder/project.json"
    if [ -f "${_FILE}" ]; then
        local _EDIT_PROJECT_VERSION=$(cat ${_FILE} | grep -c 'project_version')
        if [ ${_EDIT_PROJECT_VERSION:-0} -ge 1 ]; then
            log_term 0 -e "Updating project_version in \"${_FILE}\"."
            # Preserve any build data appended to the version 
            local _BUILD=$(cat ${_FILE} | jq --raw-output '"\(.variables.project_version)"' | cut -s -d'_' -f2-)
            cat "${_FILE}" | jq ".variables.project_version|=\"${_RELEASE}${_BUILD:+_${_BUILD}}\"" | sponge "${_FILE}"
        else
            log_term 0 -e "Variable project_version does not exist in \"${_FILE}\"."
            echo "Contine? [y/N]"
            read CONTINUE
            if [ ${CONTINUE:-n} == "N" ] || [ ${CONTINUE:-n} == "n" ]; then
                log_term 0 "Aborting....."
                exit 1
            fi
            continue
        fi
        local _EDIT_SOURCE=$(cat ${_FILE} | grep -c 'source_ami_project_version')
        if [ ${_EDIT_SOURCE:-0} -ge 1 ]; then
            cat "${_FILE}" | jq ".variables.source_ami_project_version|=\"${_RELEASE}\"" | sponge "${_FILE}"
        fi
    fi
}

# This is a special edit to update an AMI mapping in nubis-storage and copy that template to nubis-stacks
edit_storage_template () {
    local _RELEASE="${1}"
    local _US_EAST_1="${2}"
    local _US_WEST_2="${3}"
    local _FILE="${NUBIS_PATH}/nubis-storage/nubis/cloudformation/main.json"
    cat "${_FILE}" |\
    jq ".Mappings.AMIs.\"us-west-2\".AMI |=\"${_US_WEST_2}\"" |\
    jq ".Mappings.AMIs.\"us-east-1\".AMI |=\"${_US_EAST_1}\"" |\
    sponge "${_FILE}"

    # Copy the storage template to nubis-stacks as the templates should remain identical
    cp "${_FILE}" "${NUBIS_PATH}/nubis-stacks/storage.template"

    check_in_changes 'nubis-stacks' "Update storage AMI Ids for ${_RELEASE} release" 'storage.template'

    log_term 0 "Uploading updated storage.template to S3."
    cd ${NUBIS_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push storage.template
}

# This is a special edit to update an AMI mapping in nubis-nat in nubis-stacks
edit_nat_template () {
    local _RELEASE="${1}"
    local _US_EAST_1="${2}"
    local _US_WEST_2="${3}"
    local _FILE="${NUBIS_PATH}/nubis-stacks/vpc/vpc-nat.template"

    if [ -f ${_FILE} ]; then
        cat "${_FILE}" |\
        jq ".Mappings.AMIs.\"us-west-2\".AMIs |=\"${_US_WEST_2}\"" |\
        jq ".Mappings.AMIs.\"us-east-1\".AMIs |=\"${_US_EAST_1}\"" |\
        sponge "${_FILE}"

        check_in_changes 'nubis-stacks' "Update nat AMI Ids for ${_RELEASE} release" 'vpc/vpc-nat.template'

        log_term 1 "Uploading updated vpc/vpc-nat.template to S3."
        cd ${NUBIS_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push vpc/vpc-nat.template
    fi
}

# This is a special edit to update the pinned version number to the current $RELEASE for the consul and vpc modules in nubis-deploy
edit_deploy_templates () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        $0 help
        exit 1
    fi

    local _CONSUL_FILE="${NUBIS_PATH}/nubis-deploy/modules/consul/main.tf"
    local _VPC_FILE="${NUBIS_PATH}/nubis-deploy/modules/vpc/main.tf"

    sed "s:nubis-consul//nubis/terraform/multi?ref=v[0-9].[0-9].[0-9]*:nubis-consul//nubis/terraform/multi?ref=${_RELEASE}:g" "${_CONSUL_FILE}" |\
    sponge "${_CONSUL_FILE}"

    sed "s:nubis-jumphost//nubis/terraform?ref=v[0-9].[0-9].[0-9]*:nubis-jumphost//nubis/terraform?ref=${_RELEASE}:g" "${_VPC_FILE}" |\
    sponge "${_VPC_FILE}"
    sed "s:nubis-fluent-collector//nubis/terraform/multi?ref=v[0-9].[0-9].[0-9]*:nubis-fluent-collector//nubis/terraform/multi?ref=${_RELEASE}:g" "${_VPC_FILE}" |\
    sponge "${_VPC_FILE}"

    check_in_changes 'nubis-deploy' "Update pinned release version for ${_RELEASE} release"
}

# This is a special edit to update the pinned version number to the current $RELEASE for nubis-ci
edit_ci_template () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        $0 help
        exit 1
    fi

    local _CI_FILE="${NUBIS_PATH}/nubis-ci/nubis/puppet/builder.pp"

    sed "s:revision => 'v[0-9].[0-9].[0-9]*',:revision => '${_RELEASE}',:g" "${_CI_FILE}" |\
    sponge "${_CI_FILE}"
}
