#!/bin/bash
#
# This is a startup script for qutselect which initates a
# RDP session to a windows server either via rdesktop or uttsc
#
# It receives the following inputs:
#
# $1 = PID of qutselect
# $2 = serverType (SRSS, RDP, VNC)
# $3 = 'true' if dtlogin mode was on while qutselect was running
# $4 = the resolution (either 'fullscreen' or 'WxH')
# $5 = the selected color depth (8, 16, 24)
# $6 = the current max. color depth (8, 16, 24)
# $7 = the selected keylayout (e.g. 'de' or 'en')
# $8 = the domain (e.g. 'FZR', used for RDP)
# $9 = the username
# $10 = the servername (hostname) to connect to
#

if [ `uname -s` = "SunOS" ]; then
   RDESKTOP=/opt/csw/bin/rdesktop
   XFREERDP=/opt/csw/bin/xfreerdp
   UTTSC=/opt/SUNWuttsc/bin/uttsc
   UTACTION=/opt/SUNWut/bin/utaction
   XVKBD=/usr/openwin/bin/xvkbd
   PKILL=/usr/bin/pkill
   TLSSOPASSWORD=/opt/thinlinc/bin/tl-sso-password
   TLBESTWINSERVER=/opt/thinlinc/bin/tl-best-winserver
else
   RDESKTOP=/usr/local/bin/rdesktop
   XFREERDP=/usr/local/bin/xfreerdp
   UTTSC=/opt/SUNWuttsc/bin/uttsc
   UTACTION=/opt/SUNWut/bin/utaction
   XVKBD=/usr/openwin/bin/xvkbd
   PKILL=/usr/bin/pkill
   TLSSOPASSWORD=/opt/thinlinc/bin/tl-sso-password
   TLBESTWINSERVER=/opt/thinlinc/bin/tl-best-winserver
fi

#####################################################
# check that we have 10 command-line options at hand
if [ $# -lt 10 ]; then
   echo "ERROR: missing arguments!"
   exit 2
fi

# catch all arguments is some local variables
parentPID="${1}"
serverType="${2}"
dtlogin="${3}"
resolution="${4}"
colorDepth="${5}"
curDepth="${6}"
keyLayout="${7}"
domain="${8}"
username="${9}"
serverName="${10}"

# if this is a ThinLinc session we can grab the password
# using the tl-sso-password command in case the user wants
# to connect to one of our servers (FZR domain)
if [ -x ${TLSSOPASSWORD} ]; then
  ${TLSSOPASSWORD} -c
  if [ $? -eq 0 ] && [ "x${domain}" = "xFZR" ]; then
    password=`${TLSSOPASSWORD}`
  fi
fi

# read the password from stdin if not specified yet
if [ "x${password}" = "x" ]; then
  read password
fi

# if the serverName contains more than one server we go and
# check via the check_nrpe command which server to prefer
serverList=`echo ${serverName} | tr -s ',' ' '`
numServers=`echo ${serverList} | wc -w`
if [ "${numServers}" -gt 1 ]; then
  # check if we can find a suitable binary
  if [ -x ${TLBESTWINSERVER} ]; then
    bestServer=`${TLBESTWINSERVER} ${serverList}`
    res=$?
  else
    # as an alternative we search for the tool in the scripts subdir
    # this tool also allows to override the username via -u
    if [ -x "scripts/tl-best-winserver" ]; then 
      bestServer=`scripts/tl-best-winserver -u ${username} ${serverList}`
      res=$?
    else
      # we don't have tl-best-winserver so lets simply take the first
      # one in the list
      echo argh
      bestServer=`echo ${serverList} | awk '{ print $1 }'`
      res=0
    fi
  fi
  if [ $res -eq 0 ]; then
    serverName=${bestServer}
  fi
fi

# variable to prepare the command arguments
cmdArgs=""

# now we find out which RDP client we use (xfreerdp/rdesktop/uttsc)

## UTTSC
# if $SUN_SUNRAY_TOKEN is set we explicitly use uttsc
if [ "x${SUN_SUNRAY_TOKEN}" != "x" ] && [ -x ${UTTSC} ]; then

   # before we go and connect to the windows (rdp) server we
   # go and add an utaction call so that on a smartcard removal
   # the windows desktop will be locked.
   if [ "x${dtlogin}" = "xtrue" ]; then
     ${PKILL} -u ${USER} -f "utaction.*xvkbd" >/dev/null 2>&1
     ${UTACTION} -d "$XVKBD -text '\Ml'" &
   fi

   # if we end up here we go and prepare all arguments for the
   # uttsc call
   
   # resolution
   if [ "x${resolution}" = "xfullscreen" ]; then
      cmdArgs="$cmdArgs -m"

      # if we are in dtlogin mode we go and disable the pulldown header
      if [ "x${dtlogin}" = "xtrue" ]; then
         cmdArgs="$cmdArgs -b"
      fi
   else
      cmdArgs="$cmdArgs -g ${resolution}"
   fi

   # color depth
   cmdArgs="$cmdArgs -A ${colorDepth}"

   # add client name
   cmdArgs="$cmdArgs -n `hostname`"

   # keyboard
   if [ "x${keyLayout}" = "xde" ]; then
      cmdArgs="$cmdArgs -l de-DE"
   else
      cmdArgs="$cmdArgs -l en-US"
   fi

   # add domain
   if [ "x${domain}" != "xNULL" ]; then
     cmdArgs="$cmdArgs -d ${domain}"
   else
     cmdArgs="$cmdArgs -d FZR"
   fi
   
   # add username
   if [ "x${username}" != "xNULL" ]; then
     cmdArgs="$cmdArgs -u ${username}"
   else
     if [ "x${domain}" != "xNULL" ]; then
       cmdArgs="$cmdArgs -u ${domain}\\"
     fi
   fi

   # enbaled enhanced network security
   cmdArgs="$cmdArgs -N on"

   # add the usb path as a local path
   cmdArgs="$cmdArgs -r disk:USB=/tmp/SUNWut/mnt/${USER}/"

   # output the cmdline so that users can replicate it
   if [ "x${dtlogin}" != "xtrue" ]; then
      echo ${UTTSC} ${cmdArgs} ${serverName}
   fi

   # run uttsc finally
   if [ "x${password}" != "xNULL" ]; then
     cmdArgs="$cmdArgs -i"
     echo ${password} | ${UTTSC} ${cmdArgs} ${serverName} &>/dev/null &
   else
     ${UTTSC} ${cmdArgs} ${serverName} &>/dev/null &
   fi

   ret=$?
   if [ $ret != 0 ]; then
      if [ $ret -eq 211 ]; then
        cmdArgs=""
        echo "WARNING: couldn't start uttsc, retrying with other remote desktop"
      else
        echo "ERROR: uttsc returned invalid return code"
        exit 2
     fi
   fi
fi

## XFREERDP
# if $cmdArgs is empty and xfreerdp exists use that one
if [ -z "${cmdArgs}" ] && [ -x ${XFREERDP} ]; then

   # resolution
   if [ "x${resolution}" = "xfullscreen" ]; then
      cmdArgs="$cmdArgs -f"
   else
      cmdArgs="$cmdArgs -g ${resolution}"
   fi

   # color depth
   cmdArgs="$cmdArgs -a ${colorDepth}"

   # enable LAN speed features
   cmdArgs="$cmdArgs -x lan"

   # add client name
   cmdArgs="$cmdArgs -n `hostname`"

   # keyboard
   if [ "x${keyLayout}" = "xde" ]; then
      cmdArgs="$cmdArgs -k 0x00000407"
   else
      cmdArgs="$cmdArgs -k 0x00000409"
   fi

   # add domain
   if [ "x${domain}" != "xNULL" ]; then
     cmdArgs="$cmdArgs -d ${domain}"
   else
     cmdArgs="$cmdArgs -d FZR"
   fi

   # add username
   if [ "x${username}" != "xNULL" ]; then
     cmdArgs="$cmdArgs -u ${username}"
   else
     if [ "x${domain}" != "xNULL" ]; then
       cmdArgs="$cmdArgs -u ${domain}\\"
     fi
   fi

   # set the window title to the server name we connect to
   cmdArgs="$cmdArgs -T ${serverName}"

   # ignore the certificate in case of encryption
   cmdArgs="$cmdArgs --ignore-certificate"

   # add the usb path as a local path. if TLSESSIONDATA is set
   # we are in a thinlinc session and thus have to forward
   # ${HOME}/thindrives/mnt instead
   if [ -n "${TLSESSIONDATA}" ]; then
     cmdArgs="$cmdArgs --plugin rdpdr --data disk:USB:${TLSESSIONDATA}/drives/ --"
   else
      if [ -n "${SUN_SUNRAY_TOKEN}" ]; then
        cmdArgs="$cmdArgs --plugin rdpdr --data disk:USB:/tmp/SUNWut/mnt/${USER}/ --"
      else
        cmdArgs="$cmdArgs --plugin rdpdr --data disk:USB:/mnt/`hostname`/ --"
      fi
   fi

   # enable sound redirection
   cmdArgs="$cmdArgs --plugin rdpsnd"

   # add clipboard synchronization
   cmdArgs="$cmdArgs --plugin cliprdr"

   # if we are not in dtlogin mode we go and
   # output the rdesktop line that is to be executed
   if [ "x${dtlogin}" != "xtrue" ]; then
      echo ${XFREERDP} ${cmdArgs} ${serverName}
   fi

   # run rdesktop finally
   if [ "x${password}" != "xNULL" ]; then
     cmdArgs="$cmdArgs --from-stdin"
     echo ${password} | ${XFREERDP} ${cmdArgs} ${serverName} &>/dev/null &
   else
     ${XFREERDP} ${cmdArgs} ${serverName} &>/dev/null &
   fi

   if [ $? != 0 ]; then
      cmdArgs=""
      echo "WARNING: couldn't start rdesktop, retrying with other remote desktop"
   fi

fi

## RDESKTOP
# if $cmdArgs is empty and rdesktop exists use that one
if [ -z "${cmdArgs}" ] && [ -x ${RDESKTOP} ]; then

   # resolution
   if [ "x${resolution}" = "xfullscreen" ]; then
      cmdArgs="$cmdArgs -f"
   else
      cmdArgs="$cmdArgs -g ${resolution}"
   fi

   # color depth
   cmdArgs="$cmdArgs -a ${colorDepth}"

   # sound 
   cmdArgs="$cmdArgs -r sound:local"

   # enable LAN speed features
   cmdArgs="$cmdArgs -x lan"

   # add client name
   cmdArgs="$cmdArgs -n `hostname`"

   # set the window title to the server name we connect to
   cmdArgs="$cmdArgs -T ${serverName}"

   # keyboard
   if [ "x${keyLayout}" = "xde" ]; then
      cmdArgs="$cmdArgs -k de"
   else
      cmdArgs="$cmdArgs -k en-US"
   fi

   # add domain
   if [ "x${domain}" != "xNULL" ]; then
     cmdArgs="$cmdArgs -d ${domain}"
   else
     cmdArgs="$cmdArgs -d FZR"
   fi

   # add username
   if [ "x${username}" != "xNULL" ]; then
     cmdArgs="$cmdArgs -u ${username}"
   else
     if [ "x${domain}" != "xNULL" ]; then
       cmdArgs="$cmdArgs -u ${domain}\\"
     fi
   fi

   # add the usb path as a local path. if TLSESSIONDATA is set
   # we are in a thinlinc session and thus have to forward
   # ${HOME}/thindrives/mnt instead
   if [ -n "${TLSESSIONDATA}" ]; then
     cmdArgs="$cmdArgs -r disk:USB=${TLSESSIONDATA}/drives/"
   else
      if [ -n "${SUN_SUNRAY_TOKEN}" ]; then
        cmdArgs="$cmdArgs -r disk:USB=/tmp/SUNWut/mnt/${USER}/"
      else
        cmdArgs="$cmdArgs -r disk:USB=/mnt/`hostname`"
      fi
   fi

   # if we are not in dtlogin mode we go and
   # output the rdesktop line that is to be executed
   if [ "x${dtlogin}" != "xtrue" ]; then
      echo ${RDESKTOP} ${cmdArgs} ${serverName}
   fi

   # run rdesktop finally
   if [ "x${password}" != "xNULL" ]; then
     cmdArgs="$cmdArgs -p -"
     echo ${password} | ${RDESKTOP} ${cmdArgs} ${serverName} &>/dev/null &
   else
     ${RDESKTOP} ${cmdArgs} ${serverName} &>/dev/null &
   fi

   if [ $? != 0 ]; then
      echo "ERROR: rdesktop returned invalid return code"
      exit 2
   fi

fi

exit 0
