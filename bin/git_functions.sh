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
    if [ "${CHANGELOG_GITHUB_TOKEN:-NULL}" == 'NULL' ];then
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
    while IFS=':' read -r KEY VALUE; do
        # Trim whitespace off the front and back of $VALUE
        VALUE=${VALUE##+([[:space:]])}; VALUE=${VALUE%%+([[:space:]])}

        case "${KEY}" in
            Link) LINK="${VALUE}"
                ;;
#             Content-Type) CONTENT_TYPE="$VALUE"
#                 ;;
#             HTTP*) read -r PROTOCOL STATUS MESSAGE <<< "$KEY{$VALUE:+:$VALUE}"
#                 ;;
        esac
    done < <(if [ "${CHANGELOG_GITHUB_TOKEN:-NULL}" == 'NULL' ];then curl -sI "${_GITHUB_URL}"; else curl -sI -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" "${_GITHUB_URL}"; fi)

    # Clean up
    unset _GITHUB_URL
}

# Part of GitHub pagination logic. See the 'collect_data ()' function below.
#
# Gets ${LINK} from 'get_headers ()' and echos each segment in turn
get_link_header_segments () {
    local _GITHUB_URL=${1}
    get_headers  "${_GITHUB_URL}"
    # If github does not return a 'Link' header, return
    if [ "${#LINK}" == 0 ]; then
        return
    fi
    while [ "${COUNT:-0}" -lt 4 ]; do
        let COUNT=${COUNT}+1
        LINK_SEGMENT=$(echo "${LINK}" | cut -d ',' -f "${COUNT}")
        if [ "${#LINK_SEGMENT}" -gt 0 ]; then
            echo "${LINK_SEGMENT}"
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
    while IFS=';' read -r URL REL; do
        # Trim whitespace off the front and back of ${REL}
        REL=${REL##+([[:space:]])}; REL=${REL%%+([[:space:]])}
        # Trim the "rel=" off the front of ${REL}
        REL=$(echo "${REL}" | cut -d '=' -f 2)
        # Trim quotes off the front and back of ${REL}
        REL=${REL##+([\"])}; REL=${REL%%+([\"])}
        # Trim whitespace off the front and back of ${URL}
        URL=${URL##+([[:space:]])}; URL=${URL%%+([[:space:]])}
        # Trim less than and greater than off the front and back of ${URL}
        URL=${URL##+([<])}; URL=${URL%%+([>])}

        # Populate the *_URL variables
        case "${REL}" in
#             first) FIRST_URL="$URL"
#                 ;;
#             prev) PREV_URL="$URL"
#                 ;;
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
    while [ "${DONE:-0}" -ne 1 ]; do

        log_term 1 "Collecting data from: ${_GITHUB_URL}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        _INTERNAL_DATA="${_INTERNAL_DATA} $(get_data "${_GITHUB_URL}")"
        get_pagination_urls "${_GITHUB_URL}"
        # If we do not get a 'next' url, break
        if [ ${#NEXT_URL} == 0 ]; then
            break
        fi
        if [ "${NEXT_URL}" != "${LAST_URL}" ]; then
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
    if [ "${GITHUB_ORGINIZATION:-NULL}" == 'NULL' ]; then
        log_term 0 "GitHub orginization not defined. Please edit your variables file."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi

    # Set up GitHub API URL
    local _GITHUB_URL="https://api.github.com/orgs/${GITHUB_ORGINIZATION}/repos"
    log_term 1 "Setting _GITHUB_URL to: \"${_GITHUB_URL}\""
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Collect the JSON list of repositories
    local _REPOSITORY_LIST; _REPOSITORY_LIST=$(collect_data "${_GITHUB_URL}")
    log_term 2 "Collecting _REPOSITORY_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Parse out only the name and sort
    local _PARSE_REPOSITORY_LIST; _PARSE_REPOSITORY_LIST=$(echo "${_REPOSITORY_LIST}" | jq -r '.[].name' | sort)
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
        if [[ " ${BUILD_REPOSITORIES[@]} " =~ ${REPOSITORY} ]] && [[ ! " ${EXCLUDE_REPOSITORIES[@]} " =~ ${REPOSITORY} ]]; then
            log_term 2 "Adding \"${REPOSITORY}\" to REPOSITORY_BUILD_ARRAY."
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            REPOSITORY_BUILD_ARRAY=( ${REPOSITORY_BUILD_ARRAY[*]} ${REPOSITORY} )
        elif [[ " ${RELEASE_REPOSITORIES[@]} " =~ ${REPOSITORY} ]] && [[ ! " ${EXCLUDE_REPOSITORIES[@]} " =~ ${REPOSITORY} ]]; then
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
    if [ "${_CSV_FILE:-NULL}" == "NULL" ]; then
        _CSV_FILE="./logs/nubis-release-$RELEASE_DATES.csv"
    fi

    # Set up GitHub API URL
    local _GITHUB_URL="https://api.github.com/search/issues?q=is:closed+is:issue+user:${GITHUB_ORGINIZATION}+closed:${RELEASE_DATES}"
    log_term 1 "Setting _GITHUB_URL to: \"${_GITHUB_URL}\""
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Collect the JSON list of issues
    local _ISSUE_LIST; _ISSUE_LIST=$(collect_data "${_GITHUB_URL}")
    log_term 2 "Collecting _ISSUE_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Parse out only the info we will report on about
    local _PARSE_ISSUE_LIST; _PARSE_ISSUE_LIST=$(echo "${_ISSUE_LIST}" | jq -c '.["items"][] | {title: .title, html_url: .html_url, user: .user.login}')
    log_term 2 "Parsing _ISSUE_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Convert the data from JSON to CSV
    local _OUTPUT; _OUTPUT=$(echo "${_PARSE_ISSUE_LIST}" | json2csv -k html_url,Estimated_m-h,user,Risk,title -o "${_CSV_FILE}")
    log_term 2 "Formatting _ISSUE_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    log_term 0 "Output data to: ${_CSV_FILE}"
    if [ "${_OUTPUT:-NULL}" != NULL ]; then
        log_term 0 "Command output was:\n ${_OUTPUT}" -n
    else
        log_term 0 "Import CSV into milestone tracker at:"
        log_term 0 "https://docs.google.com/spreadsheets/d/1tClKynjyng50VEq-xuMwSP_Pkv-FsXWxEejWs-SjDu8/edit?usp=sharing"
    fi

    # Clean up
    unset _CSV_FILE _GITHUB_URL _ISSUE_LIST _PARSE_ISSUE_LIST _OUTPUT
}

# Clones the named repository
#+ Optionally specify a git ref (hash, branch, tag, release, etc) to check out
#+ Otherwise check out develop branch
clone_repository () {
    local _REPOSITORY="${1}"
    local _GIT_REF="${2}"
    if [ "${_REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "You must specify a repository!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    # If the repository exists in the repository path, remove it
    if [ -d "${REPOSITORY_PATH}"/"${_REPOSITORY}" ]; then
        log_term 1 "Directory \"${REPOSITORY_PATH}/${_REPOSITORY}\" already exists. Removing!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        rm -rf "${REPOSITORY_PATH:?'REPOSITORY_PATH is unset'}"/"${_REPOSITORY:?'REPOSITORY is unset'}" || exit 1

    fi
    # If the repository path does not exist, create it
    if [ ! -d "${REPOSITORY_PATH}" ]; then
        log_term 1 "Directory \"${REPOSITORY_PATH}\" does not exist. Creating."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        mkdir "${REPOSITORY_PATH:?'REPOSITORY_PATH is unset'}" || exit 1

    fi
    cd "${REPOSITORY_PATH}" || exit 1
    SSH_URL=$(curl -s https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" | jq -r '.ssh_url')
    git clone "${SSH_URL}" || exit 1
    cd "${_REPOSITORY}" || exit 1
    # If a git ref was specified, checkout at that ref
    if [ "${_GIT_REF:-NULL}" != 'NULL' ]; then
        git checkout "${_GIT_REF}" || exit 1
        git submodule update --init --recursive || exit 1
    else
        git checkout develop || exit 1
        git submodule update --init --recursive || exit 1
    fi
}

# Create a releae branch on named repositry
create_release_branch () {
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    if [ "${REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "You must specify a repository!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    if [ "${RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "You must specify a release!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    # Ensure the repository exists in the repository path
    if [ ! -d "${REPOSITORY_PATH}"/"${_REPOSITORY}" ]; then
        log_term 0 "Repository '${_REPOSITORY}' not chekced out out in repository path '${REPOSITORY_PATH}'!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1
    # Check to see if the branch already exists
    BRANCH_EXISTS=$(git branch -a | grep -c "release-${_RELEASE}")
    # If no branch exists, create it and push the remote tracking branch
    if [ "${BRANCH_EXISTS}" == 0 ]; then
        git checkout -b "release-${_RELEASE}" || exit 1
        git submodule update --init --recursive || exit 1
        git push --set-upstream origin "release-${_RELEASE}" || exit 1
    # If we get only one
    elif [ "${BRANCH_EXISTS}" == 1 ]; then
        # Lets try to determine if it is a remote branch
        BRANCH_REMOTE=$(git branch -a | grep -c "/release-${_RELEASE}")
        # If not, assume it is local and attempt to set upstream tracking
        if [ "${BRANCH_REMOTE}" == 0 ]; then
            git push --set-upstream origin "release-${_RELEASE}" || exit 1
        # If it is remote, error out for manual correction
        else
            log_term 0 "Remote branch 'release-${_RELEASE}' exists for '${_REPOSITORY}'"
            log_term 0 "You need to fix this manually."
            log_term 0 "git push origin :release-${_RELEASE}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            exit 1
        fi
    # If we get two or more lets log a warning and continue
    #+ In this case I am assuming a re-release of an aborted release
    #+ Best bet is to check out the brranch anyhow and continue
    #+ If this assumption proves to be false, further logic may need to be ncluded here
    else
        git checkout "release-${_RELEASE}" || exit 1
        git submodule update --init --recursive || exit 1
        log_term 0 "Local and remote branches 'release-${_RELEASE}' exists for '${_REPOSITORY}'"
        log_term 0 "Attempting to continue with unknown consequences."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    fi
}

delete_release_branch () {
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    if [ "${_REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "You must specify a repository!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "You must specify a release!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    # Ensure the repository exists in the repository path
    if [ ! -d "${REPOSITORY_PATH}"/"${_REPOSITORY}" ]; then
        log_term 0 "Repository '${_REPOSITORY}' not chekcout out in repository path '${REPOSITORY_PATH}'!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1
    git checkout develop || exit 1
    git branch --delete "release-${_RELEASE}" || exit 1
    git push origin --delete "release-${_RELEASE}" || exit 1
}

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
        log_term 0 "Closing milestone ${_MILESTONE_NUMBER} for ${_REPOSITORY}"
        _MILESTONE_NUMBER=$(ghi milestone --state closed "${_MILESTONE_NUMBER}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"  | cut -s -d'#' -f 2 | cut -d':' -f 1)
    # Finally create the milestone as it does not appear to exist
    #+ Do not crete if we are closing
    elif [ "${_MILESTONE_NUMBER:-NULL}" == 'NULL' ] && [ "${_CLOSE_MILESTONE:-NULL}" == 'NULL'  ]; then
        log_term 0 "Creating milestone ${_MILESTONE} for ${_REPOSITORY}"
        _MILESTONE_NUMBER=$(ghi milestone --message "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"  | cut -d'#' -f 2 | cut -d' ' -f 1)
    fi
    echo "${_MILESTONE_NUMBER}"
    return
}

create_milestones () {
    local _RELEASE="${1}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
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
        local _MILESTONE; _MILESTONE=$(get_set_milestone "${_RELEASE}" "${REPOSITORY}")
        log_term 1 "Got milestone number \"${_MILESTONE}\"."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        let _COUNT=${_COUNT}+1
    done
    unset REPOSITORY MILESTONE_REPOSITORY_ARRAY
}

close_milestones () {
    local _RELEASE="${1}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
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
        local _MILESTONE; _MILESTONE=$(get_set_milestone "${_RELEASE}" "${REPOSITORY}" "Close")
        log_term 1 "Got milestone number \"${_MILESTONE}\"."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        let _COUNT=${_COUNT}+1
    done
    unset REPOSITORY MILESTONE_REPOSITORY_ARRAY
}

get_release_issue () {
    test_for_ghi
    local _REPOSITORY="${1}"
    local _ISSUE_TITLE="${2}"
    local _MILESTONE="${3}"
    local _ISSUE_NUMBER
    if [ "${_MILESTONE:-NULL}" == 'NULL' ]; then
        _ISSUE_NUMBER=$(ghi list --state open --no-pulls -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" | grep "${_ISSUE_TITLE}" | cut -d ' ' -f 3)
    else
        _ISSUE_NUMBER=$(ghi list --state open --no-pulls --milestone "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" | grep "${_ISSUE_TITLE}" | cut -d ' ' -f 3)
    fi
    log_term 1 "Got release issue number(s): \"${_ISSUE_NUMBER}\"."
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    local _ISSUE_COUNT=0
    for ISSUE in ${_ISSUE_NUMBER}; do
        log_term 3 "Got issue '${ISSUE}'"
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
        _ISSUE_NUMBER=$(echo "${_ISSUE_NUMBER}" | cut -d ' ' -f 1)
        log_term 1 "Warning: Got \"${_ISSUE_COUNT}\" issue numbers. Returning only the first: \"${_ISSUE_NUMBER}\"."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    fi
    echo "${_ISSUE_NUMBER}"
    return 0
}

file_issue () {
    test_for_ghi
    local _REPOSITORY="${1}"
    local _ISSUE_TITLE="${2}"
    local _ISSUE_COMMENT="${3}"
    local _MILESTONE="${4}"
    log_term 1 "Filing release issue for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    # We do not need multiple release issues
    _ISSUE_EXISTS=$(get_release_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_MILESTONE}")
    if [ $? == 0 ]; then
        log_term 2 "Release issue exists. Returned: '${_ISSUE_EXISTS}'. Skipping 'file_issue'."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    elif [ "${_MILESTONE:-NULL}" == 'NULL' ]; then
        ghi open --message "${_ISSUE_COMMENT}" "${_ISSUE_TITLE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" > /dev/null 2>&1
    else
        ghi open --message "${_ISSUE_COMMENT}" "${_ISSUE_TITLE}" --milestone "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" > /dev/null 2>&1
    fi
}

close_issue () {
    test_for_ghi
    local _REPOSITORY="${1}"
    local _ISSUE_TITLE="${2}"
    local _ISSUE_COMMENT="${3}"
    local _MILESTONE="${4}"
    log_term 0 "Closing release issue for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    # Check to see if an issue exists for us to close
    _ISSUE_NUMBER=$(get_release_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_MILESTONE}")
    if [ $? != 0 ]; then
        log_term 1 "Warning: 'get_release_issue' returned: '${_ISSUE_NUMBER}'. Skipping 'close_issue'."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    else
        ghi close --message "${_ISSUE_COMMENT}" "${_ISSUE_NUMBER}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"
    fi
}

check_in_changes () {
    test_for_hub
    local _REPOSITORY=${1}
    local _MESSAGE=${2}
    local _FILE=${3}
    if [ "${_FILE:-NULL}" == 'NULL' ]; then
        local _FILE='.'
    fi
    if [ "${NON_INTERACTIVE:-NULL}" == 'NULL' ]; then
        log_term 0 "Check in changes for \"${_REPOSITORY}\" to: \"${_FILE}\"? [Y/n]"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        read -r CONTINUE
    else
        CONTINUE='y'
    fi
    if [ ${CONTINUE:-y} == "Y" ] || [ ${CONTINUE:-y} == "y" ]; then
        log_term 1 "\nChecking in chenges to '${_FILE}' for \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        cd "${REPOSITORY_PATH}/${_REPOSITORY}" && git add ${_FILE}
        cd "${REPOSITORY_PATH}/${_REPOSITORY}" && git commit -m "${_MESSAGE} [skip ci]"
        cd "${REPOSITORY_PATH}/${_REPOSITORY}" && git push
    fi
}

# Set restrictions for a branch on a repository
#+ If ${3} is not passed, set permissions to require code reviews
#+ If ${3} is passed, remove code review requirement, but restrict action to repository owners (or orginization owners)
# NOTE: This is a blind function. It will not preserve existing permissoins.
repository_set_permissions () {
    local _REPOSITORY=${1}
    local _BRANCH=${2}
    local _UNSET=${3}

    # Set up GitHub PUT data to:
    #+ Require code reviews, includig owners
    #+ Disable checks
    #+ Disable users and teams restrictions
    REQUIRE_PULL_REQUEST_REVIEW=$(cat <<EOH
{
  "required_pull_request_reviews": {
    "include_admins": true
  },
  "required_status_checks": null,
  "restrictions": null
}
EOH
)

    # Set up GitHub PUT data to:
    #+ Disable code reviews, includig owners
    #+ Disable checks
    #+ Restrict operations to orginization and repository administrators
    RESTRICT_TO_OWNERS=$(cat <<EOH
{
  "required_pull_request_reviews": null,
  "required_status_checks": null,
  "restrictions": {
    "users": [
    ],
    "teams": [
    ]
  }
}
EOH
)

    if [ "${_UNSET:-NULL}" == 'NULL' ]; then
        DATA_BINARY="${REQUIRE_PULL_REQUEST_REVIEW}"
        log_term 1 "\nSetting repository permissions to require code reviews for \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    else
        DATA_BINARY="${RESTRICT_TO_OWNERS}"
        log_term 1 "\nSetting repository permissions to disable code reviews for \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    fi

    log_term 1 "\nSetting repository permissions for \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    # Set restrictions on the named branch to require pull-requests
    curl --silent -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" -H "Accept: application/vnd.github.loki-preview+json" -H 'Content-Type: application/json' --request PUT --data-binary "${DATA_BINARY}" https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/branches/"${_BRANCH}"/protection > /dev/null 2>&1
}

# Set up a repository for a release
# A git ref (hash, branch, tag, release, etc) can be specified to start the release for
repository_setup_release () {
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    local _GIT_REF="${3}"
    if [ "${_REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    # Ensure the repository exists in the repository path
    # This will check out the develop branch
    if [ ! -d "${REPOSITORY_PATH}"/"${_REPOSITORY}" ]; then
        log_term 1 "Repository '${_REPOSITORY}' not cheked out out in repository path '${REPOSITORY_PATH}'!"
        log_term 1 "\nCloning repository: \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        # If a git ref was specified, clone at that ref
        if [ "${_GIT_REF:-NULL}" != 'NULL' ]; then
            clone_repository "${_REPOSITORY}" "${_GIT_REF}" || exit 1
        else
            clone_repository "${_REPOSITORY}" || exit 1
        fi

    fi
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1

    # Create a release branch for us to work on
    create_release_branch "${_REPOSITORY}" "${_RELEASE}"

    # This is a special edit to update the pinned version number to the current $RELEASE for the consul and vpc modules in nubis-deploy
    if [ "${_REPOSITORY}" == 'nubis-deploy' ]; then
        edit_deploy_templates "${_RELEASE}"
    fi

    # File release issue
    local _ISSUE_TITLE="Tag ${_RELEASE} release"
    local _ISSUE_COMMENT="Tag a release of the ${_REPOSITORY} repository for the ${_RELEASE} release of the Nubis project."
    local _MILESTONE; _MILESTONE=$(get_set_milestone "${_RELEASE}" "${_REPOSITORY}")
    file_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_ISSUE_COMMENT}" "${_MILESTONE}"
}

repository_complete_release () {
    test_for_github_changelog_generator
    test_for_hub
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    if [ "${_REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "Repository required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    if [ ${#CHANGELOG_GITHUB_TOKEN} == 0 ]; then
        # https://github.com/koalaman/shellcheck/wiki/SC2016
        # shellcheck disable=SC2016
        log_term 0 'You must have ${CHANGELOG_GITHUB_TOKEN} set'
        log_term 0 'https://github.com/skywinder/github-changelog-generator#github-token'
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    # Ensure the repository exists in the repository path
    if [ ! -d "${REPOSITORY_PATH}"/"${_REPOSITORY}" ]; then
        log_term 0 "Repository '${_REPOSITORY}' not chekced out out in repository path '${REPOSITORY_PATH}'!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1

    # Update the CHANGELOG and make a pull-request, rebasing first to ensure a clean repository
    github_changelog_generator --future-release "${_RELEASE}" "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"
    git add CHANGELOG.md
    git commit -m "Update CHANGELOG for ${_RELEASE} release [skip ci]"
    git push -u origin "release-${_RELEASE}"
    # GitHub is sometimes a bit slow here
    sleep 3
    local _MILESTONE; _MILESTONE=$(get_set_milestone "${_RELEASE}" "${_REPOSITORY}" 'close')
    hub pull-request -m "Update CHANGELOG for ${_RELEASE} release [skip ci]" -h "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"":release-${_RELEASE}" -b "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"':master' || exit 1

    # Switch to the master branch, merge the pull-request and then tag the release
    log_term 1 "\nMerging release into master branch for \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    git checkout master || exit 1
    git pull || exit 1
    git merge --no-ff -m "Merge release branch into master [skip ci]" "release-${_RELEASE}" || exit 1
    git push origin HEAD:master || exit 1
    log_term 1 "\nTaging release for \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    git tag -s "${_RELEASE}" -f -m"Signed ${_RELEASE} release" || exit 1
    git push --tags -f || exit 1
    # GitHub is sometimes a bit slow here
    sleep 3

    # Check to see if we already have a release on GitHub
    _RELEASE_ID=$(curl --silent -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" --request GET https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/releases/tags/"${_RELEASE}" | jq --raw-output .id)

    # If we have a release we need to delete it before recreating it
    if [ "${_RELEASE_ID:-null}" != 'null' ]; then
        curl --silent -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" --request DELETE https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/releases/"${_RELEASE_ID}"
    fi

    # Now we can create the release
    curl --silent -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" --request POST --data "{\"tag_name\": \"${_RELEASE}\"}" https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/releases

    # Close release issue and milestone (if it exists and is open)
    local _ISSUE_TITLE="Tag ${_RELEASE} release"
    local _ISSUE_COMMENT="Release of repository ${_REPOSITORY} for the ${_RELEASE} release complete. Closing issue."
    local _MILESTONE; _MILESTONE=$(get_set_milestone "${_RELEASE}" "${_REPOSITORY}" 'close')
    close_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_ISSUE_COMMENT}" "${_MILESTONE}"

    # Create pull-request to merge into develop
    hub pull-request -m "Merge ${_RELEASE} release into develop. [skip ci]" -h "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"":release-${_RELEASE}" -b "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"':develop' # || exit 1

    # Remove code review restriction from develop branch
    repository_set_permissions "${_REPOSITORY}" 'develop' 'unset'

    # Switch to the develop branch and merge the pull-request
    log_term 1 "\nMerging release into develop branch for \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    git checkout develop || exit 1
    git pull || exit 1
    git merge --no-ff -m "Merge release branch into develop [skip ci]" "release-${_RELEASE}" || exit 1
    git push origin HEAD:develop || exit 1

    # Replace code review restriction on develop branch
    repository_set_permissions "${_REPOSITORY}" 'develop'

    # Remove the (now) unnecessary release branch
    delete_release_branch "${_REPOSITORY}" "${_RELEASE}"
}
