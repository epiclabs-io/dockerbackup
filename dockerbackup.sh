#!/bin/bash

# backs up a Docker container
# This script scans the /etc/dockerbackup.d/containers folder
# for "imagename.conf" files that contain instructions for
# performing the backup
# It will check the plan and if it is time to back it up, 
# it will stop it gracefully, make a copy, compress it,
# delete the copy and upload the compressed files to a backup FTP
# location

# Default settings are stored in /etc/dockerbackup.conf


CONFIG_FILE="/etc/dockerbackup.conf"
AUTHOR="Javier Peletier <jm@epiclabs.io>"
LICENSE="Released under GNU. All rights reserved. Epic Labs, S.L. 2016"

function log {

local T=`date "+%Y-%m-%d %H:%M:%S"`
echo $T - $1 $2 $3
}

# Reads a configuration file of the format VARIABLE=VALUE
function readConfig {

	shopt -s extglob
	while IFS='= ' read lhs rhs
	do
		if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
			rhs="${rhs%%\#*}"    # Del in line right comments
			rhs="${rhs%%*( )}"   # Del trailing spaces
			rhs="${rhs%\"*}"     # Del opening string quotes 
			rhs="${rhs#\"*}"     # Del closing string quotes 
			printf -v "$lhs" "$rhs"
		fi
	done < "$1"

}

function writeTimestampFile { # sequence number, timestamp, timestamp file

	echo "SEQNUM=$1" > "$3"
	echo "TIMESTAMP=$2" >> "$3"

}

function backup {

	readConfig $1
	log "Processing Container $CONTAINER_NAME..."
	
	DOCKERBACKUP_TIMESTAMP_FILE="$DOCKERBACKUP_LOG_FOLDER/$CONTAINER_NAME.timestamp"
	TEMP_DIR="$BACKUP_TEMP_FOLDER/$CONTAINER_NAME.backup.d"
	

	#check if the timestamp file exists
	if [ ! -f "$DOCKERBACKUP_TIMESTAMP_FILE" ]; then
		writeTimestampFile 0 0 "$DOCKERBACKUP_TIMESTAMP_FILE"
	fi
	
	#obtain sequence number to use
	readConfig "$DOCKERBACKUP_TIMESTAMP_FILE"

	if (( NOW < TIMESTAMP )) ; then
		log "Backing up '$CONTAINER_NAME' skipped. Not the time to back it up yet..."
		return 1
	fi
	

	if [ -d "$TEMP_DIR" ]; then
		rm -r "$TEMP_DIR"
	fi
	
	mkdir "$TEMP_DIR"

	log "Querying status of $CONTAINER_NAME..."
	docker ps | grep "$CONTAINER_NAME" > /dev/null
	CONTAINER_OFF=$?

	if [ $CONTAINER_OFF -eq 0 ]; then
		log "$CONTAINER_NAME is running. Shutting it down..."
		docker stop "$CONTAINER_NAME"
	else
		log "$CONTAINER_NAME is not running."
	fi
		
	log "Exporting $CONTAINER_NAME files to tar file in $TEMP_DIR/..."
	
	TAR_FILE="$TEMP_DIR/$CONTAINER_NAME-$SEQNUM.tar"

	docker export -o "$TAR_FILE" "$CONTAINER_NAME"

	log "Container exported to $TAR_FILE"
	if [ $CONTAINER_OFF -eq 0 ]; then
		log "Restarting $CONTAINER_NAME..."
		docker start "$CONTAINER_NAME"
	fi


	ZIP_FILE_FULL_PATH="$TAR_FILE".7z

	7z a -t7z $ZIP_FILE_FULL_PATH -m0=lzma2 -mx=9 -aoa -v256m -r "$TAR_FILE"
	rm "$TAR_FILE"

	BACKUP_REMOTE_FOLDER="$FTP_REMOTE_FOLDER/$CONTAINER_NAME-$SEQNUM"

	FTP_COMMAND="open -u $FTP_USER,$FTP_PASSWORD $FTP_HOSTNAME"
	FTP_COMMAND="$FTP_COMMAND;mirror -R --verbose --delete-first --delete $TEMP_DIR $BACKUP_REMOTE_FOLDER"

	log "Uploading backup of $CONTAINER_NAME to $FTP_HOSTNAME ..."	
	lftp -c "$FTP_COMMAND"
	rm -r "$TEMP_DIR"

	TIMESTAMP=$((NOW + BACKUP_PERIOD * 24 * 60 * 60 - 3600)) # schedule for 1h before to ensure it triggers
	SEQNUM=$(((SEQNUM+1) % NUMBACKUPS ))
	writeTimestampFile "$SEQNUM" "$TIMESTAMP" "$DOCKERBACKUP_TIMESTAMP_FILE"
	
	log "Finished backing up $CONTAINER_NAME"
}

log "Docker backup script, by $AUTHOR"
log "$LICENSE"
log ----------------

NOW=`date +%s`

log "Reading configuration file $CONFIG_FILE ..."
readConfig "$CONFIG_FILE"

if [ ! -d "$DOCKERBACKUP_LOG_FOLDER" ]; then
	mkdir "$DOCKERBACKUP_LOG_FOLDER"
fi

N=$(((NOW / 86400) % 7 )) 
LOGFILE="$DOCKERBACKUP_LOG_FOLDER/log-$N.txt"

log "Logging to $LOGFILE."
log "Now scanning for Docker backup plans..."
for d in "$BACKUP_PLAN_FOLDER"/*.conf ; do 

	backup "$d" >> "$LOGFILE"
	readConfig "$CONFIG_FILE"
	
done

log "Done."

