#!/bin/bash
# go get github.com/jehiah/json2csv

#RELEASE_DATES="2016-04-18..2016-07-10"
RELEASE_DATES="2016-08-05..2016-12-21"
GITHUB_URL="https://api.github.com/search/issues?q=is:closed+is:issue+user:Nubisproject+closed:$RELEASE_DATES"
TMP_OUTPUT_FILE="/tmp/github_temp.json"
CSV_FILE="nubis-release-$RELEASE_DATES.csv"
shopt -s extglob # Required to trim characters

get_headers () {
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
    done < <(curl -sI -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" "${GITHUB_URL}")
}

get_data () {
    curl -s -H "Authorization: token ${CHANGELOG_GITHUB_TOKEN}" "${GITHUB_URL}" >> ${TMP_OUTPUT_FILE}
}

get_link_header_segments () {
    get_headers
    # if github does not return a 'Link' header, break
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
}

get_pagination_urls () {
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
    done < <(get_link_header_segments)
}

collect_data () {
    # Clear the output file
    :> ${TMP_OUTPUT_FILE}
    # Paginate through grabbing data as we go
    while [ ${DONE:-0} -ne 1 ]; do

        echo "Grabbing issues from: ${GITHUB_URL}"
        get_data
        get_pagination_urls
        # If we do not get a 'next' url, break
        if [ ${#NEXT_URL} == 0 ]; then
            break
        fi
        if [ ${NEXT_URL} != ${LAST_URL} ]; then
            GITHUB_URL=${NEXT_URL}
        else
            GITHUB_URL=${NEXT_URL}
            echo "Grabbing issues from: ${GITHUB_URL}"
            get_data
            let DONE=1
        fi
    done
}

parse_data () {
    jq -c '.["items"][] | {title: .title, html_url: .html_url, user: .user.login}' ${TMP_OUTPUT_FILE} | json2csv -k html_url,Estimated_m-h,user,Risk,title -o ${CSV_FILE}
}

clean_up () {
 rm -f ${TMP_OUTPUT_FILE}
}

#collect_data
#parse_data
#clean_up
