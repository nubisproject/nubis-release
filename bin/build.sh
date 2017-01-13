#!/bin/bash
#
# These functions drive nubis-builder
#

# Clean up any librarian-puppet files
clean_librarian_puppet () {
    local _REPOSITORY="${2}"
    if [ ${_REPOSITORY:-NULL} == 'NULL' ]; then
        log_term 0 "Repository required"
        $0 help
        exit 1
    fi
    if [ -f "${NUBIS_PATH}/${_REPOSITORY}/nubis/Puppetfile" ]; then
        log_term 1 "Cleaning librarian-puppet files..."
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
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        $0 help
        exit 1
    fi
    if [ ${_REPOSITORY:-NULL} == 'NULL' ]; then
        log_term 0 "Repository required"
        $0 help
        exit 1
    fi
    test_for_nubis_builder
    edit_main_json "${_RELEASE}" "${_REPOSITORY}"
    edit_project_json "${_RELEASE}" "${_REPOSITORY}"
    clean_librarian_puppet "${_REPOSITORY}"
    log_term 0 "Running nubis-builder...."
    exec 5>&1
    OUTPUT=$(cd "${NUBIS_PATH}/${_REPOSITORY}" && nubis-builder build | tee >(cat - >&5))
    if [ $? != '0' ]; then
# Timeout waiting for SSH
        log_term 0 "Build for ${_REPOSITORY} failed. Contine? [y/N]"
        read CONTINUE
        if [ ${CONTINUE:-n} == "N" ] || [ ${CONTINUE:-n} == "n" ]; then
            log_term 0 "Aborting....."
            exit 1
        fi
        continue
    fi
    exec 5>&-

    # Special hook for nubis-ci
    if [ ${_REPOSITORY:-NULL} == 'nubis-ci' ]; then
        edit_ci_template "${_RELEASE}"
    fi

    # Special hook for nubis-storage
    if [ ${_REPOSITORY:-NULL} == 'nubis-storage' ]; then
        AMI_ARTIFACT="${NUBIS_PATH}/${_REPOSITORY}/nubis/builder/artifacts/${RELEASE}/AMIs"
        local _US_EAST_1=$(cat ${AMI_ARTIFACT} | grep 'us-east-1' | cut -d ':' -f 2 | sed -e 's/^[[:space:]]*//')
        local _US_WEST_2=$(cat ${AMI_ARTIFACT} | grep 'us-west-2' | cut -d ':' -f 2 | sed -e 's/^[[:space:]]*//')
        edit_storage_template "${_RELEASE}" "${_US_EAST_1}" "${_US_WEST_2}"
    fi

    # Special hook for nubis-nat
    if [ ${_REPOSITORY:-NULL} == 'nubis-nat' ]; then
        AMI_ARTIFACT="${NUBIS_PATH}/${_REPOSITORY}/nubis/builder/artifacts/${RELEASE}/AMIs"
        local _US_EAST_1=$(cat ${AMI_ARTIFACT} | grep 'us-east-1' | cut -d ':' -f 2 | sed -e 's/^[[:space:]]*//')
        local _US_WEST_2=$(cat ${AMI_ARTIFACT} | grep 'us-west-2' | cut -d ':' -f 2 | sed -e 's/^[[:space:]]*//')
        edit_nat_template "${_RELEASE}" "${_US_EAST_1}" "${_US_WEST_2}"
    fi

    # nubis-builder outputs some build artifacts. Lets check them in here
    check_in_changes "${_REPOSITORY}" "Update builder artifacts for ${RELEASE} release"
}

build_infrastructure_amis () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        $0 help
        exit 1
    fi
    # Build a fresh copy of nubis-base first
    log_term 1 -e "\nBuilding AMIs for \"nubis-base\"."
    build_amis "${_RELEASE}" 'nubis-base'
    # Next build all of the infrastructure components form the fresh nubis-base
    local _COUNT=1
    for REPOSITORY in ${INFRASTRUCTURE_ARRAY[*]}; do
        if [[ " ${RELEASE_EXCLUDES[@]} " =~ " ${REPOSITORY} " ]]; then
            log_term 1 -e "\n Skipping \"${REPOSITORY}\" as it is in the excludes list. (${_COUNT} of ${#INFRASTRUCTURE_ARRAY[*]})"
            let COUNT=${_COUNT}+1
        else
            log_term 1 -e "\n Building AMIs for \"${REPOSITORY}\". (${_COUNT} of ${#INFRASTRUCTURE_ARRAY[*]})"
            build_amis "${_RELEASE}" "${REPOSITORY}"
            let _COUNT=${_COUNT}+1
        fi
    done
    unset REPOSITORY
}
