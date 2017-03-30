#!/bin/bash

# This function is depricated as we no longer use CloudFormation
# # Upload nubis-stacks to release folder
# upload_stacks () {
#     local _RELEASE="${1}"
#     if [ ${_RELEASE:-NULL} == 'NULL' ]; then
#         log_term 0 "Relesae number required"
#         log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#         $0 help
#         exit 1
#     fi
#
#     test_for_jq
#     test_for_sponge
#
#     declare -a TEMPLATE_ARRAY
#     # Gather the list of templates from nubis-stacks
#     TEMPLATE_LIST=$(ls ${REPOSITORY_PATH}/nubis-stacks/*.template)
#     # Format the list into an array
#     for TEMPLATE in ${TEMPLATE_LIST}; do
#         TEMPLATE_ARRAY=( ${TEMPLATE_ARRAY[*]} $TEMPLATE )
#     done
#     unset TEMPLATE
#
#     # Gather the list of VPC templates from nubis-stacks
#     TEMPLATE_LIST=$(ls ${REPOSITORY_PATH}/nubis-stacks/vpc/*.template)
#     # Format the list into an array
#     for TEMPLATE in ${TEMPLATE_LIST}; do
#         TEMPLATE_ARRAY=( ${TEMPLATE_ARRAY[*]} $TEMPLATE )
#     done
#     unset TEMPLATE
#
#     local _COUNT=1
#     for TEMPLATE in ${TEMPLATE_ARRAY[*]}; do
#         local _EDIT_VERSION=$(cat ${TEMPLATE} | jq --raw-output '"\(.Parameters.StacksVersion.Default)"')
#         if [ ${_EDIT_VERSION:-0} != "null" ]; then
#             log_term 1 -e "Updating StacksVersion in \"${TEMPLATE}\". (${_COUNT} of ${#TEMPLATE_ARRAY[*]})"
#             log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#             cat "${TEMPLATE}" | jq ".Parameters.StacksVersion.Default|=\"${_RELEASE}\"" | sponge "${TEMPLATE}"
#         else
#             log_term 1 -e "StacksVersion unset in \"${TEMPLATE}\". (${_COUNT} of ${#TEMPLATE_ARRAY[*]})"
#             log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#         fi
#         let _COUNT=${_COUNT}+1
#     done
#     unset TEMPLATE
#
#     cd ${REPOSITORY_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push
#     if [ $? != '0' ]; then
#         log_term 0 "Uploads for ${_RELEASE} failed."
#         log_term 0 "Aborting....."
#         log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
#         exit 1
#     fi
#     check_in_changes 'nubis-stacks' "Update StacksVersion for ${RELEASE} release"
# }

upload_lambda_functions () {
    local _REPOSITORY='nubis-stacks'
    local _RELEASE="${1}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi

    # Ensure the repository exists in the repository path
    if [ ! -d "${REPOSITORY_PATH}"/"${_REPOSITORY}" ]; then
        log_term 1 "Repository '${_REPOSITORY}' not cheked out out in repository path '${REPOSITORY_PATH}'!"
        log_term 1 "\nCloning repository: \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

        # Check to see if we have a latest release on GitHub
#        local _LATEST_RELEASE_TAG; _LATEST_RELEASE_TAG=$(curl -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" --request GET https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/releases/latest | jq --raw-output .tag_name)

        # If we got a latest release, check it out, otherwise use the develop branch
        cd "${REPOSITORY_PATH}" || exit 1
        if [ "${_LATEST_RELEASE_TAG:-null}" != 'null' ]; then
            clone_repository "${_REPOSITORY}" "${_LATEST_RELEASE_TAG}"
        else
            clone_repository "${_REPOSITORY}"
        fi
    fi

    # Run the upload_to_s3 script from the nubis-stacks repository
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1
    "${AWS_VAULT_COMMAND[@]}" bin/upload_to_s3 --profile "${PROFILE}" -m --path "${_RELEASE}" push-lambda
    if [ $? != '0' ]; then
        log_term 0 "Uploads for ${_RELEASE} failed. Aborting..."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi

    # push-lambda fetches dependancies and generates new zip files, check them in here
    #+ unless we are on master or develop (assume these are test builds)
    local _CURRENT_BRANCH; _CURRENT_BRANCH=$(git branch | cut -d' ' -f 2)
    declare -a SKIP_BRANCHES=( 'master' 'develop' )
    if [[ ! " ${SKIP_BRANCHES[@]} " =~ ${_CURRENT_BRANCH} ]]; then
        check_in_changes "${_REPOSITORY}" "Updated lambda function bundles for ${_RELEASE} release"
    fi
    unset SKIP_BRANCHES
}
