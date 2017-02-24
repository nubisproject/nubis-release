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

# This function will curl for the GitHub URL passed as ${1}
# Outputs what curl gets returned
get_data () {
    local _GITHUB_URL=${1}
    local _INTERNAL_DATA
    if [ ${CHANGELOG_GITHUB_TOKEN:-NULL} == 'NULL' ];then
        log_term 1 "WARNING: 'CHANGELOG_GITHUB_TOKEN' unset. Data may be incomplete."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        _INTERNAL_DATA=$(curl -s "${_GITHUB_URL}")
        log_term 2 "Get date from: \"${_GITHUB_URL}\""
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    else
        _INTERNAL_DATA=$(curl -s -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" "${_GITHUB_URL}")
        log_term 2 "Get data from: \"${_GITHUB_URL}\""
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    fi
    echo "${_INTERNAL_DATA}"

    # Clean up
    unset _GITHUB_URL _INTERNAL_DATA
}

# Part of GitHub pagination logic. See the 'collect_data ()' function below.
#
# This function gathers headers and pases out the 'Link" header
# GITHUB_URL must be passed as ${1}
# Sets ${LINK} from 'Link' header. (Others are not currently used)
get_headers () {
    local _GITHUB_URL=${1}
    while IFS=':' read KEY VALUE; do
        # Trim whitespace off the front and back of $VALUE
        VALUE=${VALUE##+([[:space:]])}; VALUE=${VALUE%%+([[:space:]])}

        case "$KEY" in
            Link) LINK="$VALUE"
                    ;;
            Content-Type) CT="$VALUE"
                    ;;
            HTTP*) read PROTO STATUS MSG <<< "$KEY{$VALUE:+:$VALUE}"
                    ;;
        esac
    done < <(if [ ${CHANGELOG_GITHUB_TOKEN:-NULL} == 'NULL' ];then curl -sI "${_GITHUB_URL}"; else curl -sI -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" "${_GITHUB_URL}"; fi)

    # Clean up
    unset _GITHUB_URL
}

# Part of GitHub pagination logic. See the 'collect_data ()' function below.
#
# Gets ${LINK} from 'get_headers ()' and echos each segment in turn
get_link_header_segments () {
    local _GITHUB_URL=${1}
    get_headers  "${_GITHUB_URL}"
    # If github does not return a 'Link' header, break
    if [ ${#LINK} == 0 ]; then
        break
    fi
    while [ ${COUNT:-0} -lt 4 ]; do
        let COUNT=$COUNT+1
        LINK_SEGMENT=$(echo $LINK | cut -d ',' -f $COUNT)
        if [ ${#LINK_SEGMENT} -gt 0 ]; then
            echo $LINK_SEGMENT
        fi
    done

    # Clean up
    unset _GITHUB_URL
}

# Part of GitHub pagination logic. See the 'collect_data ()' function below.
#
# Gets 'Link' header segments from 'get_link_header_segments ()'
# Sets: ${FIRST_URL} ${PREV_URL} ${NEXT_URL} ${LAST_URL}
get_pagination_urls () {
    local _GITHUB_URL=${1}
    while IFS=';' read URL REL; do
        # Trim whitespace off the front and back of $REL
        REL=${REL##+([[:space:]])}; REL=${REL%%+([[:space:]])}
        # Trim the "rel=" off the front of $REL
        REL=$(echo ${REL} | cut -d '=' -f 2)
        # Trim quotes off the front and back of $REL
        REL=${REL##+([\"])}; REL=${REL%%+([\"])}
        # Trim less than and greater than off the front and back of $URL
        URL=${URL##+([<])}; URL=${URL%%+([>])}

        # Populate the *_URL variables
        case "$REL" in
            first) FIRST_URL="$URL"
                    ;;
            prev) PREV_URL="$URL"
                    ;;
            next) NEXT_URL="$URL"
                    ;;
            last) LAST_URL="$URL"
                    ;;
        esac
    done < <(get_link_header_segments "${_GITHUB_URL}")

    # Clean up
    unset _GITHUB_URL
}

# This is a wrapper function which collects data from GitHub with pagination logic
#
# This uses the 'get_pagination_urls ()' function to set pagination URLs
#+ which uses the 'get_link_header_segments ()' function to parse the 'Link' header
#+ which uses the get_headers () function to gather the 'Link' header
#
# This function then calls the 'get_data ()' function to collect the actual data from each page
#
collect_data () {
    local _GITHUB_URL=${1}
    local _INTERNAL_DATA
    # Paginate through grabbing data as we go
    while [ ${DONE:-0} -ne 1 ]; do

        log_term 1 "Collecting data from: ${_GITHUB_URL}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        _INTERNAL_DATA="${_INTERNAL_DATA} $(get_data "${_GITHUB_URL}")"
        get_pagination_urls "${_GITHUB_URL}"
        # If we do not get a 'next' url, break
        if [ ${#NEXT_URL} == 0 ]; then
            break
        fi
        if [ ${NEXT_URL} != ${LAST_URL} ]; then
            _GITHUB_URL=${NEXT_URL}
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        else
            _GITHUB_URL=${NEXT_URL}
            log_term 1 "Collecting data from: ${_GITHUB_URL}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            _INTERNAL_DATA="${_INTERNAL_DATA} $(get_data "${_GITHUB_URL}")"
            let DONE=1
        fi
    done
    echo "${_INTERNAL_DATA}"

    # Clean up
    unset _GITHUB_URL _INTERNAL_DATA
}


# This function gathers the list of repositories belonging to the GitHub orginization.
# This function should be called only once for any given run
# Sets: ${REPOSITORY_LIST_ARRAY[*]} ${REPOSITORY_BUILD_ARRAY[*]}  ${REPOSITORY_RELEASE_ARRAY[*]}  ${REPOSITORY_EXCLUDE_ARRAY[*]}
# Returns: Nothing
declare -a REPOSITORY_LIST_ARRAY REPOSITORY_BUILD_ARRAY REPOSITORY_RELEASE_ARRAY REPOSITORY_EXCLUDE_ARRAY
get_repositories () {
    if [ ${GITHUB_ORGINIZATION:-NULL} == 'NULL' ]; then
        log_term 0 "GitHub orginization not defined. Please edit your variables file."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi

    # Set up GitHub API URL
    local _GITHUB_URL="https://api.github.com/orgs/${GITHUB_ORGINIZATION}/repos"
    log_term 1 "Setting _GITHUB_URL to: \"${_GITHUB_URL}\""
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Collect the JSON list of repositories
    local _REPOSITORY_LIST=$(collect_data ${_GITHUB_URL})
    log_term 2 "Collecting _REPOSITORY_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Parse out only the name and sort
    local _PARSE_REPOSITORY_LIST=$(echo "${_REPOSITORY_LIST}" | jq -r '.[].name' | sort)
    log_term 2 "Parsing and sorting _REPOSITORY_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Format the list into an array
    for REPO in ${_PARSE_REPOSITORY_LIST}; do
        REPOSITORY_LIST_ARRAY=( ${REPOSITORY_LIST_ARRAY[*]} ${REPO} )
        log_term 3 "REPOSITORY_LIST_ARRAY=${REPOSITORY_LIST_ARRAY[*]}"
    done
    log_term 1 "Found ${#REPOSITORY_LIST_ARRAY[*]} repositories: ${REPOSITORY_LIST_ARRAY[*]}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Set up REPOSITORY_BUILD_ARRAY REPOSITORY_RELEASE_ARRAY REPOSITORY_EXCLUDE_ARRAY
    for REPOSITORY in ${REPOSITORY_LIST_ARRAY[*]}; do
        if [[ " ${BUILD_REPOSITORIES[@]} " =~ " ${REPOSITORY} " ]] && [[ ! " ${EXCLUDE_REPOSITORIES[@]} " =~ " ${REPOSITORY} " ]]; then
            log_term 2 "Adding \"${REPOSITORY}\" to REPOSITORY_BUILD_ARRAY."
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            REPOSITORY_BUILD_ARRAY=( ${REPOSITORY_BUILD_ARRAY[*]} ${REPOSITORY} )
        elif [[ " ${RELEASE_REPOSITORIES[@]} " =~ " ${REPOSITORY} " ]] && [[ ! " ${EXCLUDE_REPOSITORIES[@]} " =~ " ${REPOSITORY} " ]]; then
            log_term 2 "Adding \"${REPOSITORY}\" to REPOSITORY_RELEASE_ARRAY."
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            REPOSITORY_RELEASE_ARRAY=( ${REPOSITORY_RELEASE_ARRAY[*]} ${REPOSITORY} )
        else
            log_term 2 "Adding \"${REPOSITORY}\" to REPOSITORY_EXCLUDE_ARRAY."
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            REPOSITORY_EXCLUDE_ARRAY=( ${REPOSITORY_EXCLUDE_ARRAY[*]} ${REPOSITORY} )
        fi
    done
    log_term 1 "Building ${#REPOSITORY_BUILD_ARRAY[*]} repositories: ${REPOSITORY_BUILD_ARRAY[*]}"
    log_term 1 "Releasing ${#REPOSITORY_RELEASE_ARRAY[*]} repositories: ${REPOSITORY_RELEASE_ARRAY[*]}"
    log_term 1 "Excluding ${#REPOSITORY_EXCLUDE_ARRAY[*]} repositories: ${REPOSITORY_EXCLUDE_ARRAY[*]}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
}

# This function generates a list of all of the GitHub issues closed for the release.
# Both ${GITHUB_ORGINIZATION} and ${RELEASE_DATES} must be set (see variables.sh)
# Optionaly a file-name may be passed in, otherwise a default file is created in /tmp
# Makes use of the 'collect_data ()' function only.
# Requires two external dependancies: 'jq' and 'json2csv'
# OUTPUTS: A CSV formatted file in ${CSV_FILE}
generate_release_csv () {
    local _CSV_FILE="${1}"
    if [ ${_CSV_FILE:-NULL} == "NULL" ]; then
        _CSV_FILE="/tmp/nubis-release-$RELEASE_DATES.csv"
    fi

    # Set up GitHub API URL
    local _GITHUB_URL="https://api.github.com/search/issues?q=is:closed+is:issue+user:${GITHUB_ORGINIZATION}+closed:${RELEASE_DATES}"
    log_term 1 "Setting _GITHUB_URL to: \"${_GITHUB_URL}\""
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Collect the JSON list of issues
    local _ISSUE_LIST=$(collect_data ${_GITHUB_URL})
    log_term 2 "Collecting _ISSUE_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Parse out only the info we will report on about
    local _PARSE_ISSUE_LIST=$(echo "${_ISSUE_LIST}" | jq -c '.["items"][] | {title: .title, html_url: .html_url, user: .user.login}')
    log_term 2 "Parsing _ISSUE_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Convert the data from JSON to CSV
    local _OUTPUT=$(echo "${_PARSE_ISSUE_LIST}" | json2csv -k html_url,Estimated_m-h,user,Risk,title -o ${_CSV_FILE})
    log_term 2 "Formatting _ISSUE_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    log_term 0 "Output data to: ${_CSV_FILE}"
    if [ ${_OUTPUT:-NULL} != NULL ]; then
        log_term 0 "Command output was:\n ${_OUTPUT}" -n
    else
        log_term 0 "Import CSV into milestone tracker at:"
        log_term 0 "https://docs.google.com/spreadsheets/d/1tClKynjyng50VEq-xuMwSP_Pkv-FsXWxEejWs-SjDu8/edit?usp=sharing"
    fi

    # Clean up
    unset _CSV_FILE _GITHUB_URL _ISSUE_LIST _PARSE_ISSUE_LIST _OUTPUT
}

clone_repository () {
    TEST=$(hub --version 2>&1) 2> /dev/null
    if [ $? != 0 ]; then
        log_term 0 "hub must be installed and on your path!"
        log_term 0 "See: https://hub.github.com/"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    if [ ${REPOSITORY:-NULL} == 'NULL' ]; then
        log_term 0 "You must specify a repository!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    if [ -d ${NUBIS_PATH}/${REPOSITORY} ]; then
        log_term 0 "Directory \"${NUBIS_PATH}/${REPOSITORY}\" already exists. Aborting!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
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
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    if [ ! -d ${NUBIS_PATH}/${REPOSITORY} ]; then
        log_term 1 " Repository \"${REPOSITORY}\" not found... Attempting to clone locally."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        clone_repository ${REPOSITORY}
    fi
    log_term 1 " #### Updating repository ${REPOSITORY} ####" -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    cd ${NUBIS_PATH}/${REPOSITORY}
    git checkout master
    git fetch origin
    git rebase origin/master
    if [ $? != 0 ]; then
        log_term 0 "\n !!!!!!!! Repository '${REPOSITORY}' not updated! !!!!!!!!\n" -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    else
        git push
    fi
}

update_all_repositories () {
    get_repositories
    COUNT=1
    for REPOSITORY in ${REPOSITORY_LIST_ARRAY[*]}; do
        log_term 0 "\n Updating ${COUNT} of ${#REPOSITORY_ARRAY[*]} repositories" -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        update_repository ${REPOSITORY}
        let COUNT=${COUNT}+1
    done
}

# Create, list and close milestones.
# If milestone exists open, echo number
# If milestone exists open and we are closing, close milestone, echo number
# If milestone exists closed ?? (Currently just echo number and return, not sure the best approach here)
# If milestone exists closed and we are closing, echo number
# If milestone non-exists, open milestone, echo number
# If milestone not-exists and we are closing, echo 'NULL'
#
# Call function like 'get_set_milestone "v1.2.0" "nubis-base" ["close"]'
# Returns (as echo) milestone number or "NULL'
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
    local _CLOSE_MILESTONE="${3}"
    # First check to see if we have an open milestone
    _MILESTONE_NUMBER_OPEN=$(milestone_open)
    if [ "${_MILESTONE_NUMBER_OPEN:-NULL}" != 'NULL' ]; then
        _MILESTONE_NUMBER="${_MILESTONE_NUMBER_OPEN}"
    else
        # Next check to see if we have the milestone but it is closed
        # If so, echo the number and return
        _MILESTONE_NUMBER_CLOSED=$(milestone_closed)
        if [ "${_MILESTONE_NUMBER_CLOSED:-NULL}" != 'NULL' ]; then
            _MILESTONE_NUMBER="${_MILESTONE_NUMBER_CLOSED}"
            echo "${_MILESTONE_NUMBER}"
            return
        fi
    fi
    # If it is open and we are closing, close milestone
    #+ else, assume we are creating and open a milestone
    if [ "${_MILESTONE_NUMBER_OPEN:-NULL}" != 'NULL' ] && [ "${_CLOSE_MILESTONE:-NULL}" != 'NULL'  ]; then
        log_term 0 "Closing milestone ${_MILESTONE_NUMBER}"
        _MILESTONE_NUMBER=$(ghi milestone --state closed "${_MILESTONE_NUMBER}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"  | cut -s -d'#' -f 2 | cut -d':' -f 1)
    # Finally create the milestone as it does not appear to exist
    #+ Do not crete if we are closing
    elif [ "${_MILESTONE_NUMBER:-NULL}" == 'NULL' ] && [ "${_CLOSE_MILESTONE:-NULL}" == 'NULL'  ]; then
        log_term 0 "Creating milestone ${_MILESTONE}"
#        _MILESTONE_NUMBER=$(ghi milestone --message "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"  | cut -d'#' -f 2 | cut -d' ' -f 1)
    fi
    echo "${_MILESTONE_NUMBER:-NULL}"
    return
}

create_milestones () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae nubber required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    get_repositories
    declare -a MILESTONE_REPOSITORY_ARRAY=( 'nubis-base' ${REPOSITORY_BUILD_ARRAY[*]} ${REPOSITORY_RELEASE_ARRAY[*]} )
    local _COUNT=1
    for REPOSITORY in ${MILESTONE_REPOSITORY_ARRAY[*]}; do
        log_term 1 "\nCreating milestone in \"${REPOSITORY}\". (${_COUNT} of ${#MILESTONE_REPOSITORY_ARRAY[*]})" -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        local _MILESTONE=$(get_set_milestone "${_RELEASE}" "${REPOSITORY}")
        log_term 1 "Got milestone number \"${_MILESTONE}\"."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        let _COUNT=${_COUNT}+1
    done
    unset REPOSITORY MILESTONE_REPOSITORY_ARRAY
}

close_milestones () {
    local _RELEASE="${1}"
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae nubber required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    get_repositories
    declare -a MILESTONE_REPOSITORY_ARRAY=( 'nubis-base' ${REPOSITORY_BUILD_ARRAY[*]} ${REPOSITORY_RELEASE_ARRAY[*]} )
    local _COUNT=1
    for REPOSITORY in ${MILESTONE_REPOSITORY_ARRAY[*]}; do
        log_term 1 "\nClosing milestone in \"${REPOSITORY}\". (${_COUNT} of ${#MILESTONE_REPOSITORY_ARRAY[*]})" -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        local _MILESTONE=$(get_set_milestone "${_RELEASE}" "${REPOSITORY}" "Close")
        log_term 1 "Got milestone number \"${_MILESTONE}\"."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        let _COUNT=${_COUNT}+1
    done
    unset REPOSITORY MILESTONE_REPOSITORY_ARRAY
}

file_issue () {
    test_for_ghi
    local _REPOSITORY="${1}"
    local _ISSUE_TITLE="${2}"
    local _ISSUE_BODY="${3}"
    local _MILESTONE="${4}"
    ghi open --message "${_ISSUE_BODY}" "${_ISSUE_TITLE}" --milestone "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"
}

get_release_issue () {
    test_for_ghi
    local _REPOSITORY="${1}"
    local _ISSUE_TITLE="${2}"
    local _MILESTONE="${3}"
    local _ISSUE_NUMBER=$(ghi list --state open --no-pulls --milestone "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" | grep "${_ISSUE_TITLE}" | cut -d ' ' -f 3)
    log_term 1 "Got release issue number(s): \"${_ISSUE_NUMBER}\"."
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    local _ISSUE_COUNT=0
    for ISSUE in ${_ISSUE_NUMBER}; do
        let _ISSUE_COUNT+=1
    done
    if (( "${_ISSUE_COUNT}" == 0 )); then
        log_term 0 "Warning: Release issue not found."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        return 1
    elif (( "${_ISSUE_COUNT}" == 1 )); then
        log_term 1 "Congratulations: Got exactly one release issue number."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    elif (( "${_ISSUE_COUNT}" >= 2 )); then
        _ISSUE_NUMBER=$(echo ${_ISSUE_NUMBER} | cut -d ' ' -f 1)
        log_term 1 "Warning: Got \"${_ISSUE_COUNT}\" issue numbers. Returning only the first: \"${_ISSUE_NUMBER}\"."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    fi
    echo "${_ISSUE_NUMBER}"
    return 0
}

close_issue () {
    test_for_ghi
    local _REPOSITORY="${1}"
    local _ISSUE_MESSAGE="${2}"
    local _ISSUE_NUMBER="${3}"
    ghi close --message "${_ISSUE_MESSAGE}" "${_ISSUE_NUMBER}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"
}

merge_changes () {
    local _REPOSITORY=${1}
    if [ "${NON_INTERACTIVE:-NULL}" == 'NULL' ]; then
        log_term 0 "Merge pull-request? [y/N]"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        read CONTINUE
    else
        CONTINUE='y'
    fi
    if [ ${CONTINUE:-n} == "Y" ] || [ ${CONTINUE:-n} == "y" ]; then
        # Switch to the originmaster branch and merge the pull-request
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git checkout originmaster
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git pull
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git merge --no-ff master -m "Merge branch 'master' into originmaster [skip ci]"
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
    if [ "${NON_INTERACTIVE:-NULL}" == 'NULL' ]; then
        log_term 0 "Check in changes for \"${_REPOSITORY}\" to: \"${_FILE}\"? [Y/n]"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        read CONTINUE
    else
        CONTINUE='y'
    fi
    if [ ${CONTINUE:-y} == "Y" ] || [ ${CONTINUE:-y} == "y" ]; then
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git add ${_FILE}
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git commit -m "${_MESSAGE} [skip ci]"
        cd "${NUBIS_PATH}/${_REPOSITORY}" && git push
        # GitHub is sometimes a bit slow here
        sleep 3
        cd "${NUBIS_PATH}/${_REPOSITORY}" && hub pull-request -m "${_MESSAGE} [skip ci]"

        merge_changes "${_REPOSITORY}"
    fi
}

release_repository () {
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    if [ ${_REPOSITORY:-NULL} == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    if [ ${_RELEASE:-NULL} == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    if [ ${#CHANGELOG_GITHUB_TOKEN} == 0 ]; then
        log_term 0 'You must have ${CHANGELOG_GITHUB_TOKEN} set'
        log_term 0 'https://github.com/skywinder/github-changelog-generator#github-token'
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
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
    git commit -m "Update CHANGELOG for ${_RELEASE} release [skip ci]"
    git push
    # GitHub is sometimes a bit slow here
    sleep 3
    hub pull-request -m "Update CHANGELOG for ${_RELEASE} release [skip ci]"

    # Switch to the originmaster branch, merge the pull-request and then tag the release
    git checkout originmaster
    git pull
    git merge --no-ff master -m "Merge branch 'master' into originmaster [skip ci]"
    git push origin HEAD:master
    git tag -s ${_RELEASE} -f -m"Signed ${_RELEASE} release"
    git push --tags -f
    # GitHub is sometimes a bit slow here
    sleep 3

    # Check to see if we already have a release on GitHub
    _RELEASE_ID=$(curl -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" --request GET https://api.github.com/repos/${GITHUB_ORGINIZATION}/${_REPOSITORY}/releases/tags/${_RELEASE} | jq .id)

    # If we have a release we need to delete it before recreating it
    if [ ${_RELEASE_ID:-null} != 'null' ]; then
        curl -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" --request DELETE https://api.github.com/repos/${GITHUB_ORGINIZATION}/${_REPOSITORY}/releases/${_RELEASE_ID}
    fi

    # Now we can create the release
    curl -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" --request POST --data "{\"tag_name\": \"${_RELEASE}\"}" https://api.github.com/repos/${GITHUB_ORGINIZATION}/${_REPOSITORY}/releases

    # Refresh the local fork
    git checkout master
}
