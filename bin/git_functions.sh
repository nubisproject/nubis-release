#!/bin/bash
#
# Functions for working with git and GitHub here
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

declare -a REPOSITORY_ARRAY

get_repositories () {
    # Gather the list of repositories in the nubisproject from GitHub
    REPOSITORY_LIST=$(curl -s https://api.github.com/orgs/nubisproject/repos?per_page=100 | jq -r '.[].name' | sort)

    # Format the list into an array
    for REPO in ${REPOSITORY_LIST}; do
        REPOSITORY_ARRAY=( ${REPOSITORY_ARRAY[*]} $REPO )
        log_term 3 "REPOSITORY_ARRAY=${REPOSITORY_ARRAY[*]}"
    done
}

clone_repository () {
    TEST=$(hub --version 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        log_term 0 "hub must be installed and on your path!"
        log_term 0 "See: https://hub.github.com/"
        exit 1
    fi
    if [ ${REPOSITORY:-NULL} == 'NULL' ]; then
        log_term 0 "You must specify a repository!"
        exit 1
    fi
    if [ -d ${NUBIS_PATH}/${REPOSITORY} ]; then
        log_term 0 "Directory \"${NUBIS_PATH}/${REPOSITORY}\" already exists. Aborting!"
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
        log_term 0 "You must specify a repository!"
        exit 1
    fi
    if [ ! -d ${NUBIS_PATH}/${REPOSITORY} ]; then
        log_term 1 " Repository \"${REPOSITORY}\" not found... Attempting to clone locally."
        clone_repository ${REPOSITORY}
    fi
    log_term 1 " #### Updating repository ${REPOSITORY} ####" -e
    cd ${NUBIS_PATH}/${REPOSITORY}
    git checkout master
    git fetch origin
    git rebase origin/master
    if [ $? != 0 ]; then
        log_term 0 "\n !!!!!!!! Repository '${REPOSITORY}' not updated! !!!!!!!!\n" -e
    else
        git push
    fi
}

update_all_repositories () {
    get_repositories
    COUNT=1
    for REPOSITORY in ${REPOSITORY_ARRAY[*]}; do
        log_term 0 "\n Updating ${COUNT} of ${#REPOSITORY_ARRAY[*]} repositories" -e
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
        log_term 0 "${_MILESTONE_NUMBER}"
        return
    fi
    # Next check to see if we have the milestone but it is closed
    _MILESTONE_NUMBER=$(milestone_closed)
    if [ "${_MILESTONE_NUMBER:-NULL}" != 'NULL' ]; then
        log_term 0 "${_MILESTONE_NUMBER}"
        return
    fi
    # Finally create the milestone as it does not appear to exist
    _MILESTONE_NUMBER=$(ghi milestone -m "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"  | cut -d'#' -f 2 | cut -d' ' -f 1)
    log_term 0 "${_MILESTONE_NUMBER}"
    return
}

create_milestones () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae nubber required"
        $0 help
        exit 1
    fi
    get_repositories
    local _COUNT=1
    for REPOSITORY in ${REPOSITORY_ARRAY[*]}; do
        if [[ " ${RELEASE_EXCLUDES[@]} " =~ " ${REPOSITORY} " ]]; then
            log_term 0 "\n Skipping \"${REPOSITORY}\" as it is in the excludes list. (${_COUNT} of ${#REPOSITORY_ARRAY[*]})" -e
            let COUNT=${_COUNT}+1
        else
            log_term 0 "\n Creating milestone in \"${REPOSITORY}\". (${_COUNT} of ${#REPOSITORY_ARRAY[*]})" -e
            local _RELEASE="${1}"
            local _MILESTONE=$(get_set_milestone "${_RELEASE}" "${REPOSITORY}")
            log_term 0 " Got milestone number \"${_MILESTONE}\"."
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
        log_term 0 "Relesae number required"
        $0 help
        exit 1
    fi
    get_repositories
    local _COUNT=1
    for REPOSITORY in ${REPOSITORY_ARRAY[*]}; do
        if [[ " ${RELEASE_EXCLUDES[@]} " =~ " ${REPOSITORY} " ]]; then
            log_term 1 "\n Skipping \"${REPOSITORY}\" as it is in the excludes list. (${_COUNT} of ${#REPOSITORY_ARRAY[*]})" -e
            let COUNT=${COUNT}+1
        else
            log_term 1 "\n Filing release issue in \"${REPOSITORY}\". (${_COUNT} of ${#REPOSITORY_ARRAY[*]})" -e
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

release_repository () {
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
    if [ ${#CHANGELOG_GITHUB_TOKEN} == 0 ]; then
        log_term 0 'You must have $CHANGELOG_GITHUB_TOKEN set'
        log_term 0 'https://github.com/skywinder/github-changelog-generator#github-token'
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
        log_term 0 "Relesae number required"
        $0 help
        exit 1
    fi
    get_repositories
    local _COUNT=1
    for REPOSITORY in ${REPOSITORY_ARRAY[*]}; do
        if [[ " ${RELEASE_EXCLUDES[@]} " =~ " ${REPOSITORY} " ]]; then
            log_term 2 "\n Skipping \"${REPOSITORY}\" as it is in the excludes list. (${_COUNT} of ${#REPOSITORY_ARRAY[*]})" -e
            let _COUNT=${_COUNT}+1
        else
            log_term 0 "\n Releasing repository \"${REPOSITORY}\". (${_COUNT} of ${#REPOSITORY_ARRAY[*]})" -e
            local _RELEASE="${1}"
            release_repository "${_RELEASE}" "${REPOSITORY}"
            let _COUNT=${_COUNT}+1
        fi
    done
    unset REPOSITORY
}
