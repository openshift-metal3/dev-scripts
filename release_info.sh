
function save_release_info() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    if [[ -f "$PULL_SECRET_FILE" ]]; then
        PULL_SECRET="${PULL_SECRET_FILE}"
    else
        PULL_SECRET="${PERSONAL_PULL_SECRET}"
    fi

    oc adm release info --registry-config "$PULL_SECRET" "$release_image" -o json > ${outdir}/release_info.json
}

# Gives us e.g 4.7 because although OPENSHIFT_VERSION is set by users,
# but is not set in CI
function openshift_version() {
    jq -r ".metadata.version" ${OCP_DIR}/release_info.json | grep -oP "\d\.\d+"
}

# Gives e.g 4.7.0-0.nightly-2020-10-27-051128
function openshift_release_version() {
    jq -r ".metadata.version" ${OCP_DIR}/release_info.json
}

function image_for() {
    jq -r ".references.spec.tags[] | select(.name == \"$1\") | .from.name" ${OCP_DIR}/release_info.json
}
