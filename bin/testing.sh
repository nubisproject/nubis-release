#!/bin/bash

testing () {
    echo "testing"

    get_repositories
    echo "${REPOSITORY_LIST_ARRAY[*]}"
}

