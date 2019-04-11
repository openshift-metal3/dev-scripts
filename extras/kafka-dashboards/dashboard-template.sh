#!/bin/bash

DASHBOARD=$(cat $1)
cat <<EOF
{
    "dashboard": ${DASHBOARD}
}
EOF