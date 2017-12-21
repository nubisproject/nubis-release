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

# Blocking function to ensure we have enough available API calls to complete a task.
# If called with a number of calls required, will block until that number is available,
#+ otherwise defaults to 20 available calls.
# Example Usage: github_api_limit_check '50'
# echo 'https://nubis-automation:d6ea175001241dbd405809338073ce3e38a45386@github.com' >> ~/.git-credentials
github_api_limit_check () {
    local _LIMIT_REQUESTED _DEFAULT_REQUESTED _LIMIT_REMAINING _SLEEP_SECONDS
    _LIMIT_REQUESTED="${1}"
    _DEFAULT_REQUESTED='20'

    while [ "${_LIMIT_REMAINING:-0}" -lt "${_LIMIT_REQUESTED:-$_DEFAULT_REQUESTED}" ]; do
        log_term 2 "Querying GitHub API for rate limit"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        _LIMIT_REMAINING=$(curl --silent -H "Authorization: token ${GITHUB_OATH_TOKEN}" --request GET https://api.github.com/rate_limit | jq --raw-output '.["resources"]["core"]["remaining"]')

        log_term 2 "Got \"${_LIMIT_REMAINING}\" remaining requests for \"${_LIMIT_REQUESTED:-$_DEFAULT_REQUESTED}\" desired"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

        # If we do not have enough requests remaining, sleep before trying again
        if [ "${_LIMIT_REMAINING:-0}" -lt "${_LIMIT_REQUESTED:-$_DEFAULT_REQUESTED}" ]; then
            _SLEEP_SECONDS=10
            log_term 2 "Sleeping \"${_SLEEP_SECONDS}\" seconds before trying again"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            sleep "${_SLEEP_SECONDS}"
        fi
    done
}

# This function will curl for the GitHub URL passed as ${1}
# Outputs what curl gets returned
get_data () {
    local _GITHUB_URL="${1}"
    local _INTERNAL_DATA
    if [ "${GITHUB_OATH_TOKEN:-NULL}" == 'NULL' ];then
        log_term 1 "WARNING: 'GITHUB_OATH_TOKEN' unset. Data may be incomplete."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        github_api_limit_check '1'
        _INTERNAL_DATA=$(curl -s "${_GITHUB_URL}")
        log_term 2 "Get date from: \"${_GITHUB_URL}\""
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    else
        github_api_limit_check '1'
        _INTERNAL_DATA=$(curl -s -H "Authorization: token ${GITHUB_OATH_TOKEN}" "${_GITHUB_URL}")
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
    done < <(if [ "${GITHUB_OATH_TOKEN:-NULL}" == 'NULL' ];then github_api_limit_check '1'; curl -sI "${_GITHUB_URL}"; else curl -sI -H "Authorization: token ${GITHUB_OATH_TOKEN}" "${_GITHUB_URL}"; fi)

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

# This function generates a list of all of the GitHub issues closed for the release.
# Both ${GITHUB_ORGINIZATION} and ${RELEASE_DATES} must be set (see variables.sh)
# Optionaly a file-name may be passed in, otherwise a default file is created in /tmp
# Makes use of the 'collect_data ()' function only.
# Requires two external dependancies: 'jq' and 'json2csv'
# OUTPUTS: A CSV formatted file in ${CSV_FILE}
generate_release_csv () {
    local -r RELEASE_DATES="${1}"
    local _CSV_FILE="${2}"
    if [ ${RELEASE_DATES:-'NULL'} == 'NULL' ]; then
        log_term 0 "\nYou must pass in the release dates to generate the CSV file." -e
        exit 1
    fi
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
    local _PARSE_ISSUE_LIST; _PARSE_ISSUE_LIST=$(echo "${_ISSUE_LIST}" | jq --compact-output '.["items"][] | {title: .title, html_url: .html_url, user: .user.login}')
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
clone_repository () {
    local _REPOSITORY="${1}"
    if [ "${_REPOSITORY:-NULL}" == 'NULL' ]; then
        log_term 0 "You must specify a repository!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    # If the repository exists in the repository path, remove it
    if [ -d "${REPOSITORY_PATH}/${_REPOSITORY}" ]; then
        log_term 1 "Directory \"${REPOSITORY_PATH}/${_REPOSITORY}\" already exists. Removing!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        rm -rf "${REPOSITORY_PATH:?'REPOSITORY_PATH is unset'}/${_REPOSITORY:?'REPOSITORY is unset'}" || exit 1

    fi
    # If the repository path does not exist, create it
    if [ ! -d "${REPOSITORY_PATH}" ]; then
        log_term 1 "Directory \"${REPOSITORY_PATH}\" does not exist. Creating."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        mkdir "${REPOSITORY_PATH:?'REPOSITORY_PATH is unset'}" || exit 1

    fi
    cd "${REPOSITORY_PATH}" || exit 1
    github_api_limit_check '1'
    log_term 2 "Looking up repository clone_url"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    GITHUB_URL=$(curl --silent -H "Authorization: token ${GITHUB_OATH_TOKEN}" "https://api.github.com/repos/${GITHUB_ORGINIZATION}/${_REPOSITORY}" | jq --raw-output '.clone_url')
    if [ ${GITHUB_URL} == 'null' ]; then
        log_term 0 "Unable to look up clone-url from GitHub. Aborting..."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    log_term 3 "got clone_url \"${GITHUB_URL}\""
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    log_term 2 "Cloning repository with url \"${GITHUB_URL}\""
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    git clone "${GITHUB_URL}" || exit 1
    cd "${_REPOSITORY}" || exit 1
    # If a patch version was specified check out at that release.
    #+ If the repository has a patch branch, check out that branch.
    #+ Generally a patch is a previous releas tag (ie: v2.0.2)
    #+ Otherwise assume this is a normal release and check out the develop branch.
    if [ "${RELEASE_TO_PATCH:-NULL}" != 'NULL' ]; then
        local _PATCH_BRANCH_TEST; _PATCH_BRANCH_TEST=$(git branch -r --list "origin/patch-${RELEASE_TO_PATCH:-NULL}")
        if [ "${#_PATCH_BRANCH_TEST}" != 0 ]; then
            log_term 2 "Checking out \"patch-${RELEASE_TO_PATCH}\" branch"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            git checkout "patch-${RELEASE_TO_PATCH}" || exit 1
        else
            log_term 2 "Checking out \"${RELEASE_TO_PATCH}\" branch"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            git checkout "${RELEASE_TO_PATCH}" || exit 1
        fi
    else
        log_term 2 "Checking out \"develop\" branch"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        git checkout develop || exit 1
    fi
    # Grab any submodules
    log_term 2 "Updating git submodules"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    git submodule update --init --recursive || exit 1
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
    if [ "${BRANCH_EXISTS:-0}" == 0 ]; then
        log_term 2 "Checking out new branch \"release-${_RELEASE}\""
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        git checkout -b "release-${_RELEASE}" || exit 1
        log_term 2 "Updating submodules for branch \"release-${_RELEASE}\""
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        git submodule update --init --recursive || exit 1
        log_term 2 "Setting upstream for branch \"release-${_RELEASE}\""
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        git push --set-upstream origin "release-${_RELEASE}" || exit 1
    # If we get only one
    elif [ "${BRANCH_EXISTS}" == 1 ]; then
        # Lets try to determine if it is a remote branch
        BRANCH_REMOTE=$(git branch -a | grep -c "/release-${_RELEASE}")
        # If not, assume it is local and attempt to set upstream tracking
        if [ "${BRANCH_REMOTE}" == 0 ]; then
            log_term 2 "Attempting to set upstream for existing branch \"release-${_RELEASE}\""
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
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
    #+ If this assumption proves to be false, further logic may need to be included here
    else
        log_term 2 "Checking out new branch \"release-${_RELEASE}\""
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        git checkout "release-${_RELEASE}" || exit 1
        log_term 2 "Updating submodules for branch \"release-${_RELEASE}\""
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
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
        github_api_limit_check '1'
        ghi milestone --list -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" | grep "${_MILESTONE}" | cut -d':' -f 1 | sed -e 's/^[[:space:]]*//'
    }
    milestone_closed () {
        github_api_limit_check '1'
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
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        github_api_limit_check '1'
        _MILESTONE_NUMBER=$(ghi milestone --state closed "${_MILESTONE_NUMBER}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"  | cut -s -d'#' -f 2 | cut -d':' -f 1)
    # Finally create the milestone as it does not appear to exist
    #+ Do not crete if we are closing
    elif [ "${_MILESTONE_NUMBER:-NULL}" == 'NULL' ] && [ "${_CLOSE_MILESTONE:-NULL}" == 'NULL'  ]; then
        log_term 0 "Creating milestone ${_MILESTONE} for ${_REPOSITORY}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        github_api_limit_check '1'
        _MILESTONE_NUMBER=$(ghi milestone --message "${_MILESTONE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"  | cut -d'#' -f 2 | cut -d' ' -f 1)
    fi
    echo "${_MILESTONE_NUMBER}"
    return
}

create_milestones () {
    local _RELEASE="${1}"
    shift
    declare -a MILESTONE_REPOSITORY_ARRAY="${@}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae nubber required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
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
    shift
    declare -a MILESTONE_REPOSITORY_ARRAY="${@}"
    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae nubber required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
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
        github_api_limit_check '1'
        _ISSUE_NUMBER=$(ghi list --state open --no-pulls -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" | grep "${_ISSUE_TITLE}" | cut -d ' ' -f 3)
    else
        github_api_limit_check '1'
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
    # https://github.com/koalaman/shellcheck/wiki/SC2181
    # shellcheck disable=SC2181
    if [ $? == 0 ]; then
        log_term 2 "Release issue exists. Returned: '${_ISSUE_EXISTS}'. Skipping 'file_issue'."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    elif [ "${_MILESTONE:-NULL}" == 'NULL' ]; then
        github_api_limit_check '1'
        ghi open --message "${_ISSUE_COMMENT}" "${_ISSUE_TITLE}" -- "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}" > /dev/null 2>&1
    else
        github_api_limit_check '1'
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
    # https://github.com/koalaman/shellcheck/wiki/SC2181
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then
        log_term 1 "Warning: 'get_release_issue' returned: '${_ISSUE_NUMBER}'. Skipping 'close_issue'."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    else
        github_api_limit_check '1'
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
    UPDATE_BRANCH_PROTECTION=$(cat <<EOH
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "continuous-integration/travis-ci"
    ]
  },
  "required_pull_request_reviews": {
    "dismissal_restrictions": {
      "users": [
      ],
      "teams": [
      ]
    },
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true
  },
  "enforce_admins": true,
  "restrictions": null
}
EOH
)

    if [ "${_UNSET:-NULL}" == 'NULL' ]; then
        log_term 1 "\nSetting repository permissions to enable branch protection for \"${_REPOSITORY}/${_BRANCH}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        # Set restrictions on the named branch to require pull-requests
        github_api_limit_check '1'
        curl --silent -H "Authorization: token ${GITHUB_OATH_TOKEN}" -H "Accept: application/vnd.github.loki-preview+json" -H 'Content-Type: application/json' --request PUT --data-binary "${UPDATE_BRANCH_PROTECTION}" https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/branches/"${_BRANCH}"/protection > /dev/null 2>&1
    else
        log_term 1 "\nSetting repository permissions to disable branch protection for \"${_REPOSITORY}/${_BRANCH}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        # Set restrictions on the named branch to require pull-requests
        github_api_limit_check '1'
        curl --silent -H "Authorization: token ${GITHUB_OATH_TOKEN}" -H "Accept: application/vnd.github.loki-preview+json" -H 'Content-Type: application/json' --request DELETE https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/branches/"${_BRANCH}"/protection > /dev/null 2>&1
    fi

}

generate_changelog () {
    test_for_github_changelog_generator
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
    if [ ${#GITHUB_OATH_TOKEN} == 0 ]; then
        log_term 0 "You must have \${GITHUB_OATH_TOKEN} set"
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
    # Start by counting issues, pull-requests and tags. Then do some math in an attempt to
    #+ get clost to the number of API requests required.

    # Count the number of tags in the repository
    local _TAG_COUNT; _TAG_COUNT=$(git tag -l | grep -c ^)
    log_term 2 "Found ${_TAG_COUNT} tags"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Set up GitHub API URL for searching closed issues in this repository
    local _GITHUB_URL="https://api.github.com/search/issues?q=is:issue+sort:created-desc+is:closed+repo:${GITHUB_ORGINIZATION}/${_REPOSITORY}"
    log_term 1 "Setting _GITHUB_URL to: \"${_GITHUB_URL}\""
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Collect the JSON list of issues
    local _ISSUE_LIST; _ISSUE_LIST=$(collect_data "${_GITHUB_URL}")
    log_term 2 "Collecting _ISSUE_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Count the number of closed issues in the repository
    local _ISSUE_COUNT; _ISSUE_COUNT=$(echo "${_ISSUE_LIST}" | jq --compact-output '.["items"][].number' | grep -c ^)
    log_term 2 "Found ${_ISSUE_COUNT} issues"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Set up the GtHub API URL for searching merged pull-requests
    local _GITHUB_URL="https://api.github.com/search/issues?q=is:pr+sort:created-desc+is:merged+repo:${GITHUB_ORGINIZATION}/${_REPOSITORY}"
    log_term 1 "Setting _GITHUB_URL to: \"${_GITHUB_URL}\""
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Collect the JSON list of pull-requests
    local _PULL_REQUEST_LIST; _PULL_REQUEST_LIST=$(collect_data "${_GITHUB_URL}")
    log_term 2 "Collecting _PULL_REQUEST_LIST"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Count the number of merged pull-requests in the repository
    local _PULL_REQUEST_COUNT; _PULL_REQUEST_COUNT=$(echo "${_PULL_REQUEST_LIST}" | jq --compact-output '.["items"][].number' | grep -c ^)
    log_term 2 "Found ${_PULL_REQUEST_COUNT} pull-requests"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Add up all API requests to pass to the limit_check function
    # Adds up the requests in the following way:
    #+ Queries to page through pull-requests and tags (100 results per page)
    #+ Tags (one query per tag for date created)
    #+ Issues (One query per issue and one query for closed date)
    #+ Pull-Requests (One query per merged request and one query for merged time)
    # This does not account for issues that are filtered out based on tags,
    #+ therefore this number is slightly higher that tha actual required number,
    #+ but close enough without making all the queries ourselves.
    local _REQUESTS_PER_PAGE _TAG_PAGE_COUNT _ISSUES_PAGE_COUNT _API_REQUEST_COUNT
    _REQUESTS_PER_PAGE='100'
    _TAG_PAGE_COUNT=$(( (61 + 140 + 100 - 1) / 100 ))
    _ISSUES_PAGE_COUNT=$(( (${_ISSUE_COUNT} + ${_PULL_REQUEST_COUNT} + ${_REQUESTS_PER_PAGE} - 1) / ${_REQUESTS_PER_PAGE} ))
    COUNT=$(( 3 + 1 + 20 + (61 * 2) + (140 * 2) ))
    _API_REQUEST_COUNT=$(( ${_TAG_PAGE_COUNT} + ${_ISSUES_PAGE_COUNT} + ${_TAG_COUNT} + (${_ISSUE_COUNT} * 2) + (${_PULL_REQUEST_COUNT} *2) ))
    log_term 2 "Calculated ${_API_REQUEST_COUNT} api requests for ghangelog generation"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    github_api_limit_check "${_API_REQUEST_COUNT}"
    github_changelog_generator --token "${GITHUB_OATH_TOKEN}" --future-release "${_RELEASE}" "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"
    git add CHANGELOG.md
    git commit -m "Update CHANGELOG for ${_RELEASE} release [skip ci]"
    git push -u origin "release-${_RELEASE}"
    # GitHub is sometimes a bit slow here
    sleep 3
}

merge_release_branch_to_named_branch () {
    test_for_hub
    local _REPOSITORY="${1}"
    local _RELEASE="${2}"
    local _BRANCH="${3}"
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
    if [ "${_BRANCH:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi
    # Ensure the repository exists in the repository path
    if [ ! -d "${REPOSITORY_PATH}"/"${_REPOSITORY}" ]; then
        log_term 0 "Repository '${_REPOSITORY}' not chekced out out in repository path '${REPOSITORY_PATH}'!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1

    # Create a pull-request to merge the release branch into the named branch
    github_api_limit_check '1'
    hub pull-request -m "Update CHANGELOG for ${_RELEASE} release [skip ci]" -h "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"":release-${_RELEASE}" -b "${GITHUB_ORGINIZATION}"/"${_REPOSITORY}":"${_BRANCH}" || exit 1

    # Remove code review restriction from the named branch
    repository_set_permissions "${_REPOSITORY}" "${_BRANCH}" 'unset'

    # Switch to the named branch and merge the pull-request
    log_term 1 "\nMerging release into the ${_BRANCH} branch for \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    git checkout "${_BRANCH}" || exit 1
    git pull || exit 1
    OUTPUT=$(git merge --no-ff -m "Merge release branch into ${_BRANCH} branch [skip ci]" "release-${_RELEASE}")
    # If we are doing a patch release we will get some merge conflicts, lets
    #+ attempt to resolve them automatically.
    # We start by aborting the above attempted merge (resetting files) so we do
    #+ not need to edit the merge conflicts manually.
    # Then we retry the merge with the '--strategy recursive -X theirs' options
    #+ to force our merge to win.
    # There is a small risk to this as we may unintentionally blow away future
    #+ (past the base release point) changes on the branch.
    # Due to the risk, we will be very perscrptive about the files we will allow
    #+ conflicts in and still go ahead with the change.
    # This should limit the damage to known locations.
    # https://github.com/koalaman/shellcheck/wiki/SC2181
    # shellcheck disable=SC2181
    if [ "${?}" != '0' ]; then
        log_term 0 "ERROR: Got conflict merging into ${_BRANCH} branch. Attempting to recover..."
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        # Make sure we only have only one conflict
        if [ "$(echo "$OUTPUT" | grep -c 'CONFLICT')" == '1' ]; then
            # In any repository we run a risk of errors in the changelog due to the
            #+ way github_changelog_generator reorders issues on subesequent runs
            # I (jd) have decided that I do not care enough about the changelog to
            #+ manually resolve merge conflicts in it
            # Lets simply take the most recent version and treat it as correct.
            # As it is a changelog there is zero risk for breaking deployments with
            #+ this strategy as we do not progromatically rely on the changelog.
            if [ "$(echo "$OUTPUT" | grep 'CONFLICT' | grep -c 'CHANGELOG.md')" == '1' ]; then
                    git merge --abort || exit 1
                    git merge --no-ff --strategy recursive -X theirs -m "Merge release branch into ${_BRANCH} [skip ci]" "release-${_RELEASE}" || exit 1
            fi
            # Make sure the conflict is in the nubis/builder/project.json file
            if [ "$(echo "$OUTPUT" | grep 'CONFLICT' | grep -c 'nubis/builder/project.json')" == '1' ]; then
                git merge --abort || exit 1
                git merge --no-ff --strategy recursive -X theirs -m "Merge release branch into develop [skip ci]" "release-${_RELEASE}" || exit 1
            fi
        else
            log_term 0 'ERROR: Unable to repair merge conflict. Aborting build.'
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            exit 1
        fi
    fi

    git push origin HEAD:"${_BRANCH}" || exit 1

    # Replace code review restriction on named branch
    repository_set_permissions "${_REPOSITORY}" "${_BRANCH}"
}

tag_and_release_repository () {
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
    if [ ${#GITHUB_OATH_TOKEN} == 0 ]; then
        log_term 0 "You must have \${GITHUB_OATH_TOKEN} set"
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

    log_term 1 "\nTaging release for \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
# TODO: Fix signed tags for nubis-automation user
#    git tag -s "${_RELEASE}" -f -m"Signed ${_RELEASE} release" || exit 1
    git tag "${_RELEASE}" -f -m"Tag ${_RELEASE} release" || exit 1
    git push --tags -f || exit 1
    # GitHub is sometimes a bit slow here
    sleep 3

    # Check to see if we already have a release on GitHub
    github_api_limit_check '1'
    _RELEASE_ID=$(curl --silent -H "Authorization: token ${GITHUB_OATH_TOKEN}" --request GET https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/releases/tags/"${_RELEASE}" | jq --raw-output .id)

    # If we have a release we need to delete it before recreating it
    if [ "${_RELEASE_ID:-null}" != 'null' ]; then
        log_term 1 "\nFound existing release with id:\"${_RELEASE_ID}\". Deleting..." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        github_api_limit_check '1'
        curl --silent -H "Authorization: token ${GITHUB_OATH_TOKEN}" --request DELETE https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/releases/"${_RELEASE_ID}" > /dev/null 2>&1
    fi

    # Now we can create the release
    log_term 1 "\nCreating release on github for \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    github_api_limit_check '1'
    curl --silent -H "Authorization: token ${GITHUB_OATH_TOKEN}" --request POST --data "{\"tag_name\": \"${_RELEASE}\"}" https://api.github.com/repos/"${GITHUB_ORGINIZATION}"/"${_REPOSITORY}"/releases > /dev/null 2>&1

    # Close release issue and milestone (if it exists and is open)
    local _ISSUE_TITLE="Tag ${_RELEASE} release"
    local _ISSUE_COMMENT="Release of repository ${_REPOSITORY} for the ${_RELEASE} release complete. Closing issue."
    local _MILESTONE; _MILESTONE=$(get_set_milestone "${_RELEASE}" "${_REPOSITORY}" 'close')
    close_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_ISSUE_COMMENT}" "${_MILESTONE}"
}

# Set up a repository for a release
repository_setup_release () {
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

    # Check out the repository in the repository path
    # This will check out the develop or patch branch
    log_term 1 "\nCloning repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    clone_repository "${_REPOSITORY}" || exit 1
    cd "${REPOSITORY_PATH}"/"${_REPOSITORY}" || exit 1

    # Create a release branch for us to work on
    log_term 1 "\nCreatng release branch for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    create_release_branch "${_REPOSITORY}" "${_RELEASE}"

    # This is a special edit to update the pinned version number to the current ${_RELEASE}
    #+ for the consul and vpc modules in nubis-deploy
    if [ "${_REPOSITORY}" == 'nubis-deploy' ]; then
        log_term 1 "\nEditing deploy templates for repository: \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        edit_deploy_templates "${_RELEASE}"
    fi

    # File release issue
    local _ISSUE_TITLE="Tag ${_RELEASE} release"
    local _ISSUE_COMMENT="Tag a release of the ${_REPOSITORY} repository for the ${_RELEASE} release of the Nubis project."
    local _MILESTONE; _MILESTONE=$(get_set_milestone "${_RELEASE}" "${_REPOSITORY}")
    log_term 1 "\nFiling release issue for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    file_issue "${_REPOSITORY}" "${_ISSUE_TITLE}" "${_ISSUE_COMMENT}" "${_MILESTONE}"
}

repository_complete_release () {
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

    # Generate the changelog for the release
    log_term 1 "\nGenerating changelog for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    generate_changelog "${_REPOSITORY}" "${_RELEASE}"

    # Do not merge back into master for patch release
    if [ "${RELEASE_TO_PATCH:-NULL}" == 'NULL' ]; then
        # Merge release branch into the master branch
        log_term 1 "\nMerging release branch into master branch for repository: \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        merge_release_branch_to_named_branch "${_REPOSITORY}" "${_RELEASE}" 'master'
    fi

    # Tag the release and push the release to GitHub
    log_term 1 "\nTagging and releasing for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    tag_and_release_repository "${_REPOSITORY}" "${_RELEASE}"

    # Do not merge back into develop for patch release
    if [ "${RELEASE_TO_PATCH:-NULL}" == 'NULL' ]; then
        # Merge release branch into the develop branch
        log_term 1 "\nMerging release branch into develop branch for repository: \"${_REPOSITORY}\"." -e
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        merge_release_branch_to_named_branch "${_REPOSITORY}" "${_RELEASE}" 'develop'
    fi

    # Remove the (now) unnecessary release branch
    log_term 1 "\nRemoving release branch for repository: \"${_REPOSITORY}\"." -e
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    delete_release_branch "${_REPOSITORY}" "${_RELEASE}"
}
