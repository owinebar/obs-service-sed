#!/bin/bash
## Simple OBS service to run a sed script
full_service="$(realpath "$0")"
service_name="$(basename "$0")"
#service_dir="$(dirname "$full_service")"
service_dir=/usr/lib/obs/service
if [ "$service_name" = "bash" ]; then
    echo "Service name not recognized" >&2
    exit 1
fi
DEBUG=${DEBUG:-0}
#echo "DEBUG=$DEBUG"
# define some functions first
on_error() {
    local last_command="$BASH_COMMAND"
    local last_line="${BASH_LINENO[0]}"
    local last_src="${BASH_SOURCE[0]}"
    echo "Error in service $service_name" >&2
    if (( $DEBUG )); then
	printf "%s:%s\t%s\n" "$last_src" "$last_line" "$last_command" >&2
	local k=0
	x="$(caller $k)"
	while [ "$x" ]; do
	    echo "$x";
	    (( ++k ))
	    x="$(caller $k)"
	done
    fi
    exit 1
}

cleanup() {
    rm -Rf ${scriptd}
}

trap cleanup EXIT
trap on_error ERR

get_min() {
    local val="$1"
    if [ -n "$2" ]; then
	if [ -z "$val" ]; then
	    val="$2"
	elif (( ${val} > "$2" )); then
	    val="$2"
	fi
    fi
}
get_max() {
    local val="$1"
    if [ -n "$2" ]; then
	if [ -z "$val" ]; then
	    val="$2"
	elif (( ${val} < "$2" )); then
	    val="$2"
	fi
    fi
}
check_legal() {
    local val="$1"
    local check="$2"
    local signal_err="$3"
    if [ -z "$check" ] || [ "${val}" != "$check" ]; then
	if [ "${signal_err}" ]; then
	    case "${signal_err}" in
		0 | [fF]*)
		    :
		    ;;
		*)
		    exit 1
		    ;;
	    esac
	fi
    fi
}

int_re='/^[-+]?[0-9]+/ { h ; s/^([-+]?[0-9]+).*$/\1/ ; p ; q } ; q'
pos_int_re='/^[0-9]+/ { h ; s/^([0-9]+).*$/\1/ ; p ; q } ; q'

check_integer() {
    local val="$1"
    local min="$2"
    local max="$3"
    shift 3
    local signal_err="$@"
    [ "$val" ] || return;
    local check="$(printf "%s" "$val" |
    	  	   sed -nzEe "$int_re" |
		   tr -d '\000')"    
    val="$(check_legal "$val" "$check" $signal_err)" || exit #?
    val="$(get_max "$val" "$min")"
    val="$(get_min "$val" "$max")"
    echo "${val}"
}

check_positive_integer() {
    local val="$1"
    local max="$2"
    shift 2
    local signal_err="$@"
    [ "$val" ] || return;
    local check="$(printf "%s" "$val" |
    	  	   sed -nzEe "$pos_int_re" |
		   tr -d '\000')"
    val="$(check_legal "$val" "$check" $signal_err)" || exit #?
    val="$(get_min "$val" "$max")"
    return ${val}
    
}

check_path() {
    local tmp
    local base="$1"
    local full="$2"
    local desc="$3"
    tmp="$(realpath -s --relative-base="$(realpath "${base}")" "$full")"
    case "$tmp" in
	/*)
	    echo "Illegal ${desc} file name: $full" >&2
	    exit 1
	    ;;
    esac
    echo "$tmp"
}

check_file_exists() {
    local fname="$1"
    if [ \! -e "$fname" ] || [ \! -f "$fname" ]; then
	echo "File '$fname' does not exist or is not a regular file" >&2
	return 1
    fi
}

check_system_posint() {
    local tmp
    local given="$1"
    local name="$2"
    if [ "${given}" ]; then
	tmp="$(check_positive_integer "${given}" "" 1)" || {
	    echo "$name limit must be positive integer, given: '$given'" >&2
	    exit 1
	}
    fi
    echo "$tmp"
}
check_system_int() {
    local tmp
    local given="$1"
    local name="$2"
    local min="$3"
    local max="$4"
    if [ "${given}" ]; then
	if ! tmp="$(check_integer "${given}" "$min" "$max" 1)"; then
	    echo "System $name limit must be integer, given: '$given'" >&2
	    exit 1
	fi
	if [ "$tmp" -ne "$given" ]; then
	    echo "System $name limit must be between '$min' and '$max', given: '$given'" >&2
	    exit 1
	fi
    fi
    echo "$tmp"
}

limited_sed() {
    local ul_flags="$1"
    shift
    trap on_error ERR
    if [ "$ul_flags" ]; then
	## some flags specified
	( ulimit $ul_flags >/dev/null 2>&1
	  sed "$@"
	)
    else
	sed "$@"
    fi
}

limited_sed_pipeline() {
    local ul_flags="$1" sed_flags="$2" mode="$3"
    shift 3
    trap on_error ERR
    local sed_pipe
    if [ "$mode" = "script" ]; then
	local i=0
	local sfile=$(mktemp -p $scriptd)
	while (( $# > 0 )); do
	    cat "$1" >>$sfile
	    printf "\n" >>$sfile
	    shift
	done
	sed_pipe="sed $sed_flags -f $sfile"
    else
	local sed="sed $sed_flags -f "
	sed_pipe="$(IFS="|"; tmp="${*/#/$sed}"; echo "${tmp//|/ | }")"
    fi
    if [ "$ul_flags" ]; then
	## some flags specified
	( ulimit $ul_flags >/dev/null 2>&1
	  shopt -s pipefail
	  eval "$sed_pipe"
	  shopt -u pipefail
	)
    else
	eval "$sed_pipe"
    fi
}

# these values may be set by the system configuration file
missing_input="fail"
system_cpu_limit=""
system_memory_limit=""
system_stack_limit=""
system_file_size_limit=""
system_script_size_limit=""

system_config="/etc/obs/service/$(basename "$0")"
if [ -e "$system_config" ]; then
    . "$system_config"
fi
# Make sure the system defaults are legal
system_cpu_limit="$(check_system_posint "${system_cpu_limit}" "CPU")" || exit 1
system_memory_limit="$(check_system_posint "${system_memory_limit}" "memory")" || exit 1
system_stack_limit="$(check_system_posint "${system_stack_limit}" "stack")" || exit 1
system_file_size_limit="$(check_system_posint "${system_file_size_limit}" "file size")" ||
    exit 1
script=""
scriptd=$(mktemp -d)
script_file=$(mktemp -p $scriptd)
infile=""
outfile=""
outdir=""
syntax_flag="-E"
noprint_flag=""
null_flag=""
wrap_flag=""
missing_input="fail"
cpu_limit=""
memory_limit=""
stack_limit=""
file_size_limit=""
priority_limit=""
script_size_limit=""
mode="script"
declare -a exprs expr_tps
#tmp
while [ $# -gt 0 ]; do
    case $1 in
	--script)
	    tmp="$(check_path "$(pwd)" "$2" "script")"
	    #exprs[${#exprs[@]}]=$(mktemp -p $scriptd)
	    expr_tps[${#exprs[@]}]="file"
	    exprs[${#exprs[@]}]="$tmp"
	    ;;
	--expression)
	    expr_tps[${#exprs[@]}]="expr"
	    exprs[${#exprs[@]}]=$(mktemp -p $scriptd)
	    printf "%s\n" "$2" >${exprs[-1]}
	    ;;
	--file)
	    tmp="$(check_path "$(pwd)" "$2" "input")"
	    infile="$tmp"
	    ;;
	--out)
	    outfile="${2}"
	    ;;
	--default-print)
	    case "$2" in
		"off")
		    noprint_flag="-n"
		    ;;
		*)
		    noprint_flag=""
		    ;;
	    esac
	    ;;
	--missing-input)
	    missing_input="$2"
	    ;;
	--null-data)
	    case "$2" in
		"" | "on")
		    null_flag="-z"
		    ;;
		*)
		    null_flag=""
		    ;;
	    esac
	    ;;
	--mode)
	    case "$2" in
		script)
		    mode="script"
		    ;;
		pipe)
		    mode="pipe"
		    ;;
		*)
		    echo "Unrecognized mode $2" >&2
		    exit 1
		    ;;
	    esac
	    ;;
	--line-wrap)
	    wrap_count="$(check_positive_integer "$2" "" 1)" || {
		echo "Bad line-wrap argument '$2'" >&2
		exit 1
	    }
	    wrap_flag="-l${wrap_count}"
	    ;;
	--syntax)
	    case "$2" in
		"traditional")
		    syntax_flag=""
		    ;;
		*)
		    syntax_flag="-E"
		    ;;
	    esac
	    ;;
	--cpu-limit)
	    cpu_limit="$(check_positive_integer "$2" "${system_memory_limit}")" 
	    ;;
	--memory-limit)
	    memory_limit="$(check_positive_integer "$2" "${system_memory_limit}")" 
	    ;;
	--stack-limit)
	    stack_limit="$(check_positive_integer "$2" "${system_stack_limit}")" 
	    ;;
	--file-size-limit)
	    file_size_limit="$(check_positive_integer "$2" "${system_file_size_limit}")"
	    ;;
	--script-size-limit)
	    script_size_limit="$(check_positive_integer "$2" "${system_script_size_limit}")"
	    ;;
	--outdir)
	    outdir="$2"
	    ;;
	*)
	    echo "Unrecognized option(s) '$@'" >&2
	    exit 1
	    ;;
    esac
    shift 2
done

if [ "$missing_input" = "fail" ]; then
    check_file_exists "$infile"
fi
if [ -z "$outdir" ]; then
    echo "Output directory name must be specified!" >&2
    exit 1
fi
if [ -z "$outfile" ]; then
   outfile="$infile"
fi
outpath="${outdir}/${outfile}"
echo "sed output to $outpath"
outpath="${outdir}/$(check_path "$outdir" "$outpath" "output")"
echo "sed output (checked) to $outpath"
tmp="$(dirname "${outpath}")"
mkdir -p "$tmp"
if [ \! -d "$tmp" ]; then
    echo "Destination directory for $outfile in $outdir does not exist and could not be created" >&2
    exit 1
fi
if [ -z "$script_size_limit" ]; then
    lim=-1
else
    lim=$(( ${script_size_limit} * 1024 ))
fi

check_regular_file() {
    local fn="$1"
    local tp="$(stat -L -c %F "$1")"
    if [ "$tp" != "regular file" ]; then
	echo "${2:+$2 } $1 is not a regular file or symbolic link to one, aborting" >&2
	return 1
    fi
}
N=${#exprs[@]}
for (( i=0; i < N ; i++ )); do
    x="${exprs[$i]}"
    xtp="${expr_tps[$i]}"
    check_regular_file "$x" "Script"
    sz="$(stat -c %s "$x")"
    if (( $lim > 0 && $sz > $lim )); then
	case "$xtp" in
	    file)
		echo "Script file $x exceeds limit of $script_size_limit kB" >&2
		;;
	    expr)
		echo "Script expression $i  exceeds limit of $script_size_limit kB" >&2
		;;
	    *)
		echo "Should never get here" >&2
		;;
	esac
	exit 1
    fi
    if [ "$outpath" = "$x" ]; then
	echo "Output file $outfile is specified as script expression $i - aborting" >&2
	exit 1
    fi
done
ulimit_flags=""
if [ "$cpu_limit" ]; then
    ulimit_flags="$ulimit_flags -t $cpu_limit"
fi
if [ "$memory_limit" ]; then
    ulimit_flags="$ulimit_flags -m $memory_limit"
fi
if [ "$stack_limit" ]; then
    ulimit_flags="$ulimit_flags -s $stack_limit"
fi
if [ "$file_size_limit" ]; then
    ulimit_flags="$ulimit_flags -f $file_size_limit"
fi

flags="--sandbox $syntax_flag $noprint_flag $null_flag $wrap_flag"
if [ -e "${infile}" ]; then
    echo "sed output to ${outpath}"
    limited_sed_pipeline "$ulimit_flags" \
			 "$flags" \
			 "$mode" \
			 "${exprs[@]}" \
			 <"${infile}" \
			 >"${outpath}"
else
    outfile_exists="false"
    if [ -e "$outpath" ]; then
	outfile_exists="true"
    fi
    case "$missing_input:$outfile_exists" in
	fail*)
	    echo "Should have failed already!" >&2
	    exit 1
	    ;;
	ignore* | empty-safe:true)
	    :   # Do nothing
	    ;;
	empty-safe:false | empty:* )
	    # treat as file with a single empty line,
	    # since script may handle that case
	    # (sed does not match $ if there is no newline in the input)
	    echo |
		limited_sed_pipeline "$ulimit_flags" \
				     "$flags" \
				     "$mode" \
				     "${exprs[@]}" \
				     >"${outpath}"
	    ;;
	*)
	    echo "Urecognized missing input option: $missing_input" >&2
	    exit 1
	    ;;
    esac
fi
