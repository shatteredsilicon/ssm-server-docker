#!/bin/bash

set -o errexit
set -o xtrace
umask 0000

BUILDDIR=
VERSION=
IMAGENAME="shatteredsilicon/ssm-server"
INSTALLREPO="ssm-dev"

build() {
    local logs_dir=${BUILDDIR}/results/logs
    mkdir -vp ${logs_dir}

    if [ "$(uname -p)" = "aarch64" ]
    then
        # Builds on AArch64 with a zfs filesystem using buildkit fail, so disable buildkit
        export DOCKER_BUILDKIT=0
    fi

    local image_id_file=${BUILDDIR}/ssm-server-image-id
    touch ${image_id_file}
    docker build --squash --no-cache --build-arg ssm_version=${VERSION} --build-arg install_repo="${INSTALLREPO}" --iidfile ${image_id_file} .
    local origin_image_id=$(cat ${image_id_file})

    local origin_image_tar=${BUILDDIR}/ssm-server-image.tar
    local origin_image_dir=${BUILDDIR}/ssm-server-image
    local origin_cid=$(docker create ${origin_image_id})
    docker export $origin_cid -o ${origin_image_tar}
    docker rm ${origin_cid}
    mkdir -vp ${origin_image_dir}
    rm -rf ${origin_image_dir}/* && tar -C ${origin_image_dir} -xf ${origin_image_tar}
    find ${origin_image_dir} -type d -exec chmod 0777 {} \;
    find ${origin_image_dir} -type f -exec chmod 0666 {} \;

    local image_id=${origin_image_id}
    local image_dir=${origin_image_dir}

    # use clamd@scan service to scan the docker image
    > ${BUILDDIR}/ssm-server-clamdscan.log
    find ${image_dir} -type d -exec chmod 0777 {} \;
    find ${image_dir} -type f ! -executable -exec chmod 0666 {} \;
    find ${image_dir} -type f -executable -exec chmod 0777 {} \;
    find ${image_dir} -type f -print0 | xargs -0 -n1 -P$(nproc) clamdscan --multiscan --fdpass --no-summary >> ${BUILDDIR}/ssm-server-clamdscan.log

    local log_file=${logs_dir}/security-audit-scanning.log
    local vt_files=${BUILDDIR}/ssm-server-vt-files.log
    local vt_log=${BUILDDIR}/ssm-server-vt.log
    mkdir -p "${logs_dir}"
    > ${log_file}
    > ${vt_files}
    > ${vt_log}

    # check clamdscan log file
    echo $'\n' >> ${log_file}
    check_clamdscan_log ${BUILDDIR}/ssm-server-clamdscan.log ${log_file} ${vt_files}
    rm -f ${BUILDDIR}/ssm-server-clamdscan.log

    # check package checksum verification log file
    echo $'\n' >> ${log_file}
    check_rpm_verify_log ${image_dir}/var/log/ssm-server-rpm-verify.log ${log_file}
    rm -f ${image_dir}/var/log/ssm-server-rpm-verify.log

    # check orphan file scanning log file
    echo $'\n' >> ${log_file}
    check_orphan_file_log ${image_dir}/var/log/ssm-server-orphan-files.log ${log_file} ${vt_files}
    rm -f ${image_dir}/var/log/ssm-server-orphan-files.log

    # VirusTotal scanning
    i=0
    while [ $i -lt 100 ] && [ -s ${vt_files} ]; do
        sleep 10

        vt_hashes=()
        while read -r line; do
            vt_hashes+=("${line##* }")
        done < "${vt_files}"

        analysis_output="$(vt analysis ${vt_hashes[@]})"
        entity_count=$(cat "${vt_files}" | wc -l)
        entity=
        echo "$analysis_output" | tac | while read -r line; do
            entity="${line}"$'\n'"${entity}"
            if [[ "$line" =~ ^"- _id:" ]]; then
                if [[ "$entity" =~ "status: \"completed\"" ]]; then
                    file_hash=$(sed -n "${entity_count}p" "${vt_files}")
                    filename="${file_hash%% *}"
                    sed -i "${entity_count}d" ${vt_files}
                    if [[ "$entity" =~ (malicious|suspicious)': '[1-9] ]]; then
                        entity=$(echo "$entity" | sed "2 i\  _filename: ${filename##${image_dir}}")
                        echo "$entity" >> ${vt_log}
                    fi
                fi
                entity=
                entity_count=$((entity_count-1))
            fi
        done
        i=$((i+1))
    done

    # vt scanning log file
    echo $'\n' >> ${log_file}
    check_vt_log "${vt_log}" ${log_file}
    rm -f "${vt_log}"

    # clean temporary files/directories
    rm -rf "${image_tar}" "${image_dir}" "${origin_image_tar}" "${origin_image_dir}" "${slim_base_path}"

    docker tag ${image_id} "${IMAGENAME}:${VERSION}"
    docker tag ${image_id} "${IMAGENAME}:latest"
}

check_clamdscan_log() {
    local log_file=$1
    local dest_file=$2
    local vt_files=$3

    echo $'clamav scanning\n===============\n' >> "$dest_file"

    while read -r line; do
        if ! [[ "$line" =~ ': OK'$ ]]; then
            echo "$line" >> "$dest_file"
            local filename=$(echo ${line%%': '*} | awk '{$1=$1};1')
            if [ -f "${image_dir}${filename}" ] && [ -s "${image_dir}${filename}" ]; then
                local resp="$(vt scan file "${image_dir}${filename}")"
                if [[ "${resp}" =~ "Quota exceeded" ]]; then
                    exit 1
                fi
                echo "${resp}" >> "${vt_files}"
            fi
        fi
    done < "$log_file"
}

check_rpm_verify_log() {
    local log_file=$1
    local dest_file=$2

    echo $'package checksum verification\n=============================\n' >> "$dest_file"
    if [ -s "$log_file" ]; then
        cat "$log_file" >> "$dest_file"
    fi
}

check_orphan_file_log() {
    local log_file=$1
    local dest_file=$2
    local vt_files=$3

    echo $'orphan file scanning\n====================\n' >> "$dest_file"

    if [ -s "$log_file" ]; then
        cat "$log_file" >> "$dest_file"
        while read -r line; do
            if [ -f "${image_dir}${line}" ] && [ -s "${image_dir}${line}" ]; then
                local resp="$(vt scan file "${image_dir}${line}")"
                if [[ "${resp}" =~ "Quota exceeded" ]]; then
                    exit 1
                fi
                echo "${resp}" >> "${vt_files}"
            fi
        done < "$log_file"
    fi
}

check_vt_log() {
    local log_file=$1
    local dest_file=$2

    echo $'vt scanning\n===========' >> "$dest_file"
    if [ -s "$log_file" ]; then
        cat "$log_file" >> "$dest_file"
    fi
}

main() {
    while getopts "b:v:n:r:" OPT
    do
        case "${OPT}" in
            b) BUILDDIR="${OPTARG}" ;;
            v) VERSION="${OPTARG}" ;;
            n) IMAGENAME="${OPTARG}" ;;
            r) INSTALLREPO="${OPTARG}" ;;
        esac
    done

    [ -n "${BUILDDIR}" ] || { echo "Specify build dir"; exit -1 ; }
    [ -n "${VERSION}" ] || { echo "Specify version number"; exit -1 ; }
    [ -n "${IMAGENAME}" ] || { echo "Specify image name"; exit -1 ; }
    [ -n "${INSTALLREPO}" ] || { echo "Specify install repo"; exit -1 ; }

    build
}

main $@
