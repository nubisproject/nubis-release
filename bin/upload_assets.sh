#!/bin/bash

# Upload nubis-stacks to release folder
upload_stacks () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi

    test_for_jq
    test_for_sponge

    declare -a TEMPLATE_ARRAY
    # Gather the list of templates from nubis-stacks
    TEMPLATE_LIST=$(ls ${NUBIS_PATH}/nubis-stacks/*.template)
    # Format the list into an array
    for TEMPLATE in ${TEMPLATE_LIST}; do
        TEMPLATE_ARRAY=( ${TEMPLATE_ARRAY[*]} $TEMPLATE )
    done
    unset TEMPLATE

    # Gather the list of VPC templates from nubis-stacks
    TEMPLATE_LIST=$(ls ${NUBIS_PATH}/nubis-stacks/vpc/*.template)
    # Format the list into an array
    for TEMPLATE in ${TEMPLATE_LIST}; do
        TEMPLATE_ARRAY=( ${TEMPLATE_ARRAY[*]} $TEMPLATE )
    done
    unset TEMPLATE

    local _COUNT=1
    for TEMPLATE in ${TEMPLATE_ARRAY[*]}; do
        local _EDIT_VERSION=$(cat ${TEMPLATE} | jq --raw-output '"\(.Parameters.StacksVersion.Default)"')
        if [ ${_EDIT_VERSION:-0} != "null" ]; then
            log_term 1 -e "Updating StacksVersion in \"${TEMPLATE}\". (${_COUNT} of ${#TEMPLATE_ARRAY[*]})"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            cat "${TEMPLATE}" | jq ".Parameters.StacksVersion.Default|=\"${_RELEASE}\"" | sponge "${TEMPLATE}"
        else
            log_term 1 -e "StacksVersion unset in \"${TEMPLATE}\". (${_COUNT} of ${#TEMPLATE_ARRAY[*]})"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        fi
        let _COUNT=${_COUNT}+1
    done
    unset TEMPLATE

    cd ${NUBIS_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push
    if [ $? != '0' ]; then
        log_term 0 "Uploads for ${_RELEASE} failed."
        log_term 0 "Aborting....."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    check_in_changes 'nubis-stacks' "Update StacksVersion for ${RELEASE} release"
}

upload_lambda_functions () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    cd ${NUBIS_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push-lambda
    if [ $? != '0' ]; then
        log_term 0 "Uploads for ${_RELEASE} failed."
        log_term 0 "Aborting....."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    check_in_changes 'nubis-stacks' "Updated lambda function bundles for ${RELEASE} release"
}
