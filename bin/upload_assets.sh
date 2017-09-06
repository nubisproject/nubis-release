#!/bin/bash
#

push-files () {
    local _FILES_LIST _S3_PATH _S3_BUCKET _BUCKETS _S3_MULTI_REGION _AWS_DEFAULT_REGION
    _FILES_LIST="${1}"
    _S3_PATH="${2}"
    _S3_BUCKET="${3}"
    _S3_MULTI_REGION="${4}"
    _AWS_DEFAULT_REGION="${5}"

    # Make sure we have at least one bucket
    if [ "${#_FILES_LIST[@]}" == '0' ]; then
        log_term 0 "ERROR: No file list specifyed!"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 upload_assets help
        exit 1
    fi

    # FILE=/path/to/file/to/upload.tar.gz
    log_term 0 "Uploading ${#_FILES_LIST[@]} files to ${_S3_PATH}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

    # Determine the destination buckets
    declare -a _BUCKETS=( "${_S3_BUCKET}" )
    if [ "${_S3_MULTI_REGION:-0}" == '1' ]; then
        local _S3_BUCKET_REGIONS
        # This is only used for gathering a list of available regions
        if [ "${_AWS_DEFAULT_REGION:-NULL}" == 'NULL' ]; then
            _AWS_DEFAULT_REGION='us-west-2'
        fi
        _S3_BUCKET_REGIONS=$("${AWS_VAULT_COMMAND[@]}" aws --region "${_AWS_DEFAULT_REGION}" ec2 describe-regions --query 'Regions[].{Name:RegionName}' --output text | sort)
        # https://github.com/koalaman/shellcheck/wiki/SC2181
        # shellcheck disable=SC2181
        if [ "${?}" != '0' ]; then
            log_term 0 "ERROR: AWS region lookup failed"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            exit 1
        fi
        log_term 2 "Got S3_BUCKET_REGIONS ${_S3_BUCKET_REGIONS}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        for REGION in ${_S3_BUCKET_REGIONS}; do
            _BUCKETS+=( "${_S3_BUCKET}-${REGION}" )
        done
        unset REGION
    fi

    # Make sure we have at least one bucket
    if [ "${#_BUCKETS[@]}" == '0' ]; then
        log_term 0 "ERROR: No S3 bucket detected!"
        log_term 0 "You must specify either --bucket or --multi-region"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 upload_assets help
        exit 1
    fi

    local _COUNT; _COUNT='1'
    for FILE in "${_FILES_LIST[@]}"; do
        local _FILENAME _FILE_DIR
        _FILENAME=$(basename "${FILE}")
        _FILE_DIR=$(dirname "${FILE}")
        log_term 0 "Uploading: ${_FILENAME} (${_COUNT} of ${#_FILES_LIST[@]})"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

        cd "${_FILE_DIR}" || exit 1

        local _CONTENT_TYPE; _CONTENT_TYPE=$(file --brief --mime-type "${_FILENAME}")
        log_term 2 "Got CONTENT_TYPE: ${_CONTENT_TYPE}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

        local _MD5; _MD5=$(openssl md5 -binary < "${_FILENAME}" | base64)
        log_term 2 "Got MD5: ${_MD5}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

        # Upload the file
        for BUCKET in "${_BUCKETS[@]}"; do
            local _BUCKET_REGION _BUCKET_REGION_ARGS _OUT
            _BUCKET_REGION=$("${AWS_VAULT_COMMAND[@]}" aws s3api get-bucket-location --bucket "${BUCKET}" | jq -r .LocationConstraint)
            log_term 2 "Got BUCKET_REGION: ${_BUCKET_REGION}"
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            if [ "${_BUCKET_REGION:-null}" != "null" ]; then
                _BUCKET_REGION_ARGS=( "--region" "${_BUCKET_REGION}" )
            fi

            log_term 0 " - Uploading to ${BUCKET}: " -n
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

            _OUT=$("${AWS_VAULT_COMMAND[@]}" aws "${_BUCKET_REGION_ARGS[@]}" s3api put-object --bucket "${BUCKET}" --acl public-read --content-md5 "${_MD5}" --content-type "${_CONTENT_TYPE}" --key "${_S3_PATH}/${_FILENAME}" --body "${_FILENAME}" 2>&1) 2> /dev/null
            # https://github.com/koalaman/shellcheck/wiki/SC2181
            # shellcheck disable=SC2181
            if [ "${?}" != '0' ]; then
                log_term 0 "ERROR\n\n${_OUT}" -e
                log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
                exit 1
            else
                log_term 0 "OK"
                log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
            fi
        done
        let _COUNT+='1'
    done
}

# This simply runs 'npm update' to update dependencies
# Call this function with the path to the lambda function
update-lambda-dependencies () {
    local _LAMBDA_FUNCTION; _LAMBDA_FUNCTION="${1}"
    test_for_npm
    log_term 0 "Updating dependencies for lambda: ${_LAMBDA_FUNCTION}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    cd "${REPOSITORY_PATH}"/"${LAMBDA_FUNCTION}" || exit 1
    if [ "$(npm update > /dev/null 2>&1; echo $?)" != '0' ]; then
        log_term 0 "ERROR: 'npm update' failed for lambda function ${_LAMBDA_FUNCTION}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

zip-lambda () {
    local _LAMBDA_FUNCTION; _LAMBDA_FUNCTION="${1}"
    log_term 0 "Packaging lambda:: ${_LAMBDA_FUNCTION}"
    log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
    cd "${REPOSITORY_PATH}"/"${LAMBDA_FUNCTION}" || exit 1
    zip --quiet --recurse-paths "bundles/${_LAMBDA_FUNCTION}.zip" ./* --exclude bundles/
    # https://github.com/koalaman/shellcheck/wiki/SC2181
    # shellcheck disable=SC2181
    if [ "${?}" != '0' ]; then
        log_term 0 "ERROR: 'zip' failed for lambda function ${_LAMBDA_FUNCTION}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        exit 1
    fi
}

push-lambda () {
    local _RELEASE _LAMBDA_LIST _S3_BUCKET _BUCKETS _S3_MULTI_REGION
    _RELEASE="${1}"
    _LAMBDA_LIST="${2}"
    _S3_BUCKET="${3}"
    _S3_MULTI_REGION="${4}"

    if [ "${_RELEASE:-NULL}" == 'NULL' ]; then
        log_term 0 "Relesae number required"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
        $0 help
        exit 1
    fi

    for LAMBDA_FUNCTION in "${_LAMBDA_LIST[@]}"; do
        log_term 0 "Pushing lambda: ${LAMBDA_FUNCTION}"
        log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

        # Ensure the repository exists in the repository path
        if [ ! -d "${REPOSITORY_PATH}"/"${LAMBDA_FUNCTION}" ]; then
            log_term 1 "Repository '${LAMBDA_FUNCTION}' not cheked out out in repository path '${REPOSITORY_PATH}'!"
            log_term 1 "\nCloning repository: \"${LAMBDA_FUNCTION}\"." -e
            log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"

            cd "${REPOSITORY_PATH}" || exit 1
            clone_repository "${LAMBDA_FUNCTION}"
        fi

        # Run 'nom update' for the lambda function
        update-lambda-dependencies "${LAMBDA_FUNCTION}"

        # Create the lambda function bundle
        zip-lambda "${LAMBDA_FUNCTION}"

        # Push the lambda function zip file to the S3 bucket
        push-files "${REPOSITORY_PATH}/${LAMBDA_FUNCTION}/bundles/${LAMBDA_FUNCTION}.zip" "${_RELEASE}/lambda" "${_S3_BUCKET}" "${_S3_MULTI_REGION}"

        # update-lambda-dependencies fetches dependancies and zip-lambda generates
        #+  new zip file, check them in here unless we are on master or develop
        #+  (assume these are test builds)
        local _CURRENT_BRANCH; _CURRENT_BRANCH=$(git branch | cut -d' ' -f 2)
        local _SKIP_BRANCHES="^(master|develop)$"
        local _RELEASE_REGEX="^(v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))-dev$"
        if [[ ! "${_CURRENT_BRANCH}" =~ ${_SKIP_BRANCHES} ]] || [[ "${_RELEASE}" =~ ${_RELEASE_REGEX} ]]; then
            if [ "${_CURRENT_BRANCH}" == 'develop' ]; then
                repository_set_permissions "${LAMBDA_FUNCTION}" 'develop' 'unset'
            fi
            check_in_changes "${LAMBDA_FUNCTION}" "Updated lambda function bundles for ${_RELEASE} release"
            if [ "${_CURRENT_BRANCH}" == 'develop' ]; then
                repository_set_permissions "${LAMBDA_FUNCTION}" 'develop'
            fi
        fi
    done
    unset LAMBDA_FUNCTION
}

upload-assets () {
# Grab and setup called options
while [ "$1" != "" ]; do
    case $1 in
        -b | --bucket )
            # The name of a s3 bucket to upload files to
            S3_BUCKET="${2}"
            shift
        ;;
        -r | --release )
            # The path in the s3 bucket to upload files to
            # This is intended to support versions of these files
            # There should be one path per release
            RELEASE="${2}"
            S3_PATH="${2}"
            shift
        ;;
        -m | --multi-region )
            # Should we upload to multiple regions, using <bucket>-<region> naming
            S3_MULTI_REGION='1'
        ;;

         -h | -H | --help )
            echo -en "$0\n\n"
            echo -en "Usage: $0 upload-assets -release 'vX.X.X' [options] command [file]\n\n"
            echo -en "Commands:\n"
            echo -en "  push [file]        Push files from the local directory to s3\n"
            echo -en "                      If file is given push only that file\n"
            echo -en "                      If no file is given push everything in the directory\n"
            echo -en "  push-lambda [func] Push lambda functions from the local directory to s3\n"
            echo -en "                      If function is given push only that function\n"
            echo -en "                      If no function is given push all functions (set in variables.sh)\n"
            echo -en "Options:\n"
            echo -en "  --help         -h    Print this help information and exit\n"
            echo -en "  --bucket       -b    Specify the s3 bucket to upload to\n"
            echo -en "                         Defaults to '${S3_BUCKET}'\n"
            echo -en "  --release      -r    Specify a release number for the current release\n"
            echo -en "                         This is also the path to place the files into in the s3 bucket\n"
            echo -en "  --multi-region -m    Upload files to one bucket per region, prefix at --bucket\n"
            echo -en "                         Defaults to disabled\n"
            exit 0
        ;;
        push )
            # Push file if named otherwise push everything
            if [ "${#}" != '0' ]; then
                declare -a FILE_LIST=( "${@}" )
            else
                log_term 0 "ERROR: You must specify a file with 'push'\n" -e
                log_term 3 "File: '${BASH_SOURCE[0]}' Line: '${LINENO}'"
                $0 upload-assets --help
                exit 1
            fi
            push-files "${FILE_LIST[@]}" "${S3_PATH}" "${S3_BUCKET}" "${S3_MULTI_REGION}"
            GOT_COMMAND=1
        ;;
        push-lambda )
            # Push function if named otherwise push everything
            shift
            if [ "${#}" != '0' ]; then
                declare -a LAMBDA_LIST=( "${@}" )
            else
                # https://github.com/koalaman/shellcheck/wiki/SC2153
                # shellcheck disable=SC2153
                declare -a LAMBDA_LIST=( "${LAMBDA_FUNCTIONS[@]}" )
            fi

            push-lambda "${RELEASE}" "${LAMBDA_LIST[@]}" "${S3_BUCKET}" "${S3_MULTI_REGION}"
            GOT_COMMAND=1
        ;;
    esac
    shift
done

# If we did not get a valid command print the help message
if [ ${GOT_COMMAND:-0} == 0 ]; then
    $0 upload-assets --help
fi
}

# fin
