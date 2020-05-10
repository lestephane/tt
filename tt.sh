#!/usr/bin/env bash
#
# punch clock tool based on hledger
#
# Environment:
#   - TIME_FILE:
#       Time entries file path. Date format placeholders are supported
#       (example: $HOME/time/%Y-%m.timeclock)
#
#   - TIME_BUDGETS_FILE:
#       Time budgets file path (example: $HOME/time/budgets.journal).
#       When specified, balance reports include budget performance.
#
#     example budget file content:
#     ----------------------------
#     ~ weekly  personal budget
#         wrk   40h
#         fun   14h
#     -----------------------------
#
#   - TIME_ALIASES_FILE:
#       Optional time account aliases file path (example: $HOME/time/aliases.journal)
#       When specified, time accounts get rewritten following the rules in this file.
#       Due to the way hledger works, rules are processed from bottom to top.
#       So, the modifications of later rules are seen by earlier rules.
#
#     example aliases file content:
#     ----------------------------
#     alias /^netflix/=fun:\0
#     alias /^work(.*)/=wrk:\1
#     ----------------------------
#

set -euo pipefail

TIME_FILE=${TIME_FILE:-${HOME}/.hours.timeclock}
TIME_FILE_FORMATTED=$(date +"${TIME_FILE}")

function usage {
	scriptName="$(basename ${0})"
	cat <<EOF
Usage: ${scriptName} [COMMAND] [ARGS]
Track time

i|in                "Time in" to begin a task. Args: [optional date] [task project] [optional task description] 
o|out               "Time out" to end a task. Args: [optional date]
s|stat|t|tail       Show the end of the timeclock file. Args: [optional n lines]
b|bal               Show daily balances.
wb|wbal             Show weekly balances.
wr|wreg             Show weekly register.
mb|mbal             Show monthly balances.
mr|mreg             Show monthly register.
n|sw|next|switch    End (time out of) the current task, and begin the next.
                    task. New task name is the next arg.
e|edit              Edit the timeclock file with \${EDITOR}.
t|tail              Show the last 10 lines of the ledger

EOF

}

if [[ $# == 0 ]]; then
	usage
	exit 0
fi

function time_in {
	local time=$(date '+%Y-%m-%d %H:%M:%S')
	local activity="${@}"
	if [[ "${1}" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
		time="$(date '+%Y-%m-%d') ${1}:00"
		activity="${@:2}"
	fi
	echo "Begin ${activity} at ${time}"
	echo "i ${time} ${activity}" >> "${TIME_FILE_FORMATTED}"
}

function time_out {
	local time=$(date '+%Y-%m-%d %H:%M:%S')
	if [[ "${1:-}" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
		time="$(date '+%Y-%m-%d') ${1}:00"
	fi
	echo "End at $time"
	echo "o $time" >> "${TIME_FILE_FORMATTED}"
}

function tail_file {
	local n=10
	if [[ $# -gt 0 ]]; then
		n=$1
	fi
	tail -n $n "${TIME_FILE_FORMATTED}"
}

function extra_journals {
  if [ -f "${TIME_BUDGETS_FILE}" ]; then
    cat "${TIME_BUDGETS_FILE}"
  fi
  if [ -f "${TIME_ALIASES_FILE}" ]; then
    cat "${TIME_ALIASES_FILE}"
  fi
}

function time_file_pattern() {
  echo "${TIME_FILE}" | sed 's/%[a-zA-Z]/*/g'
}

function time_file_include() {
cat <<EOF
!include $(time_file_pattern)
EOF
}

case $1 in
	i|in)
		shift
		time_in $*
		;;
	o|out)
		shift
		time_out $*
		;;
	s|stat|t|tail)
		shift
		tail_file $*
		;;
	b|bal)
		hledger -f "${TIME_FILE_FORMATTED}" bal "$@"
		;;
	wb|wbal)
		shift
		hledger -f - -p "$(date -d "6 days ago" +%Y-%m-%d) to $(date -d "tomorrow" +%Y-%m-%d)" bal --budget not:"ignore|workflix|sleeping" "$@" <<-EOF | grep -vE ' 0 +$'
		$(extra_journals)
		$(time_file_include)
		EOF
		;;
	wr|wreg)
		shift
		if head -n1 $(time_file_pattern) | grep -B1 -E "^o"; then
			echo "time file does not start with a i entry"
			false
		fi
		if tail -n1 $(time_file_pattern) | grep -B1 -E "^i"; then
			echo "time file does not end with a o entry"
			false
		fi
		hledger -f - -p "$(date -d "6 days ago" +%Y-%m-%d) to $(date -d "tomorrow" +%Y-%m-%d)" reg "$@" <<-EOF
		$(time_file_include)
		EOF
		;;
	mb|mbal)
		shift
		hledger -f - -p "$(date -d "last month" +%Y-%m-%d) to $(date -d "tomorrow" +%Y-%m-%d)" bal --budget not:"ignore|workflix|sleeping" "$@" <<-EOF | grep -vE ' 0 +$'
		$(extra_journals)
		$(time_file_include)
		EOF
		;;
	mr|mreg)
		shift
		hledger -f - -p "$(date -d "last month" +%Y-%m-%d) to $(date -d "tomorrow" +%Y-%m-%d)" reg "$@" <<-EOF
		$(time_file_include)
		EOF
		;;
	d|daily)
		hledger -f - -p "daily this week" bal --tree <<-EOF
		$(extra_journals)
		$(time_file_include)
		EOF
		;;
	w|weekly)
		hledger -f - -p "weekly this month" bal --tree <<-EOF
		$(extra_journals)
		$(time_file_include)
		EOF
		;;
	q|quarterly)
		hledger -f - -p "quarterly this year" bal --tree <<-EOF
		$(extra_journals)
		$(time_file_include)
		EOF
		;;
	n|sw|next|switch)
		shift
		time_out $* && time_in $*
		;;
	e|edit)
		$EDITOR "${TIME_FILE_FORMATTED}"
		;;
	*)
		echo "Unknown command ${1}"
		usage
		exit 1
		;;
esac

