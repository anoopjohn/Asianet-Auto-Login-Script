#!/bin/bash
# ----------------------------------------------------------------------
# Auto login to asianet connection
# Copyright (c) 2009 Anoop John, Zyxware Technologies (www.zyxware.com)
# Copyright (c) 2009 Prasad S. R., Zyxware Technologies (www.zyxware.com)
# http://github.com/anoopjohn/Asianet-Auto-Login-Script
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ----------------------------------------------------------------------
# Debug settings
#
# set to 1|0, 0 will not record wget outputs
debug=0 
# verbose 1|0, 0 will not output to screen
verbose=1


# Initialize the scirpt settings
#
# A bit unsecure because you have to store passwords here.
# If you can see the script then probably you should be able to see 
# the password as well 
username=USERNAME
password=PASSWORD
user_agent="Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.1.5) Gecko/20091102 Firefox/3.5.5"
program_folder=~/.auto-login
# Enter time in 24 hr format.
# Will safely handly case where start > stop eg: start 23:00 stop 06:00
free_start="02:10"
free_stop="07:50"
# Default connection time out interval
conn_timeout=300
ping_interval=290
ntp_wait=310

# Initialize file paths

lock_file=$program_folder/conn_url
log_file=$program_folder/conn.log
debug_log_file=$program_folder/debug.log
script_folder=$program_folder

# If debug is enabled log all output from the commands 
# else throw to null
if [ $debug -eq 1 ];
then 
  debug_log=$debug_log_file
else
  debug_log=/dev/null
fi

# Create log file folder if not exist

if [ ! -d $program_folder ]; 
then
  mkdir $program_folder
  mkdir $program_folder/startup
  mkdir $program_folder/shutdown
fi
if [ ! -d $program_folder ]; 
then
  echo "Could not create program folder"
  exit
fi

# Initialize time vars
now_utc=`date +%s`
free_start_utc=`date +%s -d "$today $free_start"`
free_stop_utc=`date +%s -d "$today $free_stop"`

#
#-BEGIN-FUNCTIONS-------------------------------------------------------
#
# Log the actions
function log {
  if [ $verbose -eq 1 ];
  then
    echo $1
  fi
  log_to_file "$1" 
}
function log_to_file {
  echo `date +"%D %H:%M:%S"` $1 >> $log_file
}
#
#
# Check if the user is already connected to the net
#
function is_connected {
  #if true we should get www.zyxware.com as return value
  test=`wget --quiet -O - http://www.zyxware.com/software/utilities/index.html|wc -c`
  
  if [ $test = "15" ];
  then
    return 0
  else
    return 1
  fi
}

#
# Get the connection URL. Asianet cycles this URL. Don't know whether it matters
# So getting it from the html page itself
#
function get_asianet_conn_url {
  # If not connected then try any URL and get the redirection URL
  if ! is_connected;
  then
    # The wget strategy will work only if user is not already connected to the net
    asianet_conn_url=`wget --quiet -O - www.zyxware.com|grep 'action='|sed 's/\(.*action="\)\(.*\)">/\2/g'`
    # Save the URL so that we can use the same URL to log out
    log $asianet_conn_url | tee $lock_file
  else
    # Use the saved URL from the file
    if [ -f $lock_file ];
    then
      cat $lock_file
    else
      log_to_file "Using fallback URL: https://mwcp-tvm-04.adlkerala.com:8001/"   
      echo https://mwcp-tvm-04.adlkerala.com:8001/
    fi
  fi
}

#
# Connect to asianet by posting the username and password
#
function connect {
  # Get URL to post data to
  asianet_conn_url=$(get_asianet_conn_url)
  log "Connecting to $asianet_conn_url"
  # Post data
  curl --silent -F "auth_user=$username" -F "auth_pass=$password" -F "accept=Login" -A "$user_agent" $asianet_conn_url >> $debug_log
}

#
# Connect to asianet by posting the username and logout command
#
function disconnect {
  # Get URL to post data to
  asianet_conn_url=$(get_asianet_conn_url)
  log "Disconnecting from $asianet_conn_url"
  # Post data
  curl --silent -F "logout_id=$username" -F "logout=Logout" -A "$user_agent" $asianet_conn_url >> $debug_log
  rm $lock_file 2>/dev/null
}

#
# Keep the connection alive by posting the keep alive command
#
function keep_alive {
  # Get URL to post data to
  asianet_conn_url=$(get_asianet_conn_url)
  log "Pinging $asianet_conn_url"
  # Post data
  curl --silent -F "alive=y" -F "un=$username" -A "$user_agent" $asianet_conn_url >> $debug_log
}

#
# Recalculate the global time variables
#
function recalculate_time_vars
{
  # We have to recalculate variables every time
  today=`date +%x`
  now_utc=`date +%s`
  free_start_utc=`date +%s -d "$today $free_start"`
  free_stop_utc=`date +%s -d "$today $free_stop"`
  # For safety we calculate free download start time+timeout
  free_start_utc=$(($free_start_utc+$conn_timeout))
  # For safety we calculate free download stop time-timeout
  free_stop_utc=$(($free_stop_utc-$conn_timeout))
  # If free time stop is less than free time start then these are in two dates
  # Eg: start = 23:00 stop = 06:00 taking the times for the current day we get
  # start > stop. So we add 86400 to take stop to the next day
  if [ $free_stop_utc -lt $free_start_utc ];
  then
    # If now < free_stop then flip the start time back
    if [ $now_utc -le $free_stop_utc ];
    then
      free_start_utc=$(($free_stop_utc-86400)) 
    # If now > free_start then flip the stop time forward
    elif [ $now_utc -ge $free_start_utc ]; 
    then 
      free_stop_utc=$(($free_stop_utc+86400)) 
    fi
  else  
    # If free download time is over for the day look forward to the next free slot  
    if [ $now_utc -gt $free_stop_utc ];
    then
      free_start_utc=$(($free_start_utc+86400)) 
      free_stop_utc=$(($free_stop_utc+86400)) 
    fi
  fi
}

#
# Get the number of seconds to sleep before free connection starts
#
function time_to_free_start {
  recalculate_time_vars
  # If it is between the free download slot just wait the default timeout
  if [ $now_utc -lt $free_stop_utc -a $now_utc -ge $free_start_utc ];
  then
    echo $conn_timeout
  else
    # If free download time is yet to start for the day
    if [ $now_utc -lt $free_start_utc ];
    then
      echo $(($free_start_utc-$now_utc))  
    fi 
  fi  
}

#
# Check if we are within the free download time.
#
function is_still_free_download_time
{
  recalculate_time_vars
  # If it is between the free download slot just wait the default timeout
  if [ $now_utc -lt $free_stop_utc -a $now_utc -gt $free_start_utc ];
  then
    return 0
  else
    return 1
  fi  
}

#
#-END-FUNCTIONS---------------------------------------------------------
if [ "$1" == "free" ];
then 
  if ! is_connected;
  then
    # If not connected then connect
    connect
    # Wait for an ntpdate call from cron
    sleep $ntp_wait
    disconnect
    sleep 1
  else
    # Wait for an ntpdate call from cron
    sleep $ntp_wait
    sleep 1
  fi  
fi
case "$1" in
  "auto"|"startup"|"free")
    # If this is a startup run wait 5 minutes to make sure that the last connection
    # times out. To take care of a quick power outage and quick return of power
    # before the previous connection times out
    if [ "$1" == "startup" -o "$1" == "free" ];
    then 
      log "Starting application."
      if [ "$1" == "free" ];
      then 
        # If this is a free download run, sleep till the free time starts
        sleep_time=$(time_to_free_start)
        if is_still_free_download_time;
        then
          # If within free download time say so
          log "Within free time, sleeping for $sleep_time second(s)."
        else  
          log "Sleeping for $sleep_time second(s) till free time starts."
        fi
        sleep $sleep_time
      else
        if [ "$2" != "nowait" ];
        then 
          log "Sleeping for $conn_timeout second(s) for old connection (if any) to time out."
          sleep $conn_timeout
        fi  
      fi    
    fi 
    # Check if connected and connect if not
    if ! is_connected;
    then
      # If not connected then connect
      connect
      if ! is_connected;
      then
        # If connection attempt failed log and exit 
        log "Could not connect to the connection."
        exit
      else
        log "Successfully connected to the connection."
      fi  
    else
      # In auto mode disconnect if connected
      if [ "$1" == "auto" ];
      then
        # If connected to the internet disconnect and exit
        disconnect
        if is_connected;
        then
          log "Could not disconnect the connection."
        else
          log "Successfully disconnected the connection."
        fi
        exit
      fi  
    fi
    # If this is a free run then run any additional scripts
    if [ "$1" == "free" ];
    then 
      if [ -d $script_folder ]; 
      then
        log "Running startup scripts."
        for script in $script_folder/startup/*; 
        do
          log "Running $script."
          if [ -x $script ]; then $script; fi
        done
      fi  
    fi 
    # If conrol reaches here, connection exists, keep alive
    while [ 1 ];
    do
      # If not explicitly logged out keep connection live
      # the autologin file would have been deleted in a logout operation
      if [ -f $lock_file ];
      then
        if is_connected;
        then
          # If connected then proceed
          keep_alive
          if ! is_connected;
          then
            log "Something is wrong, you are not connected to the internet."
            exit
          fi  
          # When lock file exists but there is no connection try reconnect  
        else
          connect
          if ! is_connected;
          then
            log "Could not re-connect."
          else
            log "Successfully re-connected."
          fi  
        fi
      else  
        # Lock file has been explicitly deleted during a disconnect operation
        # So exit  
        log "Disconnected; probably from another thread, exiting."
        exit
      fi
      # If this is a free run then exit at end of free time
      if [ "$1" == "free" ];
      then      
        if ! is_still_free_download_time;
        then
          log "Free Download time over, disconnecting"
          if [ -d $script_folder ]; 
          then
            log "Running shutdown scripts."
            for script in $script_folder/shutdown/*; 
            do
              log "Running $script."
              if [ -x $script ]; then $script; fi
            done
          fi  
          disconnect
          if is_connected;
          then
            log "Could not disconnect the connection."
          else
            log "Successfully disconnected the connection."
          fi    
          # In any case exit
          exit      
        fi  
      fi
      # Sleep ping_interval and ping again
      sleep $ping_interval
    done
    ;;
  "keep-alive")
    # Check if connected
    if is_connected;
    then
      # If connected then proceed
      keep_alive
      if ! is_connected;
      then
        log "Something is wrong, you are not connected to the connection"
      fi  
    else
      log "This system is disconnected from the internet. Cannot send keep-alive request."
    fi
    ;;
  "logout")
    # Check if connected and proceed if connected
    if is_connected;
    then
      disconnect
      if is_connected;
      then
        log "Could not disconnect the connection."
      else
        log "Successfully disconnected the connection."
      fi  
    else
      log "This system is already disconnected from the internet."
    fi
    ;;
  "--help")
    echo "-------------------------------------------------------------"
    echo "Asianet Auto Login Script"
    echo "Copyright (c) 2009 Anoop John, Prasad S. R. (www.zyxware.com)"
    echo "-------------------------------------------------------------"
    echo "Usage: "
    echo `basename $0` "[auto|startup|free|logout|*][nowait]"
    echo "  auto    - Logs in if not logged in, else logs out."
    echo "  startup - Startup mode, keeps a connection always on."
    echo "  free    - Keeps connection alive only during free download hours."
    echo "  logout  - Disconnect."
    echo "  *       - Connect."
    echo "  nowait  - Do not wait for any connection to expire."
    ;;
  *)
    # Check if already connected and proceed if not connected
    if ! is_connected;
    then
      connect
      if ! is_connected;
      then
        log "Could not connect to the connection."
      else
        log "Successfully connected to the connection."
      fi  
    else
      log "This system is already connected to the internet."
    fi
    ;;
esac

