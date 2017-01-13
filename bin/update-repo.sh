#!/bin/bash
#
# git clone git@github.com:tinnightcap/nubis-proxy.git
# git remote -vv
#    origin  git@github.com:tinnightcap/nubis-proxy.git (fetch)
#    origin  git@github.com:tinnightcap/nubis-proxy.git (push)
# git remote rename origin tinnightcap
# git remote add -f origin git@github.com:Nubisproject/nubis-proxy.git
# git remote -vv
#    origin  git@github.com:Nubisproject/nubis-proxy.git (fetch)
#    origin  git@github.com:Nubisproject/nubis-proxy.git (push)
#    tinnightcap     git@github.com:tinnightcap/nubis-proxy.git (fetch)
#    tinnightcap     git@github.com:tinnightcap/nubis-proxy.git (push)
# git branch -vv
#    * master 017748c [tinnightcap/master] Initial commit
# git checkout --track origin/master -b originmaster
# git branch -vv
#      master       017748c [tinnightcap/master] Initial commit
#    * originmaster 017748c [origin/master] Initial commit
#


# TODO, tag nubis-builder before building [nubis-ci]/nubis/puppet/builder.pp
# TODO: if a nubis/Puppetfile exists do the librarian-puppet dance (nubis-nat - edit versions)
# TODO: Close release issues
# TODO: If nubis-deploy terraform modules are pinned to master (not a version) they will not be caught by these regexes.


NUBIS_PATH='/home/jason/projects/mozilla/projects/nubis'
GITHUB_LOGIN='tinnightcap'
GITHUB_ORGINIZATION='nubisproject'
PROFILE='nubis-market-admin'
AWS_VAULT_COMMAND="aws-vault --backend=kwallet exec --assume-role-ttl=60m $PROFILE --"
set -o pipefail

# List of repositories that will be excluded form the release
declare -a RELEASE_EXCLUDES=(nubis-accounts-nubis nubis-accounts-webops nubis-ci nubis-elasticsearch nubis-elk nubis-ha-nat nubis-junkheap nubis-mediawiki nubis-meta nubis-proxy nubis-puppet-storage nubis-puppet-nat nubis-puppet-nsm nubis-puppet-mig nubis-puppet-eip nubis-puppet-discovery nubis-puppet-consul_do nubis-puppet-configuration nubis-puppet-envconsul nubis-puppet-consul-replicate nubis-siege nubis-storage nubis-vpc nubis-wrapper )

# List of infrastructure projects that need to be rebuilt from nubis-base during a release
#declare -a INFRASTRUCTURE_ARRAY=( nubis-ci nubis-consul nubis-dpaste nubis-fluent-collector nubis-jumphost nubis-mediawiki nubis-nat nubis-skel nubis-storage )
declare -a INFRASTRUCTURE_ARRAY=( nubis-consul nubis-dpaste nubis-fluent-collector nubis-jumphost nubis-nat nubis-prometheus nubis-skel )

declare -a REPOSITORY_ARRAY

test_for_ghi () {
    TEST=$(which ghi 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        echo "ghi must be installed and on your path!"
        echo "See: https://github.com/stephencelis/ghi"
        exit 1
    fi
}

test_for_nubis_builder () {
    TEST=$(which nubis-builder 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        echo "nubis-builder must be installed and on your path!"
        echo "See: https://github.com/Nubisproject/nubis-builder#builder-quick-start"
        exit 1
    fi
}

test_for_sponge () {
    TEST=$(which sponge 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        echo "sponge must be installed and on your path!"
        echo "sponge is provided by the 'moreutils' package on ubuntu"
        exit 1
    fi
}

test_for_jq () {
    TEST=$(which jq 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        echo "jq must be installed and on your path!"
        exit 1
    fi
}

test_for_github_changelog_generator () {
    TEST=$(which github_changelog_generator 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        echo "github_changelog_generator must be installed and on your path!"
        exit 1
    fi
}

get_repositories () {
    # Gather the list of repositories in the nubisproject from GitHub
    REPOSITORY_LIST=$(curl -s https://api.github.com/orgs/nubisproject/repos?per_page=100 | jq -r '.[].name' | sort)

    # Format the list into an array
    for REPO in ${REPOSITORY_LIST}; do
        REPOSITORY_ARRAY=( ${REPOSITORY_ARRAY[*]} $REPO )
    done
}

clone_repository () {
    TEST=$(hub --version 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        echo "hub must be installed and on your path!"
        echo "See: https://hub.github.com/"
        exit 1
    fi
    if [ ${REPOSITORY:-NULL} == 'NULL' ]; then
        echo "You must specify a repository!"
        exit 1
    fi
    if [ -d ${NUBIS_PATH}/${REPOSITORY} ]; then
        echo "Directory \"${NUBIS_PATH}/${REPOSITORY}\" already exists. Aborting!"
        exit 1
    fi
    cd ${NUBIS_PATH}
    SSH_URL=$(curl -s https://api.github.com/repos/nubisproject/${REPOSITORY} | jq -r '.ssh_url')
    git clone ${SSH_URL}
    cd ${REPOSITORY}
    hub fork
    git checkout --track origin/master -b originmaster
    git branch -d master
    git checkout --track ${GITHUB_LOGIN}/master -b master
}

update_repository () {
    if [ ${REPOSITORY:-NULL} == 'NULL' ]; then
        echo "You must specify a repository!"
        exit 1
    fi
    if [ ! -d ${NUBIS_PATH}/${REPOSITORY} ]; then
        echo " Repository \"${REPOSITORY}\" not found... Attempting to clone locally."
        clone_repository ${REPOSITORY}
    fi
    echo -e " #### Updating repository ${REPOSITORY} ####"
    cd ${NUBIS_PATH}/${REPOSITORY}
    git checkout master
    git fetch origin
    git rebase origin/master
    if [ $? != 0 ]; then
        echo -e "\n !!!!!!!! Repository '${REPOSITORY}' not updated! !!!!!!!!\n"
    else
        git push
    fi
}

update_all_repositories () {
    get_repositories
    COUNT=1
    for REPOSITORY in ${REPOSITORY_ARRAY[*]}; do
        echo -e "\n Updating ${COUNT} of ${#REPOSITORY_ARRAY[*]} repositories"
        update_repository ${REPOSITORY}
        let COUNT=${COUNT}+1
    done
}

get_set_milestone () {
    milestone_open () {
        ghi milestone --list -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" | grep "${_MILESTONE}" | cut -d':' -f 1 | sed -e 's/^[[:space:]]*//'
    }
    milestone_closed () {
        ghi milestone --list --closed -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" | grep "${_MILESTONE}" | cut -d':' -f 1 | sed -e 's/^[[:space:]]*//'
    }
    test_for_ghi
    local _MILESTONE="${1}"
    local _REPOSITORY="${2}"
    # First check to see if we have an open milestone
    _MILESTONE_NUMBER=$(milestone_open)
    if [ "${_MILESTONE_NUMBER:-NULL}" != 'NULL' ]; then
        echo "${_MILESTONE_NUMBER}"
        return
    fi
    # Next check to see if we have the milestone but it is closed
    _MILESTONE_NUMBER=$(milestone_closed)
    if [ "${_MILESTONE_NUMBER:-NULL}" != 'NULL' ]; then
        echo "${_MILESTONE_NUMBER}"
        return
    fi
    # Finally create the milestone as it does not appear to exist
    _MILESTONE_NUMBER=$(ghi milestone -m "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"  | cut -d'#' -f 2 | cut -d' ' -f 1)
    echo "${_MILESTONE_NUMBER}"
    return
}

create_milestones () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae nubber required"
        $0 help
        exit 1
    fi
    get_repositories
    local _COUNT=1
    for REPOSITORY in ${REPOSITORY_ARRAY[*]}; do
        if [[ " ${RELEASE_EXCLUDES[@]} " =~ " ${REPOSITORY} " ]]; then
            echo -e "\n Skipping \"${REPOSITORY}\" as it is in the excludes list. (${_COUNT} of ${#REPOSITORY_ARRAY[*]})"
            let COUNT=${_COUNT}+1
        else
            echo -e "\n Creating milestone in \"${REPOSITORY}\". (${_COUNT} of ${#REPOSITORY_ARRAY[*]})"
            local _RELEASE="${1}"
            local _MILESTONE=$(get_set_milestone "${_RELEASE}" "${REPOSITORY}")
            echo " Got milestone number \"${_MILESTONE}\"."
            let _COUNT=${_COUNT}+1
        fi
    done
    unset REPOSITORY
}

file_issue () {
    test_for_ghi
    local _REPOSITORY="${1}"
    local _ISSUE_TITLE="${2}"
    local _ISSUE_BODY="${3}"
    local _MILESTONE="${4}"
    ghi open --message "${_ISSUE_BODY}" "${_ISSUE_TITLE}" --milestone "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"
}

file_release_issues () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
        $0 help
        exit 1
    fi
    get_repositories
    local _COUNT=1
    for REPOSITORY in ${REPOSITORY_ARRAY[*]}; do
        if [[ " ${RELEASE_EXCLUDES[@]} " =~ " ${REPOSITORY} " ]]; then
            echo -e "\n Skipping \"${REPOSITORY}\" as it is in the excludes list. (${_COUNT} of ${#REPOSITORY_ARRAY[*]})"
            let COUNT=${COUNT}+1
        else
            echo -e "\n Filing release issue in \"${REPOSITORY}\". (${_COUNT} of ${#REPOSITORY_ARRAY[*]})"
            local _RELEASE="${1}"
            local _ISSUE_TITLE="Tag ${_RELEASE} release"
            local _ISSUE_BODY="Tag a release of the ${REPOSITORY} repository for the ${_RELEASE} release of the Nubis project."
            local _MILESTONE=$(get_set_milestone "${_RELEASE}" "${REPOSITORY}")
            file_issue "${REPOSITORY}" "${_ISSUE_TITLE}" "${_ISSUE_BODY}" "${_MILESTONE}"
            let _COUNT=${_COUNT}+1
        fi
    done
    unset REPOSITORY
}

merge_changes () {
    local _REPOSITORY=${1}
    echo "Merge pull-request? [y/N]"
    read CONTINUE
    if [ ${CONTINUE:-n} == "Y" ] || [ ${CONTINUE:-n} == "y" ]; then
        # Switch to the originmaster branch and merge the pull-request
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git checkout originmaster
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git pull
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git merge --no-ff master -m "Merge branch 'master' into originmaster"
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git push origin HEAD:master
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git checkout master
    fi
}

check_in_changes () {
    local _REPOSITORY=${1}
    local _MESSAGE=${2}
    local _FILE=${3}
    if [ ${_FILE:-NULL} == 'NULL' ]; then
        local _FILE='.'
    fi
    echo "Check in changes for \"${_REPOSITORY}\" to: \"${_FILE}\"? [Y/n]"
    read CONTINUE
    if [ ${CONTINUE:-y} == "Y" ] || [ ${CONTINUE:-y} == "y" ]; then
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git add ${_FILE}
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git commit -m "${_MESSAGE}"
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git push
        # GitHub is sometimes a bit slow here
        sleep 3
        cd "${NUBIS_PATH}/${_REPOSITORY}" && hub pull-request -m "${_MESSAGE}"

        merge_changes "${_REPOSITORY}"
    fi
}

install_rvm (){
    gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
    \curl -sSL https://get.rvm.io | bash -s stable
    source ~/.rvm/scripts/rvm
    rvm install 2.1
    rvm use 2.1
    sudo ln -s ~/.rvm/rubies/ruby-2.1.8/bin/ruby /usr/bin/ruby2.1
    gem install puppet
    gem install librarian-puppet
    gem install github_changelog_generator
#    gem install ghi
    rvm list
    rvm use 2.1
    gem list
    
    # The gem build is broken at the moment
    #+ This will grab the raw 1.2.0 version and install it in your home bin directory
    curl -sL https://raw.githubusercontent.com/stephencelis/ghi/b3abe43a0d62a50cadc825a12bd1b2e09e8bb059/ghi  > ghi
    chmod 755 ghi
    mv ghi ~/bin
    ghi --version
}

build_instructions () {
    TEST=$(which rvm 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        echo -e "\n\nNOTE: rvm is not installed on your path"
        echo -e "NOTE: try $0 install-rvm\n\n"
    fi
    echo "rvm use 2.1"
    echo "cd /home/jason/projects/mozilla/projects/nubis/nubis-base/nubis/ && librarian-puppet clean; cd -"
    echo "rm /home/jason/projects/mozilla/projects/nubis/nubis-base/nubis/Puppetfile.lock"
    echo "RELEASE='v1.1.0'"
    echo "$0 file-release \${RELEASE}"
    echo "$0 update-all"
    echo "$0 upload-stacks \${RELEASE}"
    echo "export AWS_VAULT_BACKEND=kwallet"
    echo "$0 build-infrastructure \${RELEASE}"
    echo "$0 release-all \${RELEASE}"
    echo "Take care of nubis-ci bullshit"
    echo "Update nubis-builder version to currentl release in:"
    echo "vi /home/jason/projects/mozilla/projects/nubis/nubis-ci/nubis/puppet/builder.pp"
    echo "$0 build nubis-ci \${RELEASE}"
    echo "$0 release nubis-ci \${RELEASE}"
    echo "Close all release issues"
    echo "https://github.com/issues?q=is%3Aissue+user%3ANubisproject+\${RELEASE}+in%3Atitle+is%3Aopen"
    echo "Update date range in generate_release_csv.sh"
    echo "vi ./generate_release_csv.sh"
    echo "./generate_release_csv.sh"
    echo "inport into milestone tracker at:"
    echo "https://docs.google.com/spreadsheets/d/1tClKynjyng50VEq-xuMwSP_Pkv-FsXWxEejWs-SjDu8/edit?usp=sharing"
    echo "Create a release presentation and export the pdf to be added to the nubis-docs/presentations folder:"
    echo "https://docs.google.com/a/mozilla.com/presentation/d/1IEyH3eDbAha1eFCfeDtHryME-1-2xeGcSgOy1HJmVgc/edit?usp=sharing"
    echo "Using the nubis-docs/templates/announce.txt send an email to:"
    echo "nubis-announce@googlegroups.com infra-systems@mozilla.com infra-webops@mozilla.com itleadership@mozilla.com moc@mozilla.com"
    echo "$0 create-milestones v1.X.0 # For the next release"
    echo "$0 upload-stacks v1.X.0 # For the next release"
    echo "$0 build-infrastructure v1.X.0-dev # For the next release"
    echo "$0 build nubis-ci v1.X.0-dev # For the next release"
}

# Upload nubis-stacks to release folder
upload_stacks () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
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
            echo -e "Updating StacksVersion in \"${TEMPLATE}\". (${_COUNT} of ${#TEMPLATE_ARRAY[*]})"
            cat "${TEMPLATE}" | jq ".Parameters.StacksVersion.Default|=\"${_RELEASE}\"" | sponge "${TEMPLATE}"
        else
            echo -e "StacksVersion unset in \"${TEMPLATE}\". (${_COUNT} of ${#TEMPLATE_ARRAY[*]})"
        fi
        let _COUNT=${_COUNT}+1
    done
    unset TEMPLATE

    cd ${NUBIS_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push
    if [ $? != '0' ]; then
        echo "Uploads for ${_RELEASE} failed."
        echo "Aborting....."
        exit 1
    fi
    check_in_changes 'nubis-stacks' "Update StacksVersion for ${RELEASE} release"
}

upload_lambda_functions () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
        $0 help
        exit 1
    fi
    cd ${NUBIS_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push-lambda
    if [ $? != '0' ]; then
        echo "Uploads for ${_RELEASE} failed."
        echo "Aborting....."
        exit 1
    fi
    check_in_changes 'nubis-stacks' "Updated lambda function bundles for ${RELEASE} release"
}

# Update StacksVersion to the current release
edit_main_json () {
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
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
            echo -e "Updating StacksVersion in \"${_FILE}\"."
            cat "${_FILE}" | jq ".Parameters.StacksVersion.Default|=\"${_RELEASE}\"" | sponge "${_FILE}"
        fi
    fi
}

# Update project_versoin to the current release
edit_project_json () {
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
        $0 help
        exit 1
    fi
    test_for_jq
    test_for_sponge
    local _FILE="${NUBIS_PATH}/${_REPOSITORY}/nubis/builder/project.json"
    if [ -f "${_FILE}" ]; then
        local _EDIT_PROJECT_VERSION=$(cat ${_FILE} | grep -c 'project_version')
        if [ ${_EDIT_PROJECT_VERSION:-0} -ge 1 ]; then
            echo -e "Updating project_version in \"${_FILE}\"."
            # Preserve any build data appended to the version 
            local _BUILD=$(cat ${_FILE} | jq --raw-output '"\(.variables.project_version)"' | cut -s -d'_' -f2-)
            cat "${_FILE}" | jq ".variables.project_version|=\"${_RELEASE}${_BUILD:+_${_BUILD}}\"" | sponge "${_FILE}"
        else
            echo -e "Variable project_version does not exist in \"${_FILE}\"."
            echo "Contine? [y/N]"
            read CONTINUE
            if [ ${CONTINUE:-n} == "N" ] || [ ${CONTINUE:-n} == "n" ]; then
                echo "Aborting....."
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

    check_in_changes 'nubis-storage' "Update storage AMI Ids for ${_RELEASE} release" 'nubis/cloudformation/main.json'

    # Copy the storage template to nubis-stacks as the templates should remain identical
    cp "${_FILE}" "${NUBIS_PATH}/nubis-stacks/storage.template"

    check_in_changes 'nubis-stacks' "Update storage AMI Ids for ${_RELEASE} release" 'storage.template'

    echo "Uploading updated storage.template to S3."
    cd ${NUBIS_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push storage.template
}

# This is a special edit to update an AMI mapping in nubis-nat in nubis-stacks
edit_nat_template () {
    local _RELEASE="${1}"
    local _US_EAST_1="${2}"
    local _US_WEST_2="${3}"
    local _FILE="${NUBIS_PATH}/nubis-stacks/vpc/vpc-nat.template"
    cat "${_FILE}" |\
    jq ".Mappings.AMIs.\"us-west-2\".AMIs |=\"${_US_WEST_2}\"" |\
    jq ".Mappings.AMIs.\"us-east-1\".AMIs |=\"${_US_EAST_1}\"" |\
    sponge "${_FILE}"

    check_in_changes 'nubis-stacks' "Update nat AMI Ids for ${_RELEASE} release" 'vpc/vpc-nat.template'

    echo "Uploading updated vpc/vpc-nat.template to S3."
    cd ${NUBIS_PATH}/nubis-stacks && $AWS_VAULT_COMMAND bin/upload_to_s3 --profile ${PROFILE} -m --path "${_RELEASE}" push vpc/vpc-nat.template
}

# This is a special edit to update the pinned version number to the current $RELEASE for the consul and vpc modules in nubis-deploy
edit_deploy_templates () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
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

# Build new AMIs for the named repository
build_amis () {
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
        $0 help
        exit 1
    fi
    if [ ${_REPOSITORY:-NULL} == 'NULL' ]; then
        echo "Repository required"
        $0 help
        exit 1
    fi
    test_for_nubis_builder
    edit_main_json "${_RELEASE}" "${_REPOSITORY}"
    edit_project_json "${_RELEASE}" "${_REPOSITORY}"
    echo "Running nubis-builder...."
    exec 5>&1
    OUTPUT=$(cd "${NUBIS_PATH}/${_REPOSITORY}" && nubis-builder build | tee >(cat - >&5))
    if [ $? != '0' ]; then
# Timeout waiting for SSH
        echo "Build for ${_REPOSITORY} failed. Contine? [y/N]"
        read CONTINUE
        if [ ${CONTINUE:-n} == "N" ] || [ ${CONTINUE:-n} == "n" ]; then
            echo "Aborting....."
            exit 1
        fi
        continue
    fi
    exec 5>&-
    # nubis-builder outputs some build artifacts. Lets check them in here
    check_in_changes "${_REPOSITORY}" "Update builder artifacts for ${RELEASE} release"

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
}

build_infrastructure_amis () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
        $0 help
        exit 1
    fi
    # Build a fresh copy of nubis-base first
    echo -e "\nBuilding AMIs for \"nubis-base\"."
    build_amis "${_RELEASE}" 'nubis-base'
    # Next build all of the infrastructure components form the fresh nubis-base
    local _COUNT=1
    for REPOSITORY in ${INFRASTRUCTURE_ARRAY[*]}; do
        if [[ " ${RELEASE_EXCLUDES[@]} " =~ " ${REPOSITORY} " ]]; then
            echo -e "\n Skipping \"${REPOSITORY}\" as it is in the excludes list. (${_COUNT} of ${#INFRASTRUCTURE_ARRAY[*]})"
            let COUNT=${_COUNT}+1
        else
            echo -e "\n Building AMIs for \"${REPOSITORY}\". (${_COUNT} of ${#INFRASTRUCTURE_ARRAY[*]})"
            build_amis "${_RELEASE}" "${REPOSITORY}"
            let _COUNT=${_COUNT}+1
        fi
    done
    unset REPOSITORY
}

release_repository () {
    local _RELEASE="${1}"
    local _REPOSITORY="${2}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
        $0 help
        exit 1
    fi
    if [ ${_REPOSITORY:-NULL} == 'NULL' ]; then
        echo "Repository required"
        $0 help
        exit 1
    fi
    if [ ${#CHANGELOG_GITHUB_TOKEN} == 0 ]; then
        echo 'You must have $CHANGELOG_GITHUB_TOKEN set'
        echo 'https://github.com/skywinder/github-changelog-generator#github-token'
        exit 1
    fi
    cd ${NUBIS_PATH}/${_REPOSITORY}

    if [ ${_REPOSITORY} == 'nubis-deploy' ]; then
        edit_deploy_templates "${_RELEASE}"
    fi
    
    # Update the CHANGELOG and make a pull-request, rebasing first to ensure a clean repository
    test_for_github_changelog_generator
    git checkout master
    git fetch origin
    git rebase origin/master
    github_changelog_generator --future-release ${_RELEASE} ${GITHUB_ORGINIZATION}/${_REPOSITORY}
    git add CHANGELOG.md
    git commit -m "Update CHANGELOG for ${_RELEASE} release"
    git push
    # GitHub is sometimes a bit slow here
    sleep 3
    hub pull-request -m "Update CHANGELOG for ${_RELEASE} release"

    # Switch to the originmaster branch, merge the pull-request and then tag the release
    git checkout originmaster
    git pull
    git merge --no-ff master -m "Merge branch 'master' into originmaster"
    git push origin HEAD:master
    git tag -s ${_RELEASE} -f -m"Signed ${_RELEASE} release"
    git push --tags -f
    # GitHub is sometimes a bit slow here
    sleep 3
    curl -i -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" --request POST --data "{\"tag_name\": \"${_RELEASE}\"}" https://api.github.com/repos/${GITHUB_ORGINIZATION}/${_REPOSITORY}/releases
    git checkout master
}

release_all_repositories () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        echo "Relesae number required"
        $0 help
        exit 1
    fi
    get_repositories
    local _COUNT=1
    for REPOSITORY in ${REPOSITORY_ARRAY[*]}; do
        if [[ " ${RELEASE_EXCLUDES[@]} " =~ " ${REPOSITORY} " ]]; then
            echo -e "\n Skipping \"${REPOSITORY}\" as it is in the excludes list. (${_COUNT} of ${#REPOSITORY_ARRAY[*]})"
            let _COUNT=${_COUNT}+1
        else
            echo -e "\n Releasing repository \"${REPOSITORY}\". (${_COUNT} of ${#REPOSITORY_ARRAY[*]})"
            local _RELEASE="${1}"
            release_repository "${_RELEASE}" "${REPOSITORY}"
            let _COUNT=${_COUNT}+1
        fi
    done
    unset REPOSITORY
}

testing () {
#    get_repositories
#    echo ${REPOSITORY_ARRAY[*]}
    edit_deploy_templates "$1"
}

# Grab and setup called options
while [ "$1" != "" ]; do
    case $1 in
        -v | --verbose )
            # For this simple script this will basicaly set -x
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
            echo -en "  upload-stacks [rel]           Upload nested stacks to S3\n"
            echo -en "  build [repo] [rel]            Build AMIs for [REPO] repository at [REL] release\n"
            echo -en "  build-infrastructure [rel]    Build all infrastructure components\n"
            echo -en "  release [repo] [rel]          Release [REPO] repository at [REL] release\n"
            echo -en "  release-all [rel]             Release all ${GITHUB_ORGINIZATION} repositories\n"
            echo -en "  build-instructions            Echo build steps\n\n"
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
            update_repository
            GOT_COMMAND=1
        ;;
        update-all )
            update_all_repositories
            GOT_COMMAND=1
        ;;
        file-release )
            RELEASE="${2}"
            shift
            file_release_issues ${RELEASE}
            GOT_COMMAND=1
        ;;
        create-milestones )
            RELEASE="${2}"
            shift
            create_milestones ${RELEASE}
            GOT_COMMAND=1
        ;;
        upload-stacks )
            RELEASE="${2}"
            shift
            upload_stacks ${RELEASE}
            upload_lambda_functions ${RELEASE}
            GOT_COMMAND=1
        ;;
        build )
            REPOSITORY="${2}"
            RELEASE="${3}"
            shift
            echo -e "\n Building AMIs for \"${REPOSITORY}\"."
            build_amis "${RELEASE}" "${REPOSITORY}"
            GOT_COMMAND=1
        ;;
        build-infrastructure )
            RELEASE="${2}"
            shift
            build_infrastructure_amis ${RELEASE}
            GOT_COMMAND=1
        ;;
        release )
            REPOSITORY="${2}"
            RELEASE="${3}"
            shift
            echo -e "\n Releasing repository \"${REPOSITORY}\". (${_COUNT} of ${#REPOSITORY_ARRAY[*]})"
            release_repository "${RELEASE}" "${REPOSITORY}"
            GOT_COMMAND=1
        ;;
        release-all )
            RELEASE="${2}"
            shift
            release_all_repositories ${RELEASE}
            GOT_COMMAND=1
        ;;
        build-instructions )
            build_instructions
            GOT_COMMAND=1
        ;;
        install-rvm )
            install_rvm
            GOT_COMMAND=1
        ;;
        testing )
            RELEASE="${2}"
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
