#!/bin/bash
#

usage() {
    echo "$(basename $0) -  list recent pass rates for metal-ipi jobs" 1>&2
    echo "Usage: $(basename 0) [-h] [-l] RELEASE" 1>&2
    echo "  -l: list links to failed job runs" 1>&2
    echo "  RELEASE: release to display results for (default: all)" 1>&2
    echo "  eg: " 1>&2
    echo "   ./scripts/periodics_pass_rates.sh 4.13 | sort" 1>&2
    echo "   ./scripts/periodics_pass_rates.sh -l 4.13" 1>&2
    exit 1
}

LIST=0
while getopts ":l" o; do
    case "${o}" in
        l)
            LIST=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

ALLJOBSURL="https://raw.githubusercontent.com/openshift/release/master/ci-operator/jobs/openshift/release/openshift-release-master-periodics.yaml"
JOBSTOTEST=$(curl -s $ALLJOBSURL | yq -r ".periodics[] | select(.name | contains(\"metal-ipi\")) | select(.name | contains(\"nightly-${1:-}\")) | .name")
RESULT_FORMAT=${RESULT_FORMAT:-"%4s %5s - %s\n"}

function getJobSummary(){
    JOB=$1
    URL=https://prow.ci.openshift.org/job-history/gs/origin-ci-test/logs/$JOB
    DATA=$(curl --silent $URL | grep allBuilds - | grep -o '\[.*\]')
    SUCCESS=$(echo $DATA | jq '.[].Result' | grep "SUCCESS" | wc -l)
    TOTAL=$(echo $DATA | jq '.[].Result' | grep -v "PENDING" | wc -l)
    if [ "$TOTAL" == 0 ] ; then
        printf "$RESULT_FORMAT" $SUCCESS/0 0% - ${URL}
        return
    fi
    printf "$RESULT_FORMAT" $(( (SUCCESS * 100)/TOTAL ))% $SUCCESS/$TOTAL ${URL}
    if [ "$LIST" == "1" ] ; then
        echo $DATA | jq '.[] | select(.Result | contains("FAILURE")) | "    \(.Started) https://prow.ci.openshift.org/\(.SpyglassLink) " ' -r
    fi
}

for JOB in $JOBSTOTEST ; do
    getJobSummary $JOB
done

