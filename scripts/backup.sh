#!/usr/bin/env bash
set -euo pipefail


: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${S3_ENDPOINT:?S3_ENDPOINT is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"


get_filenames() {
    local version="$1"

    echo "tixati_${version}-1_amd64.deb"
    echo "tixati_${version}-1_i686.deb"
    echo "tixati-${version}-1.x86_64.rpm"
    echo "tixati-${version}-1.i686.rpm"
    echo "tixati-${version}-1.x86_64.manualinstall.tar.gz"
    echo "tixati-${version}-1.i686.manualinstall.tar.gz"
    echo "tixati-${version}-1.win64-install.exe"
    echo "tixati-${version}-1.win32-install.exe"
}


get_latest_release() {
    wget -qO- https://www.tixati.com/download |\
        grep 'Now Available!' |\
        grep -oP '(?<=Version )\d+(\.\d+)?'
}


log() {
    echo >&2 "=> $1"
}


s3_exists() {
    aws s3api head-object \
        --endpoint-url "$S3_ENDPOINT" \
        --bucket "$S3_BUCKET" \
        --key "$1" \
        > /dev/null 2>&1
}


s3_read() {
    aws s3 cp --endpoint-url "$S3_ENDPOINT" "s3://$S3_BUCKET/$1" -
}


s3_write() {
    aws s3 cp --endpoint-url "$S3_ENDPOINT" - "s3://$S3_BUCKET/$1"
}


main() {
    local hash
    local hashfile
    local stored_hash
    local tmpdir
    local version

    version="${1:-$(get_latest_release)}"
    
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    pushd "$tmpdir" > /dev/null
        log "Check Tixati version: ${version}"

        while read -r name; do
            wget -q "https://download.tixati.com/${name}"
            
            hash="$(md5sum "$name" | awk '{ print $1 }')"
            hashfile="${name}.hashsum"

            if ! s3_exists "$name"; then
                log "Uploading new release '${name}' in bucket '${S3_BUCKET}'"
                s3_write "$name" < "$name"

                log "Uploading hashsum for release '${hashfile}' in bucket '${S3_BUCKET}'"
                echo "$hash" | s3_write "$hashfile"
            else
                stored_hash="$(s3_read "$hashfile" 2>/dev/null || echo '')"

                if [[ "$hash" != "${stored_hash:-$(s3_read "$name" | md5sum | awk '{ print $1 }')}" ]]
                then
                    log "Replaces the existing release '${name}' in bucket '${S3_BUCKET}'"
                    s3_write "$name" < "$name"

                    log "Replaces hashsum for release '${hashfile}' in bucket '${S3_BUCKET}'"
                    echo "$hash" | s3_write "$hashfile"
                elif [[ -z "$stored_hash" ]]; then
                    log "Uploading hashsum for release '${hashfile}' in bucket '${S3_BUCKET}'"
                    echo "$hash" | s3_write "$hashfile"
                fi
            fi
        done < <(get_filenames "$version")
    popd > /dev/null
}


main $@
