#!/bin/bash

set -e

bugzilla_one=$HOME/go/bin/bugzilla-one

source $HOME/.jira_sync_settings

if [ -z "$jira_url" ]; then
    echo "NO JIRA URL SET"
    exit 1
fi

$bugzilla_one \
    -jira-user "$jira_user" \
    -jira-password "$jira_password" \
    -jira-url "$jira_url" \
    -bugzilla-token "$bugzilla_token" \
    -bugzilla-url "$bugzilla_url" \
    -jira-project KNIDEPLOY \
    -jira-component 'KNI Deploy Install' \
    $@
