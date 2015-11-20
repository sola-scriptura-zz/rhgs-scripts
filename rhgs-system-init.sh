#!/bin/bash
# File-Name : rhgs-init.sh
# Author : YJ jeong
# Description : 
# RHGS Storage Server initialization Script. The script is supposed to be run
# after ISO installation and setting up the network.
# The script does the following:
# 	- Setting up Firewall zone and add interface to trusted zone.
#	- Apply corresponding performance tuning profile Based on the reference.
#	- Attache ssd disk for dm-cache 
#
# function list :
#	initb 	- initialization firewall and etc setting
#	lvmb	- setup lvm for Raid6 data volume  
#	ssd_lvmb	- setup lvm for dm-cache volume using ssd
#
# History :
# 10/27/2015 YJ : create script it able to use RHEL7 base RHGS3.1
# 10/28/2015 YJ : add more function such as tunning,dm-cache,init.
# 10/29/2015 YJ : add refactoring script.
# 10/30/2015 YJ : enable to using parameter for internal function
# 11/03/2015 YJ : modify function for using parameter, separate configuration value
# 11/09/2015 YJ : add function for multi pv,vg,lv device 
# 11/09/2015 YJ : add function for log-device pv,vg,lv
# 11/09/2015 YJ : copy kernel tunning parameter for gluster

##################
# Load the configuration file for gluster ininitial setting value
confile="./sds_gluster.conf"
[ -r "${confile}" ] && [ -f "${confile}" ] && source "${confile}"

###########################
# for logging 
#exec > >(tee ${logfile})
#exec 2>&1

###########################
# default function
function usage {
	cat <<EOF
Usage: $ME [-h] [-w object]

General:
  -w <object>   add_firewall -
				add_firewallrule
				mk_gpt_lvmpart
				create_pv 
				create_vg 
				create_lv 
				create_logdevice 
				mkfsb
				mountb
				enable_dmcache
				send_config
  -t            netperf test for gluster network.
  -h            Display this help.
EOF
	exit 1
}

function quit {
	exit $1
}

function yesno {
	while true; do
		read -p "$1 " yn
		case $yn in
			[Yy]* ) return 0;;
			[Nn]* ) return 1;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

############################
# object function

function add_firewallrule {
	echo "remove interface $trusted_eth from public zone"
	sudo firewall-cmd --zone=public --remove-interface=$trusted_eth
	
	echo "add interface $trusted_eth to trusted zone"
	sudo firewall-cmd --zone=trusted --add-interface=$trusted_eth
	echo "add glusterfs service to tusted zone"
	sudo firewall-cmd --zone=trusted --add-service=glusterfs 

	echo "save permanently firewall setting"
	sudo firewall-cmd --zone=trusted --add-interface=$trusted_eth --permanent
	sudo firewall-cmd --zone=trusted --add-service=glusterfs --permanent
	return $?
}

function create_pv {
	disks=${raid_disks}
	for disk in $disks;do
		echo "find device for create physical volume"
		if [ ! -h /dev/${disk} ]; then
			echo "/dev/${disk} - Net Present!"
			return 1
		fi

		echo "create physical volume with device ${disk}."
		pvcreate --dataalignment $dataalign"k" /dev/${disk}"1"
	done
	return $?
}

function create_vg {
	disks=${raid_disks} 
	vgname=${vgname_base}
	vgnum=1
	for disk in ${disks};do
		echo "create volume group $vgname."
		vgcreate --physicalextentsize $dataalign"k" ${vgname}${vgnum} "/dev/"$disk"1"
		vgnum=$[$vgnum +1]
	done

	return $?
}

function create_lv {
	vgname=${vgname_base}
	lvname=${lvname_base}
	lvpoolname=${lvname}"_pool"
	lvpoolmeta=${lvpoolname}"_meta"
	vgsize=`vgs | grep ${vgname} | awk '{print $7}'`
	vgcount=`vgs | grep ${vgname} | wc -l`
	vgnum=1

	for i in $(seq 1 $vgcount);do
		lvsize=`vgs | grep ${vgname}${vgnum} | awk '{print $7}'`
	
		echo "create logical volume ${lvname} pool"
		lvcreate -L 16776960K --name ${lvpoolmeta} ${vgname}${vgnum}
		lvcreate -l 95%VG --name ${lvpoolname} ${vgname}${vgnum}
		lvconvert --chunksize ${chunk_size}"k" --thinpool ${vgname}${vgnum}"/"${lvpoolname} --poolmetadata ${vgname}${vgnum}"/"${lvpoolmeta}
		lvchange --zero n ${vgname}${vgnum}"/"${lvpoolname}
		lvcreate -V ${lvsize}  -T ${vgname}${vgnum}"/"${lvpoolname} -n ${lvname}"1"
		vgnum=$[$vgnum +1]
	done

	return $?
}

#mkfs
function mkfsb {
	vgname=${vgname_base}
	lvname=${lvname_base}
	vgcount=`vgs | grep ${vgname} | wc -l`
	for i in $(seq 1 ${vgcount});do
		mkfs.xfs -f -i size=$inode_size -n size=$fs_block_size -imaxpct=$inode_max_percent -l logdev=/dev/${logvg}${i}"/"${loglv} -d su=$stripesize"k",sw=$stripe_elements /dev/${vgname}${i}/${lvname}"1"
	done
	return $?
}

function mountb {
	vgname=${vgname_base}
	lvname=${lvname_base}

	num=`hostname | cut -c 5-6`
	echo "Make directory for mount point"
	mount_dir="/rhgs/exp"$num	
	mkdir -p $mount_dir"-1/"
	mkdir -p $mount_dir"-2/"
	echo "######################" >> /etc/fstab
	echo "/dev/${vgname}1/${lvname}1	"$mount_dir"-1/ xfs rw,inode64,noatime,nouuid,logdev=/dev/${logvg}"1/"${loglv} 1 2" >> /etc/fstab
	echo "/dev/${vgname}2/${lvname}1 	"$mount_dir"-2/ xfs rw,inode64,noatime,nouuid,logdev=/dev/${logvg}"2/"${loglv} 1 2" >> /etc/fstab
	mount -a
	return $?
}

#tuned-adm profile
function tunedb {
	for i in $(seq 1 7);do
		ssh root@rhgs0${i} "tuned-adm profile "$tune_profile
	done
	return $?
}

function ulimitb {
	for i in $(seq 1 7);do
		ssh root@rhgs0${i} "echo '* - nproc unlimited' >> /etc/security/limits.conf; echo '* - nofile 1024000' >> /etc/security/limits.conf"
	done
	return $?
}

function create_ssd_pv {
	if [ ! -h /dev/$ssd_disk ]; then
		echo "device $ssd_disk - Not Present!"
		return 1
	fi
	
	for disk in $ssd_disk; do
		echo "Create pv for $ssd_disk"
		pvcreate --dataalignment=1024k $disk
	done
	return $?
}

function expend_vg {
	vgname=$1
	echo "Expend volume group $vgname."

	vgextend $vgname /dev/sdb /dev/sdc
	
	return $?
}

function create_ssd_lv {
	lvcreate --stripes 2 -I 2M -n rhs_cache_meta -L 10G rhs_vg /dev/sdc /dev/sdb
	lvcreate --stripes 2 -I 2M -n rhs_cache -l100%FREE rhs_vg /dev/sdc /dev/sdb	
	lvconvert --type cache-pool --poolmetadata rhs_vg/rhs_cache_meta rhs_vg/rhs_cache
	lvconvert --type cache --cachepool rhs_vg/rhs_cache rhs_vg/rhs_pool

	return $?
}

function mk_gpt_lvmpart {
 	disks=${raid_disks}
	echo "create lvm partition for physical volume"
	for disk in $disks;do
		parted /dev/${disk} mklabel gpt
		endpoint=`parted /dev/${disk} print free | grep ${disk} | awk '{print $3}'`
		echo "Disk ${disk} partition creat start..."
		parted /dev/${disk} mkpart primary 1 ${endpoint}
		parted /dev/${disk} set 1 lvm on

		echo "Disk ${disk} partition created..."
	done

	return $?
}

function enable_dmcache {
	create_ssd_pv
	expend_vg rhs_vg 
	create_ssd_lv
	
	return $?
}

function create_logdevice {
	create_logpv
	create_logvg
	create_loglv

	return $?	
}

function create_logpv {
	disks=${ssd_disks}
	diskcount=${!disks[@]}
	for disk in $disks;do
		parted /dev/${disk} mklabel msdos
		parted /dev/${disk} mkpart primary 1 2G
		parted /dev/${disk} mkpart primary 2G 4G
		parted /dev/${disk} set 1 lvm on 
		parted /dev/${disk} set 2 lvm on 
		sleep 3
		echo "partprobe.... "
		partprobe

		pvcreate --dataalignment $dataalign"k" /dev/${disk}"1" /dev/${disk}"2" --force
	done

	return $?
}

function create_logvg {
	disks=${ssd_disks}

	for i in $(seq 1 2);do
		str=""
		for disk in ${disks};do
			str+="/dev/${disk}${i} "
		done
		vgcreate --physicalextentsize "512k" ${logvg}${i} ${str}
	done

	return $?
}

function create_loglv {
	for i in $(seq 1 2);do
		lvcreate -L 2000M --name ${loglv} ${logvg}${i} --stripes 2
	done

    return $?
}

function send_config {
	cp ./sysctl.d/* /etc/sysctl.d/.
	cp ./security/limits.d/* /etc/security/limits.d/.

    return $?
}

function main {
	add_firewallrule
	mk_gpt_lvmpart
	create_pv 
	create_vg 
	create_lv 
	create_logdevice 
	mkfsb
	mountb
	enable_dmcache
	send_config

	return $?	
}

main
