#!/bin/bash

#
#  run.sh    http://www.cs.wisc.edu/~kupsch
#
#  Copyright 2013-2020 James A. Kupsch
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

declare runShVersion='1.1.15'
declare runShReleaseDate='2020-03-12'
declare buildAssessDriver="build_assess_driver"
declare getPlatform="get-platform"
declare runParamsFile="run-params.conf"
declare containerType=
declare quotedCmdLine=
declare buildAssessOut=
declare scriptStartTime=
declare outputFilesConf=
declare statusOut=
declare envSh=
declare swampBaseDir=
declare swampEventFile=
declare runOutFile=
declare userConf=
declare ipAddrFile=
declare delayShutdownAlwaysWaitFile=
declare delayShutdownStopWaitFile=
declare captureArchive=
declare earlyCaptureArchive=
declare -a errorMsgs=()
declare -a bgPids=()
declare stdoutRedirectedTo=
declare stderrRedirectedTo=
declare hasPrintfTime=
declare hasQTransform=
declare -i defaultTimePrec=3
declare -i networkState=0
declare inShutdown=
declare inErrorShutdown=
declare -i SLEEP_TIME=20
declare -i DNS_WAIT_TIME=10
declare OPT_DIR=/opt
declare BUILD_ASSESS_OUTPUT=build_assess.out
declare OUTPUT_FILES_CONF=output_files.conf
declare ENV_SH=env.sh
declare STATUS_OUT=status.out
declare TIMESTAMP_LOG_ENTRIES=
declare DELAY_SHUTDOWN_UNTIL=
declare -i DELAY_SHUTDOWN_UNTIL_SECONDS_AFTER_START=0
declare DELAY_SHUTDOWN_CMD=who
declare -i DELAY_SHUTDOWN_CHECK_INTERVAL=10
declare DELAY_SHUTDOWN_LOG_CMD_OUTPUT=1
declare DELAY_SHUTDOWN_ALWAYS_WAIT_FILE=RUNSH_ALWAYS_WAIT
declare DELAY_SHUTDOWN_STOP_WAIT_FILE=RUNSH_STOP_WAIT
declare IP_ADDR_ROUTE_TO=1.1.1.1
declare CAPTURE_ARCHIVE=capture.tar.gz
declare CAPTURE_FILES='/var/log/messages /var/log/syslog'
declare CAPTURE_METHOD=tar
declare vmVars=( VMINPUTDIR VMOUTPUTDIR VMGROUPADD VMUSERADD VMSHUTDOWN NO_SHUTDOWN_CMD )
declare runParamsVars='
    SWAMP_USERNAME
    SWAMP_USERID
    SWAMP_GROUPNAME
    SWAMP_GROUPID
    SWAMP_PASSWORD
    SWAMP_PASSWORD_IS_ENCRYPTED
    USER_CONF
    BUILD_ASSESS_OUTPUT
    SLEEP_TIME
    DNS_WAIT_TIME
    NETWORK_WAIT_TIME
    NO_CREATE_USER
    NO_VERIFY_NETWORK
    ROOT_SCRIPT
    ROOT_PAYLOAD
    USER_PRE_SCRIPT
    USER_PRE_PAYLOAD
    USER_SCRIPT
    USER_PAYLOAD
    NO_USER_FRAMEWORK_PAYLOAD
    USER_POST_SCRIPT
    USER_POST_PAYLOAD
    ROOT_POST_SCRIPT
    ROOT_POST_PAYLOAD
    NOSHUTDOWN
    NORUNPAYLOAD
    LOG_CMD_TIMING
    TIMESTAMP_LOG_ENTRIES
    TIME_PRECISION
    DELAY_SHUTDOWN_UNTIL
    DELAY_SHUTDOWN_UNTIL_SECONDS_AFTER_START
    DELAY_SHUTDOWN_CMD
    DELAY_SHUTDOWN_CHECK_INTERVAL
    DELAY_SHUTDOWN_LOG_CMD_OUTPUT
    DELAY_SHUTDOWN_ALWAYS_WAIT_FILE
    DELAY_SHUTDOWN_STOP_WAIT_FILE
    SWAMP_EVENT_FILE
    IP_ADDR_FILE
    IP_ADDR_ROUTE_TO
    EARLY_CAPTURE_ARCHIVE
    EARLY_CAPTURE_FILES
    CAPTURE_METHOD
    CAPTURE_ARCHIVE
    CAPTURE_FILES
    NO_SHUTDOWN_CMD
'
declare runParamsVarPrefixes='
    BG_SCRIPT_
    BG_PAYLOAD_
    BG_OUTFILE_
    BG_NAME_
    BG_USER_SCRIPT_
    BG_USER_PAYLOAD_
    BG_USER_OUTFILE_
    BG_USER_NAME_
'

declare -r logMsgPrefix='========================='
declare -r logNotePrefix='==='
declare -r logCmdPrefix='+'
declare -r logBgCmdPrefix='+&'
declare -r logFailPrefix='### #####'
declare -r logWarningPrefix="$logFailPrefix Warning: "
declare -r logErrorPrefix="$logFailPrefix Error: "
declare -r logTimingPrefix='    |'
declare -r logTsPrefix='<'
declare -r logTsPostfix='>'

declare -r intNumRe='^[0-9]+$'
declare -r floatNumRe='^(([-]?)[0-9]+)(\.([0-9]*))?$'
declare -r ipAddrRe='( |^)src ([0-9]{1,3}(\.[0-9]{1,3}){3})( |$)'

declare -ir nanosPerS=1000000000
declare -r dateFmt='+%F %T.%N%z'

declare -r lsCmd=( ls -l -a "--time-style=+%F %T%z" )


# CheckNumArguments(<nArgs> <min> <max>)
#   Verify the <nArgs> is between <min> and <max> exclusive, if <min> or <max>
#   are empty, they default to 0 and infinity.  If out of range ErrorShutdown
function CheckNumArguments()
{
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
	ErrorShutdown setup invalid-arg "$FUNCNAME requires 2 to 3 arguments not $#"
    fi

    local nArgs=$1  min=$2  max=$3
    local func=${FUNCNAME[1]}

    if [ -z "$min" ]; then
	min=0
	if [ -z "$max" ]; then
	    ErrorShutdown setup invalid-arg "$FUNCNAME one of min or max must be set"
	fi
    fi
    if [ -z "$max" ]; then
	max=$nArgs
    fi

    if [ "$nArgs" -lt "$min" ] || [ "$nArgs" -gt "$max" ]; then
	if [ -z "$3" ]; then
	    ErrorShutdown setup invalid-arg "$func requires at least $min args not $nArgs"
	elif [ "$min" -eq "$max" ]; then
	    ErrorShutdown setup invalid-arg "$func requires $min args not $nArgs"
	elif [ "$min" -eq 0 ]; then
	    ErrorShutdown setup invalid-arg "$func requires at most $max args not $nArgs"
	fi
	ErrorShutdown setup invalid-arg "$func requires between $min and $max args not $nArgs"
    fi
}


# IsInteger(<s>)
#   exits with 0 status if <s> is an integer, or 1 otherwise
function IsInteger
{
    CheckNumArguments $# 1 1
    [[ "$1" =~ $intNumRe ]]
}


# LogCallStack(<startAt>)
#   Write out call stack starting with FUNCNAME[<startAt> + 1], <startAt> defaults to 0
function LogCallStack()
{
    local -i i=$1
    local calledFrom=''

    LogNote "  call stack:"
    for (( ++i ; i < ${#FUNCNAME[@]}; ++i )); do
	local msg="    $calledFrom"
	msg+="function ${FUNCNAME[i]}"
	if [ "$i" -gt 0 ]; then
	    msg+=" at ${BASH_SOURCE[i-1]}:${BASH_LINENO[i-1]}"
	fi
	LogNote "$msg"
	calledFrom='called from '
    done
    LogEcho
}


# SplitTime(<time> <secVar> <nanoVar>)
#   store the seconds and nanoseconds of <time> into <secVar> and <nanoVar>
#   nanoseconds are [0, 1*nanosPerS) if seconds > 0, else (-1*nanosPerS, 0]
function SplitTime()
{
    CheckNumArguments $# 3 3

    if [[ "$1" =~ $floatNumRe ]]; then
	printf -v "$2" '%s' "${BASH_REMATCH[1]}"
	local splitTime_str="${BASH_REMATCH[4]-}000000000"
	local -i splitTime_nano="10#${splitTime_str:0:9}"
	if [ "${BASH_REMATCH[2]}" == '-' ]; then
	    (( splitTime_nano *= -1 ))
	fi
	printf -v "$3" '%s' "$splitTime_nano"
    else
	ErrorShutdown setup 'invalid-arg' "$FUNCNAME called with bad time value ($1)"
    fi
}


# JoinTime(<var> <sec> <nanoSec> <prec>)
#   set <var> to the <sec>.<nanoSec> time string with <prec> decimal places
function JoinTime()
{
    CheckNumArguments $# 3 4

    local joinTime_var=$1
    local -i joinTime_sec=$2 joinTime_nanoSec=$3 joinTime_prec=${4:-$defaultTimePrec}
    local joinTime_resultString=

    if [ "$joinTime_sec" -lt 0 ] || [ "$joinTime_nanoSec" -lt 0 ]; then
	joinTime_resultString+='-'
	(( joinTime_sec *= -1 ))
	(( joinTime_nanoSec *= -1 ))
    fi
    joinTime_resultString+=$joinTime_sec
    if [ "$joinTime_prec" -gt 0 ]; then
	local joinTime_nanoString="000000000$joinTime_nanoSec"
	joinTime_resultString+=".${joinTime_nanoString: -9:$joinTime_prec}"
    fi
    printf -v "$joinTime_var" '%s' "$joinTime_resultString"
}


# TimeToString(<var> <time> <prec>)
#   set variable <var> to a human formatted time string from <time> epoch seconds
function TimeToString()
{
    CheckNumArguments $# 2 3

    local -i timeToString_sec timeToString_nano
    local -i timeToString_prec=${3:-$defaultTimePrec}

    SplitTime "$2" timeToString_sec timeToString_nano

    local timeToString_epoch
    JoinTime timeToString_epoch "$timeToString_sec" "$timeToString_nano" "$timeToString_prec"

    if [ "$timeToString_nano" -lt 0 ]; then
	(( timeToString_sec -= 1 ))
	(( timeToString_nano += nanosPerS ))
    fi

    local timeToString_nanoString=
    if [ "$timeToString_prec" -gt 0 ]; then
	timeToString_nanoString="000000000$timeToString_nano"
	timeToString_nanoString=".${timeToString_nanoString: -9:$timeToString_prec}"
    fi

    local fmt="%F %T$timeToString_nanoString  ($timeToString_epoch)"
    if [ -n "$hasPrintfTime" ]; then
	printf -v "$1" "%($fmt)T" "$timeToString_sec"
    else
	printf -v "$1" "%s" "$(date -d "@$timeToString_sec" +"$fmt")"
    fi
}


# CurrentTime(<var> <prec>)
#   set <var> to the current time in seconds since epoch
function CurrentTime()
{
    CheckNumArguments $# 1 2

    local -i currentTime_prec=${2:-$defaultTimePrec}

    # Bash 5 enhancements: $EPOCHSECONDS $EPOCHREALTIME
    if [ "$currentTime_prec" -eq 0 ]; then
	if [ -n "$hasPrintfTime" ]; then
	    printf -v "$1" '%(%s)T' -1
	else
	    printf -v "$1" '%s' "$(date +%s)"
	fi
    else
	printf -v "$1" '%s' "$(date "+%s.%${currentTime_prec}N")"
    fi
}


# DiffTimes(<var> <startTs> <endTs> <prec>)
#   set <var> to the duration between <startTs> and <endTs> truncated to <prec>
function DiffTimes()
{
    CheckNumArguments $# 3 4

    local -i diffTimes_sec1 diffTimes_nano1 diffTimes_sec2 diffTimes_nano2 diffTimes_sec diffTimes_nano
    local -i diffTimes_prec=${4:-$defaultTimePrec}

    SplitTime "$2" diffTimes_sec1 diffTimes_nano1
    SplitTime "$3" diffTimes_sec2 diffTimes_nano2
    (( diffTimes_sec = diffTimes_sec2 - diffTimes_sec1 ))
    (( diffTimes_nano = diffTimes_nano2 - diffTimes_nano1 ))

    # nano is (-2*nanosPerS, 2*nanosPerS)
    while [ "$diffTimes_nano" -lt 0 ]; do
	(( --diffTimes_sec ))
	(( diffTimes_nano += nanosPerS ))
    done
    # nano is [0, 2*nanosPerS)
    if [ "$diffTimes_nano" -ge "$nanosPerS" ]; then
	(( ++diffTimes_sec ))
	(( diffTimes_nano -= nanosPerS ))
    fi
    # nano is [0, 1*nanosPerS)
    if [ "$diffTimes_sec" -lt 0 ] && [ "$diffTimes_nano" -gt 0 ]; then
	(( ++diffTimes_sec ))
	(( diffTimes_nano -= nanosPerS ))
    fi
    # nano is [0, 1*nanosPerS) if sec > 0, else (-1*nanosPerS, 0]
    JoinTime "$1" "$diffTimes_sec" "$diffTimes_nano" "$diffTimes_prec"
}


# BashQuote(<var> <args>...)
#   set global variable <var> to space separated arguments each bash quoted
function BashQuote()
{
    CheckNumArguments $# 1

    local bqOutputVarName=$1
    shift

    if [ $# -eq 0 ]; then
	if ! printf -v "$bqOutputVarName" '%s' ''; then
	    ErrorShutdown setup '' "$FUNCNAME printf failed with exit code $?"
	fi
	return
    fi

    if [ -n "$hasQTransform" ]; then
	if ! printf -v "$bqOutputVarName" '%s' "${*@Q}"; then
	    ErrorShutdown setup '' "$FUNCNAME printf failed with exit code $?"
	fi
    else
	if [ $# -ge 1 ]; then
	    if ! printf -v "$bqOutputVarName" '%q' "$1"; then
		ErrorShutdown setup '' "$FUNCNAME printf failed with exit code $?"
	    fi
	    shift

	    local a
	    for a in "$@"; do
		if ! printf -v "$bqOutputVarName" '%s %q' "${!bqOutputVarName}" "$a"; then
		    ErrorShutdown setup '' "$FUNCNAME printf failed with exit code $?"
		fi
	    done
	fi
    fi
}


# AbsPath(<var> <dir> <path>)
#   assign <var> the value <dir>/<path> if <path> is relative, otherwise <path>
#   if <dir> is empty use the current directory
function AbsPath()
{
    CheckNumArguments $# 3 3
    
    if [ -n "${3##/*}" ]; then
	printf -v "$1" "%s/%s" "${2:-$PWD}" "$3"
    else
	printf -v "$1" "%s" "$3"
    fi
}


# AbsPathIfPath(<var> <dir> <path>)
#   if <path> is empty, set <var> to '', else call AbsPath
function AbsPathIfPath()
{
    CheckNumArguments $# 3 3
 
    if [ -n "$3" ]; then
	AbsPath "$@"
    else
	printf -v "$1" '%s' ''
    fi
}


# ExistingPaths(<existingVar> <nonexistngVarVar> <path>...)
#   if non-empty, set the array variable <existingVar> to the set of paths in
#   <path>... that exist, and if non-empty, set teh array variable <nonexistingVar>
#   to the set of paths in <path>... that do not exist.
function ExistingPaths()
{
    CheckNumArguments $# 2

    local existingVarName=$1  nonexistingVarName=$2
    shift 2

    if [ -n "$existingVarName" ]; then
	eval "$existingVarName=()"
    fi
    if [ -n "$nonexistingVarName" ]; then
	eval "$nonexistingVarName=()"
    fi
    local -i existingCount=0  nonexistingCount=0
    for p in "$@"; do
	if [ -e "$p" ]; then
	    if [ -n "$existingVarName" ]; then
		printf -v "${existingVarName}[$existingCount]" '%s' "$p"
		(( ++existingCount ))
	    fi
	else
	    if [ -n "$nonexistingVarName" ]; then
		printf -v "${nonexistingVarName}[$nonexistingCount]" '%s' "$p"
		(( ++nonexistingCount ))
	    fi
	fi
    done
}


# Initialize()
#   Initialize the system
function Initialize()
{
    # initially log to stderr
    exec 9>&2

    umask 0022

    errorMsgs=()

    # check capabilities of the shell: print %()T, and Q transform
    printf -v scriptStartTime "%(%s)T" -1 &>/dev/null		&& hasPrintfTime=1
    eval ': ${x@Q}' &>/dev/null					&& hasQTransform=1

    CurrentTime scriptStartTime 9
}


# SetLogFile(<filename>)
#   set the log file to <filename>
function SetLogFile()
{
    CheckNumArguments $# 1 1

    if [ -z "$1" ]; then
	ErrorShutdown setup 'invalid-arg' "$FUNCNAME called with empty filename"
    fi

    if ! exec 9> "$1"; then
	ErrorShutdown setup 'log-open' "Failed to open log file $1 for writing"
    fi
    if ! exec 1>&9 2>&9; then
	ErrorShutdown setup 'redirect' "Failed to redirect stdout/err to $1"
    fi
}


# RedirectStdFds(<stdoutFilename> <stderrFilename> <cmdArgs>...)
#   redirects stdout and/or stderr,
#   if <cmdArgs> present, then run <cmdArgs>... and end redirects
function RedirectStdFds()
{
    CheckNumArguments $# 1

    if [ "$1" = "$2" ] && [ -n "$1" ]; then
	LogNote "Redirect stdout and stderr to $1"
	stdoutRedirectedTo=$1
	stderrRedirectedTo=$2
	if ! exec >"$1" 2>&1; then
	    ErrorShutdown setup 'redirect' "redirect stdout and stderr to $1 failed"
	fi
    else
	if [ -n "$1" ]; then
	    LogNote "Redirect stdout to $1"
	    stdoutRedirectedTo=$1
	    if ! exec >"$1"; then
		ErrorShutdown setup 'redirect' "redirect stdout to $1 failed"
	    fi
	fi
	if [ -n "$2" ]; then
	    LogNote "Redirect stderr to $2"
	    stderrRedirectedTo=$2
	    if ! exec 2>"$2"; then
		ErrorShutdown setup 'redirect' "redirect stdout to $2 failed"
	    fi
	fi
    fi

    if	[ $# -gt 2 ]; then
	shift 2
	"$@"
	local r=$?
	EndRedirectStdFds
	return $r
    fi
}


# RedirectAppendStdFds(<filename>)
#   redirects appending stdout and/or stderr,
#   if <cmdArgs> present, then run <cmdArgs>... and end redirects
function RedirectAppendStdFds()
{
    CheckNumArguments $# 1

    if [ "$1" = "$2" ] && [ -n "$1" ]; then
	LogNote "Redirect append stdout and stderr to $1"
	stdoutRedirectedTo=$1
	stderrRedirectedTo=$1
	if ! exec >>"$1" 2>&1; then
	    ErrorShutdown setup 'redirect' "redirect append stdout and stderr to $1 failed"
	fi
    else
	if [ -n "$1" ]; then
	    LogNote "Redirect append stdout to $1"
	    stdoutRedirectedTo=$1
	    if ! exec >>"$1"; then
		ErrorShutdown setup 'redirect' "redirect append stdout to $1 failed"
	    fi
	fi
	if [ -n "$2" ]; then
	    stderrRedirectedTo=$2
	    LogNote "Redirect append stderr to $2"
	    if ! exec 2>>"$2"; then
		ErrorShutdown setup 'redirect' "redirect append stdout to $2 failed"
	    fi
	fi
    fi

    if	[ $# -gt 2 ]; then
	shift 2
	"$@"
	local r=$?
	EndRedirectStdFds
	return $r
    fi
}


# EndRedirectStdFds()
#   restore stdout and stderr to log file if they were redirected
function EndRedirectStdFds()
{
    if [ -n "$stdoutRedirectedTo" ] || [ -n "$stderrRedirectedTo" ]; then
	if [ -n "$stdoutRedirectedTo" ]; then
	    LogNote "End stdout redirect"
	    if ! exec 1>&9; then
		ErrorShutdown setup 'redirect' "restore stdout to log file failed"
	    fi
	    stdoutRedirectedTo=
	fi
	if [ -n "$stderrRedirectedTo" ]; then
	    LogNote "End stderr redirect"
	    if ! exec 2>&9; then
		ErrorShutdown setup 'redirect' "restore stderr to log file failed"
	    fi
	    stderrRedirectedTo=
	fi
	LogEcho
    fi
}


# LogEcho(<strings>...)
#   print <strings>... as a bare echo
function LogEcho()
{
    echo "$@" >&9
}


# LogMsg(<strings>...)
#   print <strings>... as generic log message
function LogMsg()
{
    if [ -z "$TIMESTAMP_LOG_ENTRIES" ]; then
	LogEcho "$logMsgPrefix" "$@"
    else
	local t
	CurrentTime t
	LogEcho "$logMsgPrefix" "$logTsPrefix$t$logTsPostfix" "$@"
    fi
}


# LogNote(<strings>...)
#   print <strings>... as note log message
function LogNote()
{
    LogMsg "$logNotePrefix" "$@"
}


# LogWarning(<strings>...)
#   print <strings>... as warning log message, increment errorCount
function LogWarning()
{
    LogMsg "$logWarningPrefix" "$@"
    AddFailure "$@"
}


# LogError(<strings>...)
#   print <strings>... as error log message, increment errorCount
function LogError()
{
    LogMsg "$logErrorPrefix" "$@"
    AddFailure "$@"
}


# LogTime(<msg> <time>)
#   print <msg> followed by human formatted time from <time> epoch seconds
function LogTime()
{
    CheckNumArguments $# 2 2

    local timeStr
    TimeToString timeStr "$2"
    LogMsg "$1" "$timeStr"
}


# CurrentTimeForTiming(<var> <prec>)
#   set <var> to the current time in seconds since epoch, if LOG_CMD_TIMING is non-empty
function CurrentTimeForTiming()
{
    CheckNumArguments $# 1 2

    if [ -n "$LOG_CMD_TIMING" ]; then
	CurrentTime "$@"
    else
	printf -v "$1" "%s" ''
    fi
}


# LogTiming(<start> <end> <msg> <forceLogging>)
#   print timing information including duration if $LOG_CMD_TIMING or <forceLogging> are set
function LogTiming()
{
    CheckNumArguments $# 3 4

    local start=$1  end=$2  msg=$3  force=$4

    if [ -z "$LOG_CMD_TIMING$force" ] || [ -z "$start" ] || [ -z "$end" ]; then
	return
    fi

    local duration
    DiffTimes duration "$start" "$end"

    LogMsg  "$logTimingPrefix Command Timing ($msg):"
    LogTime "$logTimingPrefix	Start time: " "$start"
    LogTime "$logTimingPrefix	End time:   " "$end"
    LogMsg  "$logTimingPrefix	Duration:   " "$duration"
    LogEcho
}


# CallFromInDir(<pos> <cmdArgs>...)
#   execute <cmdArgs>... after prefixing cmdArg[<pos>] with $VMINPUTDIR/
function CallFromInDir()
{
    CheckNumArguments $# 2
    CheckNumArguments $# "$(( $1 + 2 ))"

    local n=$1
    shift
    local cmdArgs=( "$@" )
    local absPath
    AbsPath absPath "$VMINPUTDIR" "${cmdArgs[$n]}"
    cmdArgs[$n]=$absPath
    "${cmdArgs[@]}"
}


# CallIfIsCmd(<pos> <cmdArgs>...)
#   execute <cmdArgs>... if <cmdArgs>[<pos>] is a valid command
function CallIfIsCmd()
{
    CheckNumArguments $# 2
    CheckNumArguments $# "$(( $1 + 2 ))"

    local n=$(( $1 + 1 ))
    shift
    if type ${!n} &>/dev/null; then
	"$@"
    else
	LogNote "Command not found, not running:" "$@"
    fi
}


# ValidateExecIgnoreFail(<execPath>)
#   Shutdown if the executable is not found or is not executable
function ValidateExecIgnoreFail()
{
    CheckNumArguments $# 1 1

    if [ ! -f "$1" ]; then
	LogWarning "Executable ($1) not found"
	return 1
    fi
    if [ ! -x "$1" ]; then
	LogWarning "Executable ($1) not executable"
	return 1
    fi

    return 0
}


# ValidateExec(<execPath>)
#   Shutdown if the executable is not found or is not executable
function ValidateExec()
{
    ShutdownIfFail setup 'command-not-executable' ValidateExecIgnoreFail "$@"
}


# ValidateVarsAreSet(<type> <var>...)
#   validate each <var> is set to a non-empty value
function ValidateVarsAreSet()
{
    CheckNumArguments $# 2

    local type=$1
    shift

    local v
    for v in "$@"; do
	if [ -z "${!v}" ]; then
	    ErrorShutdown setup "invalid-$type-var" "required $type var $v is not set"
	fi
    done
}


# ValidateVarsAreInts(<type> <var>...)
#   validate each <var> is either empty or an integer
function ValidateVarsAreInts()
{
    CheckNumArguments $# 2

    local type=$1
    shift

    local v
    for v in "$@"; do
	if [ -n "${!v}" ] && ! IsInteger "${!v}"; then
	    ErrorShutdown setup "invalid-$type-var" "$type var $v is not an integer"
	fi
    done
}


# ValidateVarsAreDirs(<type> <var>...)
#   validate each <var> is set to a non-empty value that is a path to a directory
function ValidateVarsAreDirs()
{
    CheckNumArguments $# 2

    ValidateVarsAreSet "$@"

    local type=$1
    shift

    local v
    for v in "$@"; do
	if [ ! -d "${!v}" ]; then
	    ErrorShutdown setup "invalid-$type-var" "$type var $v (${!v}) is not a directory"
	fi
    done
}


# LogVariableValues(<var>...)
#   Log each <var> and its value
function LogVariableValues()
{
    local s
    for v in "$@"; do
	printf -v s "\$%-16s %s" "$v:" "${!v}"
	LogNote "$s"
    done
    LogEcho
}


# LogCmdIgnoreFail(<args>...)
#   run cmd <args>..., on fail log error
function LogCmdIgnoreFail()
{
    CheckNumArguments $# 1

    local quotedCmd startTime endTime
    BashQuote quotedCmd "$@"
    LogMsg "$logCmdPrefix" "$quotedCmd"

    CurrentTimeForTiming startTime

    if [ "$( type -t "$1" )" != 'file' ]; then
	"$@"
    else
	"$@" 9>&-
    fi
    local r=$?

    CurrentTimeForTiming endTime

    LogEcho
    if [ $r -ne 0 ]; then
	LogWarning "Command failed with exit code $r: $quotedCmd" $'\n'
    fi

    LogTiming "$startTime" "$endTime" "$quotedCmd"

    return $r
}


# LogCmd(<args>...)
#   run cmd <args>..., on fail log error and shutdown/exit
function LogCmd()
{
    ShutdownIfFail setup 'command-failed' LogCmdIgnoreFail "$@"
}


# LogScriptIgnoreFail(<<bashCmdString>)
#   eval <bashCmdString>, on fail log error
function LogScriptIgnoreFail()
{
    CheckNumArguments $# 1

    local quotedCmd startTime endTime
    BashQuote quotedCmd eval "$1"
    LogMsg "$logCmdPrefix" "$quotedCmd"

    CurrentTimeForTiming startTime

    ( eval "$1" ) 9>&-
    local r=$?

    CurrentTimeForTiming endTime

    LogEcho
    if [ $r -ne 0 ]; then
	LogWarning "Command failed with exit code $r: $quotedCmd" $'\n'
    fi

    LogTiming "$startTime" "$endTime" "$quotedCmd"

    return $r
}


# LogScript(<bashCmdString>)
#   eval <bashCmdString>, on fail log error and shutdown/exit
function LogScript()
{
    ShutdownIfFail setup 'command-failed' LogScriptIgnoreFail "$@"
}


# LogUserCmdIgnoreFail(<user> <cmdArg>...)
#   run command <cmdArg>... as user <user>, on fail log error
function LogUserCmdIgnoreFail()
{
    CheckNumArguments $# 2

    local user=$1
    shift

    local quotedCmd
    BashQuote quotedCmd "$@"
    LogUserScriptIgnoreFail "$user" "$quotedCmd"
}


# LogUserCmd(<user> <cmdArg>...)
#   run command <cmdArg>... as user <user>, on fail log error and shutdown/exit
function LogUserCmd()
{
    ShutdownIfFail setup 'command-failed' LogUserCmdIgnoreFail "$@"
}


# LogUserScriptIgnoreFail(<user> <bashCmdString>)
#   run command <bashCmdString> as user <user>, on fail log error
function LogUserScriptIgnoreFail()
{
    CheckNumArguments $# 2 2

    local user=$1  cmd=$2
    if [ -z "$user" ]; then
	ErrorShutdown setup 'invalid-arg' "$FUNCNAME called with empty username"
    fi
    if [ -z "$cmd" ]; then
	ErrorShutdown setup 'invalid-arg' "$FUNCNAME called with empty command"
    fi

    LogCmdIgnoreFail su -c "$cmd" - "$user"
}


# LogUserScript(<user> <bashCmdString>)
#   run command <bashCmdString> as user <user>, on fail log error and shutdown/exit
function LogUserScript()
{
    ShutdownIfFail setup 'command-failed' LogUserScriptIgnoreFail "$@"
}


# LogBgCmd(<cmdArg>...)
#   run cmd <cmdArg>... in the background
function LogBgCmd()
{
    CheckNumArguments $# 1

    local quotedCmd
    BashQuote quotedCmd "$@"
    LogMsg "$logBgCmdPrefix" "$quotedCmd" '&'

    if [ "$( type -t "$1" )" != 'file' ]; then
	"$@" &
    else
	"$@" 9>&- &
    fi
    local r=$?  pid=$!

    if [ $r -ne 0 ]; then
	LogWarning "Background command failed to start with exit code $r: $quotedCmd &" $'\n'
    else
	LogNote "Background command started (pid=$pid)"
	bgPids+=( "$pid" )
    fi
    LogEcho

    return $r
}


# LogBgScript(<bashCmdString>)
#   eval <bashCmdString> in the background
function LogBgScript()
{
    CheckNumArguments $# 1

    LogBgCmd "$BASH" -c "$1"
}


# LogBgUserCmd(<user> <cmdArg>...)
#   run command <cmdArg>... as user <user> in the background
function LogBgUserCmd()
{
    CheckNumArguments $# 2

    local user=$1
    shift

    local quotedCmd
    BashQuote quotedCmd "$@"
    LogBgUserScript "$user" "$quotedCmd"
}


# LogUserScript(<user> <bashCmdString>)
#   run command <bashCmdString> as user <user> in the background
function LogBgUserScript()
{
    CheckNumArguments $# 2 2

    local user=$1  cmd=$2
    if [ -z "$user" ]; then
	ErrorShutdown setup 'invalid-arg' "$FUNCNAME called with empty username"
    fi
    if [ -z "$cmd" ]; then
	ErrorShutdown setup 'invalid-arg' "$FUNCNAME called with empty command"
    fi

    LogBgCmd su -c "$cmd" - "$user"
}


# KillBgCmds(<pid>...)
#   send each <pid>... a SIGTERM, wait up to (killTermWaitCount * killTermWaitInterval)
#   seconds and send each still running process a SIGKILL
function KillBgCmds()
{
    if [ $# -ne 0 ]; then
	LogNote "Killing background command pids: $*"
	local -a pids=() existingPids=()
	local p
	local -i i
	local -i killTermWaitInterval=1 killTermWaitCount=10 killKillWaitInterval=2

	# save and ignore SIGTERM trap (fedora 20 su sends SIGTERM to pgid of this proc)
	local savedTermTrap
	savedTermTrap=$(trap -p SIGTERM)
	LogCmdIgnoreFail trap ':' SIGTERM

	# everyone pid gets a SIGTERM
	for p in "$@"; do
	    LogCmdIgnoreFail kill -s SIGTERM "$p"
	done

	# check for processes to stop
	existingPids=( "$@" )
	for (( i=0; i<killTermWaitCount; ++i )); do
	    pids=()
	    for p in "${existingPids[@]}"; do
		if kill -n 0 "$p" >/dev/null 2>&1; then
		    pids+=( "$p" )
		else
		    LogNote "Process $p no longer exists"
		fi
	    done
	    existingPids=( "${pids[@]}" )
	    if [ "${#pids[@]}" -eq 0 ]; then
		break;
	    fi
	    sleep "$killTermWaitInterval"
	done

	# for any still running pid, send a SIGKILL, wait, and report status
	if [ "${#pids[@]}" -ne 0 ]; then
	    for p in "${pids[@]}"; do
		LogCmdIgnoreFail kill -s SIGKILL "$p"
	    done
	    sleep "$killKillWaitInterval"
	    existingPids=()
	    for p in "${pids[@]}"; do
		if kill -n 0 "$p" >/dev/null 2>&1; then
		    LogNote "Process $p still exists"
		    existingPids+=( "$p" )
		else
		    LogNote "Process $p no longer exists"
		fi
	    done
	fi

	if [ "${#existingPids[@]}" -eq 0 ]; then
	    LogNote "All background commands successfully stopped"
	else
	    LogWarning "The following background commands were not stopped: ${existingPids[*]}"
	fi
	LogEcho

	# restore SIGTERM trap
	LogMsg "$logCmdPrefix" "$savedTermTrap"
	eval "$savedTermTrap"
	LogEcho
    fi
}


# LogBgJobsFromVars(<prefix> <jobType> <cmdArg>...)
#   for all variables the start with <prefix>_<jobType>_<id>, run <cmdArg>... with
#   the value as a parameter.  If <prefix>_OUTFILE_<id> exists redirect stdout and
#   stderr to this file (relative to VMOUTPUTDIR), otherwise it is discarded.
#   If <prefix>_NAME_<id> exists, add output_files entry with this value.
function LogBgJobsFromVars()
{
    CheckNumArguments $# 3

    local prefix=$1  jobType=$2
    local scriptVarPrefix="${prefix}_${jobType}_"
    shift 2

    for v in $(compgen -v "$scriptVarPrefix"); do
	local value=${!v}
	local suffix=${v#$scriptVarPrefix}
	local fileVar="${prefix}_OUTFILE_$suffix"
	local nameVar="${prefix}_NAME_$suffix"
	local name=${!nameVar-}
	local file
	AbsPathIfPath file "$VMOUTPUTDIR" "${!fileVar-}"
	if [ -z "$file" ]; then
	    file=/dev/null
	fi
	local -a cmd
	if [ "$jobType" = 'SCRIPT' ]; then
	    cmd=( "$value" )
	else
	    cmd=( $value )
	fi

	RedirectStdFds "$file" "$file" "$@" "${cmd[@]}"
	AddOutputFilesEntry "$outputFilesConf" "$name" "$file"
    done
}


# WriteStatusOut(<filename> <task> <subtask> <longMsgLines>...)
#   generate a status.out file at <filename> if it doesn't exist.  add retry if task is network
function WriteStatusOut()
{
    CheckNumArguments $# 1

    if [ -z "$VMOUTPUTDIR" ] || [ ! -d "$VMOUTPUTDIR" ]; then
	return 1
    fi

    local filename=$1

    if [ -z "$filename" ]; then
	LogNote "Not creating status.out, path not set" $'\n'
    elif [ -f "$filename" ]; then
	LogNote "Status.out ($filename) exists" $'\n'
    else
	AddOutputFilesEntry "$outputFilesConf" statusOut "$filename"
	local task
	if [ $# -ge 2 ]; then
	    task=$2
	    shift 2

	    local taskString=$task  subtask=
	    if [ $# -ge 1 ]; then
		subtask=$1
		shift
		if [ -n "$subtask" ]; then
		    taskString+=" ($subtask)"
		fi
	    fi
	fi

	LogNote "Creating status.out${task:+" with fail task '$task'"} at $filename"
	RedirectStdFds "$filename"
	    echo			"NOTE: begin"
	    echo			"NOTE: generator ($0)"
	    if [ -n "$task" ]; then
		echo			"FAIL: $taskString"
		if [ $# -ge 1 ]; then
		    printf '  %s\n' '----------' "${@//$'\n'/$'\n  '}" '----------'
		fi
		if [ "$task" = 'network' ]; then
		    echo		"NOTE: retry"
		fi
		echo			"FAIL: all"
	    else
		echo			"PASS: all"
	    fi
	    echo			"NOTE: end"
	EndRedirectStdFds
	LogNote "Created status.out"
    fi
}


# ArchivePaths(<outputFilesKey> <archive> <path>...)
#   Create gzipped tar file in <archive> containing paths in <path>...
#   No archive is created if <archive> is empty or if there are no <path>...
#   If archive is created and outputFilesKey, add entry to output_files.conf
#   Failure of the tar command are ignored.
function ArchivePaths()
{
    CheckNumArguments $# 2

    local outputFilesKey=$1  archive=$2
    shift 2

    if [ -n "$archive" ] && [ $# -gt 0 ]; then
	local quotedArchive quotedFiles
	BashQuote quotedArchive "$archive"
	BashQuote quotedFiles "$@"
	# ignore errors from tar as files can be changing while running
	LogScriptIgnoreFail "tar czf $quotedArchive $quotedFiles ; :"
	if [ -n "$outputFilesKey" ]; then
	    AddOutputFilesEntry "$outputFilesConf" "$outputFilesKey" "$archive"
	fi
    fi
}


# CpPaths(<toDir> <path>...)
#   copy files specified by <path>... to <toDir>.  Skip if <toDir> or <path>...
#   is empty
function CpPaths()
{
    CheckNumArguments $# 1

    local toDir=$1
    shift

    if [ -n "$toDir" ] && [ $# -gt 0 ]; then
	LogCmdIgnoreFail 'cp' "$@" "$toDir"
    fi
}


# CapturePaths(<outputFilesKey> <method> <archive> <path>...)
#   Capture the paths given by <path>... using the mechanism specified by
#   <method> (tar or cp).  Nonexistent paths in <path>... are removed from the
#   paths to capture.  Skips capture if <method> is 'disable' or no paths exist.
function CapturePaths()
{
    CheckNumArguments $# 3

    local outputFilesKey=$1  method=$2  archive=$3
    shift 3

    if [ $# -eq 0 ] || [ "$method" = 'disable' ] || { [ "$method" = 'tar' ] && [ -z "$archive" ]; }; then
	return
    fi

    case "$method" in
	tar)	LogNote "Capturing files to archive $archive"					;;
	cp)	LogNote "Capturing files to directory $VMOUTPUTDIR"				;;
	*)	LogNote "CapturePaths invalid CAPTURE_METHOD ($method), skipping" $'\n'; return	;;
    esac

    local -a existing nonexisting
    ExistingPaths existing nonexisting "$@"
    if [ "${#existing[@]}" -gt 0 ]; then
	if [ "${#nonexisting[@]}" -gt 0 ]; then
	    LogNote "  excluding non-existent paths:" "${nonexisting[@]}"
	fi
    else
	LogNote "  skipping capture, no paths exist:" "${nonexisting[@]}" $'\n'
    fi

    case "$method" in
	tar)	ArchivePaths "$outputFilesKey" "$archive" "${existing[@]}"	;;
	cp)	CpPaths "$VMOUTPUTDIR" "${existing[@]}"				;;
    esac
}


# WaitUntilNoCmdOutput(<waitCmd> <sleepTime> <logOutput> <alwaysWaitFile> <stopWaitFile>)
#   Loop until <waitCmd> returns no output or fails, sleep <sleepTime> between
#   each run, and log command output changes if <logOutput> is non-empty.
#   If <stopWaitFile> is set and the file exists, immediately stop waiting
#   If <alwaysWaitFile> is set and the file exists, then wait for its removal
function WaitUntilNoCmdOutput()
{
    CheckNumArguments $# 3 5

    local waitCmd=$1  sleepTime=$2  logOutput=$3  alwaysWaitFile=$4  stopWaitFile=$5

    local output lastOutput
    local startTime curTime curTimeStr duration
    local quotedCmd
    local foundAlwaysWaitFile

    CurrentTime startTime
    BashQuote quotedCmd eval "$waitCmd"

    if [ -z "$waitCmd" ] && [ -z "$alwaysWaitFile" ]; then
	return
    fi

    LogNote "Wait until:  checking every ${sleepTime}s with:  $quotedCmd"
    LogVariableValues alwaysWaitFile stopWaitFile
    while :; do
	if [ -n "$stopWaitFile" ] && [ -e "$stopWaitFile" ]; then
	    LogNote "Wait until:  stop-wait file ($stopWaitFile) found, stopping wait"
	    break
	fi
	if [ -n "$alwaysWaitFile" ] && [ -e "$alwaysWaitFile" ]; then
	    if [ -z "$foundAlwaysWaitFile" ]; then
		LogNote "Wait until:  always-wait file $alwaysWaitFile) found, waiting for removal" $'\n'
		foundAlwaysWaitFile=1
	    fi
	else
	    if [ -n "$foundAlwaysWaitFile" ]; then
		LogNote "Wait until:  always-wait file ($alwaysWaitFile) removed, continuing wait" $'\n'
		foundAlwaysWaitFile=
	    fi
	    if [ -n "$waitCmd" ]; then
		output=$(eval "$waitCmd" 2>&1)
		r=$?
		if [ $r -ne 0 ]; then
		    LogMsg "$logCmdPrefix" "$quotedCmd"
		    LogEcho "$output" $'\n'
		    LogWarning "Wait until:  done, command failed with exit code $r: $quotedCmd"
		    break
		fi
		if [ -z "$output" ]; then
		    LogMsg "$logCmdPrefix" "$quotedCmd" $'\n'
		    LogNote "Wait until:  done, command produced no output"
		    break
		fi
		if [ -n "$logOutput" ] && [ "$output" != "$lastOutput" ]; then
		    CurrentTime curTime
		    TimeToString 'curTimeStr' "$curTime"
		    LogNote "Wait until:  new output at $curTimeStr:"
		    LogMsg "$logCmdPrefix" "$quotedCmd"
		    LogEcho "$output" $'\n'
		    WriteSwampEvent 'CONNECTEDUSERS'
		    lastOutput=$output
		fi
	    fi
	fi
	if ! sleep "$sleepTime"; then
	    LogNote "Wait until:  sleep $sleepTime failed with exit code $?, stopping wait"
	    break
	fi
    done
    CurrentTime curTime
    DiffTimes duration "$startTime" "$curTime"
    LogNote "Wait until:  wait complete, delayed $duration seconds" $'\n'
}


# WaitForever(<exitCode>)
#   Wait forever (for use in a docker container) using WaitUntilNoCmdOutput
#   Used in NO_SHUTDOWN_CMD so fd 9 needs to be open so use stderr
function WaitForever()
{
    WaitUntilNoCmdOutput 'echo "waiting forever"' 30 1 "$delayShutdownAlwaysWaitFile" "$delayShutdownStopWaitFile" 9>&2
}


# NoShutdownExit(<exitCode>)
#   call $NO_SHUTDOWN_CMD <exitCode>, exitCode defaults to 0
function NoShutdownExit()
{
    local exitCode=$1
    if [ -z "$exitCode" ]; then
	exitCode=0
    fi
    if [ -z "$NO_SHUTDOWN_CMD" ]; then
	NO_SHUTDOWN_CMD='exit'
    fi
    LogCmdIgnoreFail $NO_SHUTDOWN_CMD $exitCode
    LogNote "NoShutdownExit command returned, exiting"
    LogCmd exit "$exitCode"
}


# ShutdownExit(<exitCode>)
#   call $VMSHUTDOWN or if it fails $NO_SHUTDOWN_CMD <exitCode>, exitCode defaults to 0
function ShutdownExit
{
    LogCmdIgnoreFail trap - SIGTERM
    if LogCmdIgnoreFail $VMSHUTDOWN; then
	NoShutdownExit "$1"
    fi

    LogError "Shutdown failed, exiting"
    exit 1
}


# LogSignalHandler(<sigName> <cmd>...)
#   Log Trap caught with call stack and call <cmd> <exitCode> where <exitCode> is <sigNum> + 128
function LogSignalHandler
{
    CheckNumArguments $# 1
    local sigName
    local -i sigNum
    if IsInteger "$1"; then
	sigName=$(kill -l "$1")
	sigNum=$1
    else
	sigName=$1
	sigNum=$(kill -l "$1")
    fi

    local -i exitCode=128+sigNum
    LogError "Caught signal $sigName ($sigNum)"
    LogNote  "  while executing: $BASH_COMMAND"
    LogCallStack 0
    shift
    if [ $# -gt 0 ]; then
	LogCmdIgnoreFail "$@" "$exitCode"
    fi
}


# Shutdown(<exitCode> <msgs>...)
#   print <msgs>..., shutdown if VM and not NOSHOTDOWN, otherwise exit with <exitCode>
#   also log info, and if enabled: kill background commands, capture files, and delay
function Shutdown()
{
    LogNote "Begin $FUNCNAME"

    local -i exitCode=0
    if [ $# -gt 0 ]; then
	exitCode=$1
	shift
    fi

    if [ $# -ge 1 ] && [ "$exitCode" -ne 0 ]; then
	LogError "$@"
    fi

    if [ -n "$inShutdown" ]; then
	LogError "$FUNCNAME called recursively, ignoring"
	return 1
    fi
    inShutdown=1

    EndRedirectStdFds

    LogEcho
    LogFinalInfo

    if [ -z "$NORUNPAYLOAD" ]; then
	WriteStatusOut "$statusOut"
    fi

    CapturePaths captureArchive "$CAPTURE_METHOD" "$captureArchive" $CAPTURE_FILES

    KillBgCmds "${bgPids[@]}"

    if ! LogCmdIgnoreFail chown -R "$SWAMP_USERNAME.$SWAMP_GROUPNAME" "$VMOUTPUTDIR"; then
	LogCmdIgnoreFail chown -R "$SWAMP_USERID" "$VMOUTPUTDIR"
	LogCmdIgnoreFail chgrp -R "$SWAMP_GROUPID" "$VMOUTPUTDIR"
    fi
    LogCmdIgnoreFail "${lsCmd[@]}" "$VMOUTPUTDIR"
    LogCmd date "$dateFmt"

    if [ "$exitCode" -eq 0 ]; then
	LogNote "end $0 successfully" "$@"
    else
	LogNote "end $0 due to error"
    fi

    local scriptEndTime
    CurrentTime scriptEndTime
    LogTiming "$scriptStartTime" "$scriptEndTime" "$0" 1

    LogNote "Shutting down"

    if [ -n "$NOSHUTDOWN" ]; then
	LogNote "NOSHUTDOWN set, exiting without shutdown"
	VMSHUTDOWN=''
    fi

    if [ -z "$VMSHUTDOWN" ]; then
	# if not shutting down, no need to wait for users or delay
	NoShutdownExit "$exitCode"
    fi

    if [ -n "$DELAY_SHUTDOWN_UNTIL" ]; then
	local afterStartWait=$DELAY_SHUTDOWN_UNTIL_SECONDS_AFTER_START
	if [ -n "$afterStartWait" ] && [ $afterStartWait -gt 0 ]; then
	    local duration
	    DiffTimes duration "$scriptStartTime" "$scriptEndTime" 0
	    local sleepTime=$(( afterStartWait - duration ))
	    if [ "$sleepTime" -gt 0 ]; then
		LogNote "Sleeping ${sleepTime}s to wait ${afterStartWait}s after start of $0"
		LogCmd sleep "$sleepTime"
	    fi
	fi

	WaitUntilNoCmdOutput "$DELAY_SHUTDOWN_CMD" "$DELAY_SHUTDOWN_CHECK_INTERVAL" "$DELAY_SHUTDOWN_LOG_CMD_OUTPUT" \
			    "$delayShutdownAlwaysWaitFile" "$delayShutdownStopWaitFile"
    fi
    WriteSwampEvent 'ENDASSESSMENT'

    ShutdownExit "$exitCode"
}


# ErrorShutdownWithMsg(<errorMsg> <task> <subtask> <longMsgLines>...)
#   log <errorMsg>, create status.out, shutdown
function ErrorShutdownWithMsg()
{
    local shutdownNote=$1
    shift

    LogError "Shutting down:" "$shutdownNote"
    LogCallStack

    if [ -n "$inErrorShutdown" ]; then
	LogError "$FUNCNAME called recursively, ignoring"
	return 1
    fi
    inErrorShutdown=1

    EndRedirectStdFds

    WriteStatusOut "$statusOut" "$@"
    Shutdown 1
}


# ErrorShutdown(<errorMsg> <task> <subtask> <longMsgLines>...)
#   log <errorMsg>, create status.out using the first line of <longMsgLines> for shutdown message
function ErrorShutdown()
{
    ErrorShutdownWithMsg "$3" "$@"
}


# ShutdownIfErrors()
#   shutdown if the error count is greater than 0
function ShutdownIfErrors()
{
    if [ "${#errorMsgs[@]}" -gt 0 ]; then
	ErrorShutdown setup 'command-failed' "${#errorMsgs[@]} previous failures" '' "${errorMsgs[@]}"
    fi
}


# AddFailure(<msgArgs>...)
#   add the message to the errorMsgs array
function AddFailure()
{
    errorMsgs+=( "$*" )
}


# ShutdownIfFail(<task> <subtask> <cmdArgs>...)
#   Run command args, if non-0 exit, then ErrorShutdown using
#   the last error or warn mssage as the shutdown message
function ShutdownIfFail()
{
    CheckNumArguments $# 3

    local task=$1  subtask=$2
    shift 2

    "$@"
    local r=$?
    if [ $r -ne 0 ]; then
	ErrorShutdown "$task" "$subtask" "${errorMsgs[$((${#errorMsgs[@]}-1))]}"
    fi

    return $r
}


# AddOutputFilesEntry(<filename> <key> <value>)
#   write a the <key>, <value> pair to <filename>, making <value> relative to <filename>
function AddOutputFilesEntry()
{
    CheckNumArguments $# 3 3

    if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ]; then
	local v=${3#${1%/*}/}
	LogNote "Adding output files entry to $1:  $2=$v"
	RedirectAppendStdFds "$1" '' printf "%s=%s\n" "$2" "$v"
    fi
}


# ReadConfFile(<filename> <varNames> <varNamePrefixes>)
#   source the conf file and set the specified variable names in <varNames>
#   and variables that match prefixes in <varNamePrefixes>
function ReadConfFile()
{
    CheckNumArguments $# 2 3

    local filename=$1  varNames=$2  varNamePrefixes=$3

    if [ ! -f "$filename" ]; then
	ErrorShutdown setup conf-file-missing "conf file '$filename' not found"
    fi

    LogCmdIgnoreFail cat "$filename"

    LogNote "Processing conf file $filename"
    local data
    data=$(
	set -e
	
	. "$filename" >&9

	for i in $varNames; do
	    if [ -n "${!i+isSet}" ]; then
		printf "%s=%q\n" "$i" "${!i}"
	    fi
	done
	for p in $varNamePrefixes; do
	    for i in $(compgen -v "$p"); do
		printf "%s=%q\n" "$i" "${!i}"
	    done
	done
    )
    local r=$?

    if [ $r -eq 0 ]; then
	eval "$data"
	r=$?
	LogEcho
	if [ $r -ne 0 ]; then
	    ErrorShutdown setup conf-file "Processing conf file '$filename' eval of output failed with exit code $r"
	fi
    else
	LogEcho
	ErrorShutdown setup conf-file "Processing conf file '$filename' sourcing as sh script failed with exit code $r"
    fi

    LogEcho "Variables set:"
    local i line
    for i in $varNames; do
	if [ -n "${!i+isSet}" ]; then
	    printf -v line "  %s=%q" "$i" "${!i}"
	    LogEcho "$line"
	fi
    done
    local p
    for p in $varNamePrefixes; do
	for i in $(compgen -v "$p"); do
	    printf -v line "  %s=%q" "$i" "${!i}"
	    LogEcho "$line"
	done
    done
    LogEcho
}


###########################################################

# ReadConfFileAndValidateVars(<confFile> <varNames> <varNamePrefixes>)
#   verify variables, process <confFile>, set synthesized values
function ReadConfFileAndValidateVars()
{
    CheckNumArguments $# 2 3

    # validate environment variables
    ValidateVarsAreDirs env VMINPUTDIR
    ValidateVarsAreSet env VMSHUTDOWN

    # read run-params.conf and verify required variables are set
    ReadConfFile "$@"

    # make group name and id match user if not set
    if [ -z "$SWAMP_GROUPNAME" ]; then
	SWAMP_GROUPNAME=$SWAMP_USERNAME
    fi
    if [ -z "$SWAMP_GROUPID" ]; then
	SWAMP_GROUPID=$SWAMP_USERID
    fi

    if [ -z "$NETWORK_WAIT_TIME" ]; then
	NETWORK_WAIT_TIME=$SLEEP_TIME
    fi
    AbsPathIfPath buildAssessOut		"$VMOUTPUTDIR"	"$BUILD_ASSESS_OUTPUT"
    AbsPathIfPath envSh				"$VMOUTPUTDIR"	"$ENV_SH"
    AbsPathIfPath earlyCaptureArchive		"$VMOUTPUTDIR"	"$EARLY_CAPTURE_ARCHIVE"
    AbsPathIfPath captureArchive		"$VMOUTPUTDIR"	"$CAPTURE_ARCHIVE"
    AbsPathIfPath ipAddrFile			"$VMOUTPUTDIR"	"$IP_ADDR_FILE"
    AbsPathIfPath swampEventFile		"$VMOUTPUTDIR"	"$SWAMP_EVENT_FILE"
    AbsPathIfPath delayShutdownAlwaysWaitFile	"$VMOUTPUTDIR"	"$DELAY_SHUTDOWN_ALWAYS_WAIT_FILE"
    AbsPathIfPath delayShutdownStopWaitFile	"$VMOUTPUTDIR"	"$DELAY_SHUTDOWN_STOP_WAIT_FILE"
    AbsPathIfPath userConf			"$VMINPUTDIR"	"$USER_CONF"

    ValidateVarsAreSet run-params SWAMP_USERNAME SWAMP_USERID CAPTURE_METHOD
    ValidateVarsAreInts run-params DEFAULT_TIME_PRECISION SWAMP_USERID SWAMP_GROUPID				\
				    SLEEP_TIME NETWORK_WAIT_TIME DNS_WAIT_TIME TIME_PRECISION			\
				    DELAY_SHUTDOWN_UNTIL_SECONDS_AFTER_START DELAY_SHUTDOWN_CHECK_INTERVAL 

    if [ -n "$TIME_PRECISION" ]; then
	defaultTimePrec=$TIME_PRECISION
    fi
    if [ "$CAPTURE_METHOD" != 'tar' ] && [ "$CAPTURE_METHOD" != 'cp' ] && [ "$CAPTURE_METHOD" != 'disable' ]; then
	ErrorShutdown setup invalid-run-params-var  \
				"run-params var CAPTURE_METHOD ($CAPTURE_METHOD) is invalid (must be tar or cp)"
    fi
}


# LogIntialInfo()
#   log initial information about host, ignoring failure
function LogInitialInfo()
{
    LogCmdIgnoreFail date "$dateFmt"
    LogCmdIgnoreFail date -u "$dateFmt"
    LogCmdIgnoreFail date +'%s.%N'
    LogCmdIgnoreFail id
    LogCmdIgnoreFail pwd
    LogCmdIgnoreFail env
    LogCmdIgnoreFail umask
    LogVariableValues PPID '$' BASH BASH_VERSION BASHOPTS '-' containerType quotedCmdLine
    LogCmdIgnoreFail mount
    LogFinalInfo
    LogCmdIgnoreFail lscpu
    LogCmdIgnoreFail free -k -t
    CallIfIsCmd 1 LogCmdIgnoreFail lsb_release -a
    CallFromInDir 3 CallIfIsCmd 1 LogCmdIgnoreFail $buildAssessDriver --version
    CallFromInDir 3 CallIfIsCmd 1 LogCmdIgnoreFail $getPlatform
    LogCmdIgnoreFail trap -p
}


# LogUserInfo()
#   log information about the user, ignoring failures
function LogUserInfo()
{
    CheckNumArguments $# 1 1

    local user=$1

    LogUserCmdIgnoreFail "$user" id
    LogUserCmdIgnoreFail "$user" pwd
    LogUserCmdIgnoreFail "$user" env
    LogUserCmdIgnoreFail "$user" umask
    LogUserCmdIgnoreFail "$user" "${lsCmd[@]}"
    LogUserCmdIgnoreFail "$user" ulimit -a -S
    LogUserCmdIgnoreFail "$user" ulimit -a -H
}


# LogNetworkInfo()
#   log information about the network, ignoring failures
function LogNetworkInfo()
{
    LogCmdIgnoreFail hostname
    LogCmdIgnoreFail ip -s -d link
    LogCmdIgnoreFail ip -s -d addr
    LogCmdIgnoreFail ip -s -d route
    if [ "$networkState" -gt 0 ]; then
	: # takes too long on some hosts LogCmdIgnoreFail dnsdomainname
    fi
    LogCmdIgnoreFail date "$dateFmt"
}


# LogFinalInfo()
#   log final information about host, ignoring failure
function LogFinalInfo()
{
    local d
    for d in / /tmp "$VMINPUTDIR" "$VMOUTPUTDIR"; do
	LogCmdIgnoreFail "${lsCmd[@]}" "$d"
    done
    LogCmdIgnoreFail df
    LogCmdIgnoreFail df -i
    LogNetworkInfo
}


# CreateUser()
#   create the user account along with the group, set the password, shell,
#   make ~/.cache, and add the user to sudoers
function CreateUser()
{
    ValidateVarsAreSet env VMGROUPADD VMUSERADD

    # adjust VMUSERADD if not el based OS
    if [ ! -f /etc/redhat-release ]; then
	VMUSERADD+=" -m"
	LogNote "Found non-RedHat system, assuming debian"
	LogNote "   set VMUSERADD to '$VMUSERADD'"
    fi

    #create the user and group
    LogCmd $VMGROUPADD -g "$SWAMP_GROUPID" "$SWAMP_GROUPNAME"
    LogCmd $VMUSERADD -u "$SWAMP_USERID" -g "$SWAMP_GROUPID" "$SWAMP_USERNAME"

    userHomeDir=$(eval echo ~"$SWAMP_USERNAME")
    if [ ! -d "$userHomeDir" ]; then
	ErrorShutdown setup 'no-home-dir' "~$SWAMP_USERNAME, $userHomeDir, is not a directory"
    fi

    # set the password for the user
    if [ -n "$SWAMP_PASSWORD" ]; then
	chpasswdCmd=chpasswd
	if [ -n "$SWAMP_PASSWORD_IS_ENCRYPTED" ]; then
	    chpasswdCmd+=" -e"
	fi
	LogNote "Changing Password of username $SWAMP_USERNAME"
	LogCmd $chpasswdCmd <<<"$SWAMP_USERNAME:$SWAMP_PASSWORD"
    else
	LogNote "SWAMP_PASSWORD not set, not setting password for username $SWAMP_USERNAME" $'\n'
    fi

    # set the shell to bash for the user
    LogCmd chsh -s /bin/bash "$SWAMP_USERNAME"

    ## too many things try manipulating this, and if it doesn't already
    ## exist you can end up with a race condition.  Just fix it for
    ## everything.
    LogUserCmd "$SWAMP_USERNAME" mkdir -m 0755 -p .cache

    # setup sudo access for the user
    sudoersFile=/etc/sudoers
    LogNote "Appending to $sudoersFile to grant $SWAMP_USERNAME sudo access"
    RedirectAppendStdFds "$sudoersFile" '' LogCmd cat <<-EOF

	Defaults:$SWAMP_USERNAME    !requiretty
	$SWAMP_USERNAME ALL = (ALL) NOPASSWD: ALL
	EOF
    LogCmd visudo -c
}


# VerifyNetwork()
#   Wait for network to be up, and fail if it does not within allowed time
function VerifyNetwork()
{
    ## XXX the problem with waiting so long for the network to come up is
    ## that if ROOT_PAYLOAD needs the net, it is hosed.
    netup="netup"
    if CallFromInDir 1 ValidateExecIgnoreFail "$netup"; then
	if ! CallFromInDir 1 LogCmdIgnoreFail "$netup" "$NETWORK_WAIT_TIME"; then
	    if true; then
		ErrorShutdownWithMsg "NETWORK NOT UP" network no-ipv4-address
	    else
		LogError "NETWORK NOT UP, CONTINUING"
	    fi
	fi

	## hack until my dns tool can be used for this
	## mir-swamp has dns propogation issues through DNS
	LogNote "Sleeping $DNS_WAIT_TIME seconds for DNS connectivity"
	LogCmd sleep "$DNS_WAIT_TIME"
    else
	LogNote "Sleeping $SLEEP_TIME seconds for network connectivity"
	LogCmd sleep "$SLEEP_TIME"
    fi
}


# GetIpSrcAddrForDstAddr(<var> <dstAddr>)
#   set <var> to the IPv4 addr string used as the src address to route to <stdAddr>
function GetIpSrcAddrForDstAddr()
{
    CheckNumArguments $# 2 2

    LogNote "Determining source address to route to $2"
    local ipRouteOut
    ipRouteOut=$(LogCmd ip route get "$2")
    local r=$?
    if [ $r -ne 0 ]; then
	ErrorShutdown setup get-ip-addr "ip route get $2 failed with exit code $r:" "$ipRouteOut"
    fi
    if [[ "$ipRouteOut" =~ $ipAddrRe ]]; then
	local addr=${BASH_REMATCH[2]}
	LogNote "Source IP address $addr is used to route to $2"
	printf -v "$1" "%s" "$addr"
    elif [ $? -ne 2 ]; then 
	ErrorShutdown setup get-ip-addr "ip route get $2 did not contain src <IPv4_ADDR>:" "$ipRouteOut"
    else
	ErrorShutdown setup get-ip-addr "regular expression is invalid: $ipAddrRe"
    fi
}


# WriteIpAddrFile(<file> <dstAddr>)
#   if <file> and <dstAddr> are non-empty, write to <file> the source IP output
#   address used to route to <dstAddr>
function WriteIpAddrFile()
{
    CheckNumArguments $# 2 2

    if [ -n "$1" ] && [ -n "$2" ]; then
	local ipAddr
	GetIpSrcAddrForDstAddr ipAddr "$2"
	RedirectAppendStdFds "$1" "" LogCmd echo "$ipAddr"
	WriteSwampEvent 'WROTEIPADDR'
    fi
}


# WriteSwampEvent(<msg>)
#   write <msg> to the SWAMP_EVENT_FILE if it exists
function WriteSwampEvent()
{
    CheckNumArguments $# 1 1

    if [ -n "$swampEventFile" ]; then
	LogNote "Write SWAMP Event Log: $1"
	RedirectAppendStdFds "$swampEventFile" "" LogCmd echo "$1"
    fi
}


# PrintAndExit(<type>)
#   print message for <type> (help, version or long-version) message and exit
function PrintAndExit()
{
    case "$1" in
	help)
	    echo "Usage: $0 [options]
    --help           -h  print help and exit
    --version        -v  print version and exit
    --long-version   -V  print version and release date, and exit
    --type               set container type (docker or vm)
    --container-type     set container type (docker or vm)"
	    ;;
	version)	echo "$runShVersion"				;;
	long-version)	echo "$runShVersion ($runShReleaseDate)"	;;
	*)		echo "In $FUNCNAME: Error unknown type ($1)"	::
    esac

    exit 0
}


# SetContainerType(<type>)
#   set the environment variables appropriately for the type, the in and out
#   directories are set to ./in and ./out respectively.
function SetContainerType()
{
    CheckNumArguments $# 1 1

    containerType=$1
    AbsPath VMINPUTDIR '' "in"
    AbsPath VMOUTPUTDIR '' "out"
    VMUSERADD='/usr/sbin/useradd'
    VMGROUPADD='/usr/sbin/groupadd'

    case "$containerType" in
	docker)
	    VMSHUTDOWN='exit 0'
	    NO_SHUTDOWN_CMD='WaitForever'
	    DELAY_SHUTDOWN_CMD='ps a --no-headers -o ppid,pid,user,tname,state,command | egrep "^ *0 " ; exit "${PIPESTATUS[0]}"'
	    ;;
	vm)
	    VMSHUTDOWN='/sbin/shutdown -h now'
	    NO_SHUTDOWN_CMD='exit'
	    ;;
	*)
	    LogMsg "Unknown container type ($1)"
	    NoShutdownExit 1
	    ;;
    esac
}


# ProcessOptions(<arg>...)
#   process the options passed and respond accordingly
function ProcessOptions()
{
    while [ $# -gt 0 ]; do
	case "$1" in
	    --)				shift; break;;
	    --help | -h)		PrintAndExit help;			   shift;;
	    --version | -v)		PrintAndExit version;			   shift;;
	    --long-version | -V)	PrintAndExit long-version;		   shift;;
	    --type=*)			SetContainerType "${1#--type=}";	   shift;;
	    --container-type=*)		SetContainerType "${1#--container-type=}"; shift;;
	    --type | --container-type)	SetContainerType "$2";			   shift 2;;
	    *)				break;;
	esac
    done

    if [ $# -gt 0 ]; then
	LogMsg "$0: invalid option or arguments, found:" "$@"
	NoShutdownExit 1
    fi
}


###########################################################


trap 'LogSignalHandler SIGQUIT NoShutdownExit' SIGQUIT
trap 'LogSignalHandler SIGTERM ErrorShutdown setup signal "Signal received"' SIGTERM

Initialize
ProcessOptions "$@"

if [ -z "$NO_SHUTDOWN_CMD" ]; then
    export NO_SHUTDOWN_CMD=exit
fi

# if run.out exists, just exit
AbsPath runOutFile "$VMOUTPUTDIR" "run.out"
if [ -f "$runOutFile" ]; then
    # restart of VM, just exit to allow for interactive debugging
    LogMsg "Found existing run.out at $runOutFile, stopping"
    NoShutdownExit
fi

AbsPathIfPath outputFilesConf "$VMOUTPUTDIR" "$OUTPUT_FILES_CONF"
AbsPathIfPath statusOut "$VMOUTPUTDIR" "$STATUS_OUT"

# check  that $VMOUTPUTDIR is set and is a directory
ValidateVarsAreDirs env VMOUTPUTDIR

# open log file
SetLogFile "$runOutFile"
LogNote "begin $0 version $runShVersion ($runShReleaseDate)" $'\n'
BashQuote quotedCmdLine "$0" "$@"

# log info about the host
LogInitialInfo

# set variables in conf file
CallFromInDir 1 ReadConfFileAndValidateVars "$runParamsFile" "$runParamsVars" "$runParamsVarPrefixes"
CapturePaths earlyCaptureArchive "$CAPTURE_METHOD" "$earlyCaptureArchive" $EARLY_CAPTURE_FILES

# export variables needed by frameworks and log values
export "${vmVars[@]}"
LogVariableValues "${vmVars[@]}"
LogVariableValues delayShutdownAlwaysWaitFile delayShutdownStopWaitFile

AddOutputFilesEntry "$outputFilesConf" runOut "$runOutFile"
WriteSwampEvent 'RUNSHSTART'

# run any background monitoring scripts as root 
LogBgJobsFromVars BG SCRIPT LogBgScript
LogBgJobsFromVars BG PAYLOAD CallFromInDir 1 LogBgCmd

# log the SWAMP environment variables to env.sh
if [ -n "$envSh" ]; then
    AddOutputFilesEntry "$outputFilesConf" envSh "$envSh"
    LogNote "Creating environment file:  $envSh"
    RedirectStdFds "$envSh"
	for i in "${vmVars[@]}"; do
	    printf "export %q=%q\n" "$i" "${!i}"
	done
    EndRedirectStdFds
fi

# create configure the user account if NO_CREATE_USER is empty
if [ -z "$NO_CREATE_USER" ]; then
    CreateUser
fi

# change the owner and group on the input and output dirs
LogCmd chown -R "$SWAMP_USERNAME.$SWAMP_GROUPNAME" "$VMINPUTDIR" "$VMOUTPUTDIR"

# shutdown if any of the earlier commands failed
ShutdownIfErrors

# create the /opt/swamp symlink and dir if they do not exist
if [ ! -d "$OPT_DIR" ]; then
    LogNote "Warning:  $OPT_DIR missing, creating"
    LogCmd mkdir -m 0755 "$OPT_DIR"
fi
AbsPath swampBaseDir "$OPT_DIR" "swamp-base"
if ! [ -L "$swampBaseDir" ] || ! [ "$(readlink "$swampBaseDir")" = "$userHomeDir" ]; then
    LogCmd ln -s "$userHomeDir" "$swampBaseDir"
else
    LogNote "Symlink $swampBaseDir exists and points to $userHomeDir"
fi

# untar the USER_CONF if set
if [ -n "$userConf" ]; then
    LogUserCmd "$SWAMP_USERNAME" tar xzf "$userConf"
fi

# log information about the user
LogUserInfo "$SWAMP_USERNAME"

# run any background monitoring scripts as the user
LogBgJobsFromVars BG_USER SCRIPT LogBgUserScript "$SWAMP_USERNAME"
LogBgJobsFromVars BG_USER PAYLOAD CallFromInDir 2 LogBgUserCmd "$SWAMP_USERNAME"

# run root script or payload if set
if [ -n "$ROOT_SCRIPT" ]; then
    LogScript "$ROOT_SCRIPT"
elif [ -n "$ROOT_PAYLOAD" ]; then
    CallFromInDir 1 LogCmd $ROOT_PAYLOAD
fi

# if NORUNPAYLOAD is set, exit here for debugging as if NOSHUTDOWN were also set
if [ -n "$NORUNPAYLOAD" ]; then
    NOSHUTDOWN=1
    Shutdown 0 "NORUNPAYLOAD set, exiting without running payload"
fi

# check network
(( ++networkState ))
if [ -z "$NO_VERIFY_NETWORK" ]; then
    # verify the network is up and OK, or fail and shutdown
    VerifyNetwork
    (( ++networkState ))
fi
WriteIpAddrFile "$ipAddrFile" "$IP_ADDR_ROUTE_TO"
LogNetworkInfo

# run user pre script or payload
if [ -n "$USER_PRE_SCRIPT" ]; then
    LogUserScript "$SWAMP_USERNAME" "$USER_PRE_SCRIPT"
elif [ -n "$USER_PRE_PAYLOAD" ]; then
    CallFromInDir 2 LogUserCmd "$SWAMP_USERNAME" $USER_PRE_PAYLOAD "$VMINPUTDIR" "$VMOUTPUTDIR" "$envSh"
fi

# run the user script, payload, or build_assess_driver
if [ -n "$USER_SCRIPT" ]; then
    LogUserScriptIgnoreFail "$SWAMP_USERNAME" "$USER_SCRIPT"
elif [ -n "$USER_PAYLOAD" ]; then
    CallFromInDir 2 LogUserCmdIgnoreFail "$SWAMP_USERNAME" $USER_PAYLOAD "$VMINPUTDIR" "$VMOUTPUTDIR" "$envSh"
elif [ -z "$NO_USER_FRAMEWORK_PAYLOAD" ]; then
    WriteSwampEvent 'BEGINASSESSMENT'
    AddOutputFilesEntry "$outputFilesConf" buildAssessOut "$buildAssessOut"
    AddOutputFilesEntry "$outputFilesConf" statusOut "$statusOut"
    RedirectStdFds "$buildAssessOut" "$buildAssessOut" CallFromInDir 2 LogUserCmdIgnoreFail "$SWAMP_USERNAME"  \
	    "$buildAssessDriver" --in-dir "$VMINPUTDIR" --out-dir "$VMOUTPUTDIR" --base-dir "$swampBaseDir"
fi

# run user post script or payload
if [ -n "$USER_POST_SCRIPT" ]; then
    LogUserScriptIgnoreFail "$SWAMP_USERNAME" "$USER_POST_SCRIPT"
elif [ -n "$USER_POST_PAYLOAD" ]; then
    CallFromInDir 2 LogUserCmdIgnoreFail "$SWAMP_USERNAME" $USER_POST_PAYLOAD "$VMINPUTDIR" "$VMOUTPUTDIR" "$envSh"
fi

# run root script or payload if set
if [ -n "$ROOT_POST_SCRIPT" ]; then
    LogScriptIgnoreFail "$ROOT_POST_SCRIPT"
elif [ -n "$ROOT_POST_PAYLOAD" ]; then
    CallFromInDir 1 LogCmdIgnoreFail $ROOT_POST_PAYLOAD
fi

# shutdown/exit
Shutdown 0

exit 1
