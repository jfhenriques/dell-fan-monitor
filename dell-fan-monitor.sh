#!/bin/bash


CONFIG_FILE=/etc/dell-fan-monitor.conf
DELLFAN=/opt/dellfan/dellfan
INIT_SPD=1
EXIT_SPD=3

# State variables
declare -A speeds
max_state=0
CUR_ST=-1
EXIT=0
last_speed_update=0
NUM_MASK="^[-]?[0-9]+$"
: "${SLEEP_TIME:=3}"
DEVICE_NAME=
TEMP_LABEL=
TEMPERATURE_FILE=

# Functions

perror() {
    echo "[ERROR] ${@}" >&2
}
pwarn() {
    echo "[WARN] ${@}"
}
pinfo() {
    echo "[INFO] ${@}"
}

read_temp() {
    cat "$TEMPERATURE_FILE"
}

get_cur_date_secs() {
    echo $(date +%s)
}

set_speed() {
    eval "$DELLFAN" "$1" >/dev/null && CUR_SPD="$1" && last_speed_update=$(get_cur_date_secs)
}

trap_cleanup() {
    [ "$EXIT" == "1" ] && return
    EXIT=1
    out="Setting default fan speed ${EXIT_SPD} and exiting..."
    if [[ "$1" -gt 0 ]]; then
        perror "Unexpected error occurred. $out"
    else
        pinfo "$out"
    fi
    [ -x "$DELLFAN" ] && set_speed "$EXIT_SPD"
    exit $1
}

find_temp_device() {
    local d_name
    local t_label

    if [ "x$DEVICE_NAME" == x ] && [ "x$TEMP_LABEL" == x ]; then
       DEVICE_NAME="coretemp"
       TEMP_LABEL="Package id 0"
    fi

    for d in /sys/class/hwmon/hwmon*; do

        [ -e "${d}/name" ] || continue
        d_name="$(cat "${d}/name")"

        [ "$d_name" == "$DEVICE_NAME" ] || continue

        for t in ${d}/temp*_label; do
            t_label="$(cat "$t")"

            [ "$t_label" == "$TEMP_LABEL" ] || continue
            TEMPERATURE_FILE=${t//_label/_input}

            break

        done

        break
    done
}

read_config() {
    total_speeds=0
    CUR_ST=-1
    speeds=()
    seen=""
    while IFS=' ' read -r sp low high; do

        # Ignore comments
        [[ $sp =~ ^#.*$ ]] && continue

        # Check sections
        if [ "x$sp" != "x" ] && [ "x$low" == "x" ] && [ "x$high" == "x" ]; then
          if [ "$sp" == "[GLOBAL]" ]; then
            seen=g
          elif [ "$sp" == "[SPEEDS]" ]; then
            seen=s
          else
            perror "Section '$sp' not recognized. Ignoring..."
          fi
          continue
        fi

        # Global configs
        if [ "$seen" == "g" ]; then
          if [ "x$sp" != "x" ] && [ "x$low" != "x" ]; then
            if [ "$sp" == "DEVICE" ]; then
                DEVICE_NAME=$(echo "$low $high"|xargs)

            elif [ "$sp" == "LABEL" ]; then
                TEMP_LABEL=$(echo "$low $high"|xargs)

            fi
          fi

        # Speeds
        elif [ "$seen" == "s" ]; then

          ( [ "x$sp" == "x" ] || [ "x$low" == "x" ] || [ "x$high" == "x" ] ) && continue
          if ! [[ $sp =~ $NUM_MASK ]] || ! [[ $low =~ $NUM_MASK ]] || ! [[ $high =~ $NUM_MASK ]]; then
              perror "Values '$sp', '$low' and '$high' must all be valid integers! Exiting..."
              exit 1
          fi
          low=$(($low * 1000))
          high=$(($high * 1000))

          #pinfo "[$total_speeds] Adding '$sp' '$low' '$high'"

          speeds["${total_speeds}.s"]="$sp"
          speeds["${total_speeds}.l"]="$low"
          speeds["${total_speeds}.h"]="$high"
          total_speeds=$((total_speeds+1))

          if [ "$INIT_SPD" == "$sp" ]; then
              CUR_ST=$total_speeds
#             pinfo "Found initial speed '$INIT_SPD' in state '$total_speeds'"
          fi
       fi
        
    done < <(cat "$CONFIG_FILE"; echo) # hack to had missing last new line

    if [ $total_speeds -eq 0 ]; then
        perror "Speeds $total_speeds not found"
        exit 1
    fi
    max_state=$((total_speeds-1))
    if [ "$CUR_ST" == "-1" ]; then
        CUR_ST=0
        INIT_SPD=${speeds["$CUR_ST.s"]}
        if [ "x$INIT_SPD" == "x" ]; then
            perror "Cannot find initial speeds"
            exit 1
        fi
        pwarn "Defaulting initial speed to '$INIT_SPD'"        
    fi
    
    find_temp_device
}

################################################################
# Startup checks
################################################################

if [[ $EUID -ne 0 ]]; then
  perror "Must be running as root"
  exit 1
fi

# trap any error and reset fan speed
trap 'trap_cleanup 1' ERR
trap 'trap_cleanup 0' EXIT

if [ ! -e "$CONFIG_FILE" ] ; then
  perror "Check if config '$CONFIG_FILE' file exists"
  exit 1
fi
if [ ! -x "$DELLFAN" ]; then
  perror "Check if '$DELLFAN' is executable"
  exit 1
fi

read_config

if [ "x$TEMPERATURE_FILE" == x ] || [ ! -e "$TEMPERATURE_FILE" ] ; then
  perror "Check if temperature file '$TEMPERATURE_FILE' exists"
  exit 1
fi

################################################################
# Start looping
################################################################

sleep 2
#pinfo "Setting initial speed of '$INIT_SPD'"
set_speed "$INIT_SPD"

while true; do
    sleep "$SLEEP_TIME"
    OLD_ST="$CUR_ST"

    c_low="${speeds["${CUR_ST}.l"]}"
    c_high="${speeds["${CUR_ST}.h"]}"

    temp="$(read_temp)"

    if [[ $temp -lt $c_low ]]; then
        CUR_ST=$((CUR_ST-1))

        if [[ $CUR_ST -lt 0 ]]; then
            CUR_ST=0
        fi

    elif [[ $temp -gt $c_high ]]; then
        CUR_ST=$((CUR_ST+1))

        if [[ $CUR_ST -gt $max_state ]]; then
            CUR_ST=$max_state
        fi
    fi
    cur_secs=$(get_cur_date_secs)
    elapsed=$((cur_secs-last_speed_update))
#    pinfo "$temp : $c_low : $c_high : $OLD_ST : $CUR_ST"
    if [ "$OLD_ST" != "$CUR_ST" ]; then
        new_speed="${speeds["${CUR_ST}.s"]}"
        #pinfo "Temperature is '$temp', changing speed to new state $CUR_ST [${new_speed}]'"
        if [ "$CUR_ST" == "$max_state" ]; then
            pwarn "Temperature is hitting max state!"
        fi
        set_speed "$new_speed"

    elif [[ $elapsed -ge 30 ]]; then
        set_speed "$new_speed"

    fi

done
