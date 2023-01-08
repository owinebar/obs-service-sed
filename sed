#!/bin/bash
## Simple OBS service to run a sed script

# define some functions first
on_error() {
    echo "Error in script" >&2
    cat ${script_file} >&2
    exit 1
}

cleanup() {
    rm -f ${script_file}
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
    echo "$check"
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
    tmp="$(realpath --relative-base="$(realpath "${base}")" "$full")"
    case "$tmp" in
	/*)
	    echo "Illegal ${desc} file name: $full" >&2
	    exit 1
	    ;;
    esac
}

check_file_exists() {
    local fname="$1"
    if [ \! -e "$fname" ] || [ \! -f "$fname" ]; then
	echo "File '$fname' does not exist or is not a regular file" >&2
	exit 1
    fi
}

check_system_posint() {
    local tmp
    local given="$1"
    local name="$2"
    tmp="$(check_positive_integer "${given}" "" 1)" || {
	echo "$name limit must be positive integer, given: '$given'" >&2
	exit 1
    }
    echo "$tmp"
}
check_system_int() {
    local tmp
    local given="$1"
    local name="$2"
    local min="$3"
    local max="$4"
    if ! tmp="$(check_integer "${given}" "$min" "$max" 1)"; then
	echo "System $name limit must be integer, given: '$given'" >&2
	exit 1
    fi
    if [ "$tmp" -ne "$given" ]; then
	echo "System $name limit must be between '$min' and '$max', given: '$given'" >&2
	exit 1
    fi
    echo "$tmp"
}

limited_sed() {
    local ul_flags="$1"
    shift
    if [ "$ul_flags" ]; then
	## some flags specified
	( ulimit $ul_flags >/dev/null 2>&1
	  sed "$@"
	)
    else
	sed "$@"
    fi
}

# these values may be set by the system configuration file
missing_input="fail"
system_cpu_limit=""
system_memory_limit=""
system_stack_limit=""
system_file_size_limit=""

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
script_file=$(mktemp)
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

while [ $# -gt 0 ]; do
    case $1 in
	--script)
	    check_path "$(pwd)" "$2" "script"
	    cat "${2}" >>$script_file
	    printf "\n" >>$script_file	    
	    ;;
	--expression)
	    printf "%s" "$2" >>$script_file
	    printf "\n" >>$script_file	    
	    ;;
	--file)
	    check_path "$(pwd)" "$2" "input"
	    infile="${2}"
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
	--prioritylimit)
	    priority_limit="$(check_integer "$2" "${system_priority_limit}" 19)"
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
check_path "$outdir" "$outpath" "output"
tmp="$(dirname "${outpath}")"
mkdir -p "$tmp"
if [ \! -d "$tmp" ]; then
    echo "Destination directory for $outfile in $outdir does not exist and could not be created" >&2
    exit 1
fi

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

if [ -e "${infile}" ]; then
    limited_sed "$ulimit_flags" \
		--sandbox \
		$syntax_flag \
		$noprint_flag \
		$null_flag \
		$wrap_flag \
		-f "${script_file}" \
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
	    # treat as file with a single empty line, since script may handle that case (sed does not match $ if there is no newline in the input)
	    echo |
		limited_sed "$ulimit_flags" \
			    --sandbox \
			    $syntax_flag \
			    $noprint_flag \
			    $null_flag \
			    $wrap_flag \
			    -f "${script_file}" \
			    >"${outpath}"
	    ;;
	*)
	    echo "Urecognized missing input option: $missing_input" >&2
	    exit 1
	    ;;
    esac
fi
