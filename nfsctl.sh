#!/bin/bash
# https://gist.githubusercontent.com/davivcgarcia/e803ad5d6c84d3e2d9f508f8960eab48/raw/4dd57c644281f1b78f8adfa48a4cc2561effd374/nfsctl.sh
# This script is EXPERIMENTAL, and it is not supported by Red Hat.
#

set -e 
set -o pipefail

servername=$(hostname -f)                     # FQDN of the NFS server (localhost)
vgname="storage"                              # Name of LVM VG used for creating the NFS Volumes
mountpath="/exports/nfsctl"                   # Where the NFS Volumes are mounted locally
fstabfile="/etc/fstab"                        # Location of system fstab file (should be default)
exportsfile="/etc/exports.d/nfsctl.exports"   # Where the NFS Exports are configured

touch ${exportsfile}

function create {
    lvsize="${1}Gi"
    lvname="pv-nfs-$(uuidgen)"
    
    lvcreate --quiet -Wy --yes ${vgname} -L ${lvsize} -n ${lvname}
    if [ ${?} -eq 0 ]; then
        devname="/dev/${vgname}/${lvname}"
        mountdir="${mountpath}/${lvname}"
        mkfs.xfs -q -f ${devname}
        mkdir -p ${mountdir}
        echo "${devname}  ${mountdir}  xfs  defaults  0 0" >> ${fstabfile}
        mount ${devname}
        chown -R nfsnobody:nfsnobody ${mountdir}
        chmod 777 -R ${mountdir}
        echo "${mountdir} *(rw,all_squash)" >> ${exportsfile}
        exportfs -r
        echo 
        echo "NFS Volume ${lvname} with ${lvsize} created and exported!"
        echo 
        echo "Using OpenShift CLI as logged as cluster admin, create the PV with:"
        printf "\n$ oc create -f - <ENTER>\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: %s \nspec:\n  capacity:\n    storage: %s \n  accessModes:\n  - ReadWriteMany \n  - ReadWriteOnce \n  nfs: \n    path: %s \n    server: %s \n  persistentVolumeReclaimPolicy: Recycle\n<CTRL+D>\n\n" ${lvname} ${lvsize} ${mountdir} ${servername} 
        exit 0
    else
        echo "Failed to create volume! Manual check required."
        exit -1
    fi    
}

function delete {
    read -r -p "DATA WILL BE COMPLETELY DESTROYED! Are you sure? [y/N] " response
    response=${response,,} # tolower
    if [[ $response =~ ^(yes|y) ]]; then
        sed -i "/${1}/d" ${exportsfile}
        exportfs -r    
        umount "/dev/${vgname}/${1}" &> /dev/null
        rm -rf "${mountpath}/${1}"
        sed -i "/${1}/d" ${fstabfile}
        lvremove -f "${vgname}/${1}" &> /dev/null
        echo "NFS Volume ${vgname} destroyed!"
        exit 0
    fi
    echo "Canceled..."
    exit 1
}

function list {
    df -h | sed -n '1p;/pv-nfs/p' | awk '{ print $2,$5,$6}'
    exit 0
}

case "$1" in
        create)
            create $2
            ;;
        delete)
            set +e
            delete $2
            ;;
        list)
            list
            ;;
	*)
            echo $"Usage: $0 {create|delete|list}"
            exit 1
esac
