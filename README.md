# Docker container backup script -- backs up Docker containers to FTP

This script scans the `/etc/dockerbackup.d` folder and looking for `.conf` files representing Docker container backup plans. For each file, the script executes a backup according to the plan defined in the file. 

This script is designed to be run once a day as root, via a crontab. The backup frequency can be defined in days in each `.conf` file.

To back up a Docker container, if it is running, the script stops it gracefully, executes `docker export` to a temporary folder and then restarts the container again. Then it compresses the files and uploads them to the specified FTP space.

## How to install

1. Copy `dockerbackup.sh` to `/usr/local/bin` and make it executable `chmod +x /usr/local/bin/dockerbackup.sh` 
2. Create your global `/etc/dockerbackup.conf` starting off the included `dockerbackup.conf.sample` file.
3. Create the backup plans directory: `/etc/dockerbackup.d/`
3. For each Docker container you want to back up, add a file `containername.conf` file in `/etc/dockerbackup.d`. For example if you want to back up the 'aragorn' container, create a `aragorn.conf` file in `/etc/dockerbackup.d` starting off the provided `containerbackup.conf.sample`
4. Add the script to crontab. For example, this line runs the backup every day at 4am:

```
0 4 * * * /usr/local/bin/dockerbackup.sh
```
Although the script runs every day, it will check each container's schedule to see if it has to actually execute the backup that day or not.

Trick: You can override gobal variables in each containers's backup configuration file, for example to back up a specific machine to a different FTP host.

### Logging

The script automatically saves rotating logs to the logging folder specified in the configuration file, by default `/var/log/dockerbackup/`

## License

Released under GPL!. Contributions welcome!

