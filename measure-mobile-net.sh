#!/bin/bash
# measure mobile network performance
# by thonixx

# config parameters
providers=("Salt" "Swisscom" "Sunrise")
networks=("GPRS" "2G" "3G" "4G")
environments=("train/car" "outdoor" "indoor")
pingcount=10
speedtmout=25
resolvetmout=5
resolvetries=3
speed_host="speedtest.init7.net"
speed_host_uri="/1GB.dd"
resultfile="./measure-mobile-net.log"
table_header="| Provider | Date | Location | Environment | Tech | Signal | Average ping | Average speed |"
date="$(export LC_ALL=C; date)"

# trap for removing temp file
tmpfile="$(mktemp)"
tmpDLfile="$(mktemp)"
trap 'rm -f "$tmpfile" "$tmpDLfile"; exit 1' EXIT INT HUP SIGHUP SIGINT SIGTERM

# linux compatibilty
GETOPT="getopt"
TIMEOUT="timeout"
SED="sed"
STAT="stat"

# mac compatibilty
if [ "$(uname)" == "Darwin" ]
then
    GETOPT="/usr/local/opt/gnu-getopt/bin/getopt"
    TIMEOUT="gtimeout"
    SED="gsed"
    STAT="gstat"
fi

# following function borrowed from stackexchange
# thanks to http://stackoverflow.com/a/24289918
toBytes() {
 echo $1 | echo $((`$SED 's/.*/\L\0/;s/t/Xg/;s/g/Xm/;s/m/Xk/;s/k/X/;s/b//;s/X/ *1024/g'`))
}

# function for printing the usage/help
usage ()
{
echo "Usage:
        ${0##*/} [-p provider -e environment]

Description:
        Measure the performance of your mobile network connection and log it.
        Test doesn't have mandatory arguments but you can skip some wizard-like questions with arguments

Options:
        Optional stuff:
        ****
        -p/--provider Provider          Define the provider you use (i.e. ${providers[@]})
        -e/--environment Environment    Define the environment the test will be taken in (i.e ${environments[@]})

        I need help:
        ****
        -h/--help               this help

Example:
        ${0##*/} -p \"Salt\" -e \"Train/Car\"
            Test will be taken with Salt in a train or a car (or something which moves)

        ${0##*/} -p \"Swisscom\"
            Test will be taken with Swisscom
"
}

# read parameters
PARAM=$($GETOPT -o hp:e: --long help,provider:,environment: -- "$@")

# show usage if parameters fail
test "$?" -ne 0 && usage && exit 1

# ok I'm honest.. This part is copied from an existing script of a friend
# crawl through the parameters
eval set -- "$PARAM"
while true ; do
        case "$1" in
                -p|--provider) prov_override="${2}" ; shift 2 ;;
                -e|--environment) env_override="${2}" ; shift 2 ;;
                -h|--help) usage ; exit 0 ;;
                --) shift ; break ;;
                *) echo -e "Some weird error..\nI'm sorry.\nSomething with parameters is going wrong." ; exit 1 ;;
        esac
done

# fill in log file if it doesn't exist and prompt the usage
# we assume that a user is new if there is no log file
if [ ! -f "$resultfile" ]
then
    # file doesn't exist, so fill it with the header
    echo "$table_header" > $resultfile

    # print usage
    usage
    echo

    # print out a message and assume the test is being run the first time
    echo
    echo "++++"
    echo "It seems that this is your first time (or you removed the log file)."
    echo "See above the help output (can also be printed with '--help')."
    echo "++++"
    echo

    read -sp "Press enter to start the first test..." blah
    echo
fi

# prepare speed test host IP
# this is because DNS resolving sometimes can take a long time and counts to the download time
# so the result wouldn't be that accurate and therefore I kinda like "cache" the IP before doing the tests
echo -n "Prepare DNS for speed test host (for max $((resolvetmout * resolvetries)) secs)... "

speed_host_ip=""
iteration="1"
while test -z $speed_host_ip && test "$iteration" -lt $resolvetries
do
    speed_host_ip="$(host -W $resolvetmout -t A $speed_host | grep -o "has address.*" | head -n1 | awk '{print $3}')"
    iteration=$((iteration+1))
done
if [ -z "$speed_host_ip" ]
then
    # we assume that dns did not resolve
    echo -e "DNS failed or timed out.\nWill be resolved at the speed test but could falsify the result."
    # save the host name to the variable so wget resolves it later
    speed_host_ip="$speed_host"
    read -sp "Press enter to continue..." blah
    echo
else
    # dns did resolve, print success
    echo "OK"
fi
echo

# announce starting
echo "Start measuring on $date..."
echo

# some important notice
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo "Immediately look at the display and remember:"
echo " - Signal strength"
echo " - Technology (3G, 4G, ...)"
echo " - Location"
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo

# ask for technology (3G or whatever)
echo "Which network technology is being used for the test (Edge/E = 2G, H+ = 3G, LTE = 4G)?"
PS3="Choose wisely: "
select opt in "${networks[@]}" "something else"; do

    case "$REPLY" in

    * ) test ! -z "$opt" && echo "Network technology was: $opt" && tech_chosen="$opt" && break || echo "No valid option. Try again.";;

    esac

done
echo

# ask for signal strength
echo "How much is the signal strength at the moment? (out of 5)"
PS3="Choose wisely: "
select opt in "●○○○○" "●●○○○" "●●●○○" "●●●●○" "●●●●●" "○○○○○"; do

    case "$REPLY" in

    * ) test ! -z $opt && echo "Signal was: $opt" && sig_chosen="$opt" && break || echo "No valid option. Try again.";;

    esac

done
echo


# do the ping test
echo "Pinging $pingcount time$(test $pingcount -gt 0 && echo -n s)..."
# parse out average ping time
pingavg="$(ping -q -c$pingcount 8.8.8.8 | grep avg | awk -F/ '{print $5}' | awk -F\. '{print $1}')"
# if empty we assume a timeout or no connection (anymore)
test -z "$pingavg" && pingavg="(timed out)"
echo "Average ping time: $pingavg ms"
echo

# do the download test
echo "Downloading file for $speedtmout sec..."
# call with timeout command and fill progress to temporary file to calculate the results
$TIMEOUT --foreground $speedtmout wget -q -O $tmpDLfile http://$speed_host_ip/$speed_host_uri --header="Host: $speed_host" 2> /dev/null > /dev/null
# if file is empty we assume the speed test went into a timeout
# otherwise calculate results
test -s $tmpDLfile && {
        file_size="$($STAT --printf="%s" $tmpDLfile)"
        speed="$(echo "scale=2; $file_size / 1024 / $speedtmout * 8" | bc | awk -F\. '{print $1}')"
        echo "Speed is: $speed Kbps"
    } || {
        speed="(timed out)"
        echo "Speed test failed or timeout reached. Skipping."
    }
echo

# ask for provider
if [ -z "$prov_override" ]
then
    # the provider was not given as an argument so ask for it
    echo "Which provider was used for the test?"
    PS3='Choose whoever you want to "blame" for ;): '
    select opt in "${providers[@]}" "Else (type the name)"; do

        case "$REPLY" in

        $(( ${#providers[@]}+1 )) ) read -p "Type the provider: " prov_chosen && test ! -z "$prov_chosen" && echo "Provider was: $prov_chosen" && break || echo "No valid option. Try again.";;
        * ) test ! -z $opt && echo "Provider was: $opt" && prov_chosen="$opt" && break || echo "No valid option. Try again.";;

        esac

    done
else
    # the provider was given as an argument
    echo "Provider was: $prov_override"
    prov_chosen="$prov_override"
fi
echo

# ask for the environment the test was taken
# it could be important to know if you're in a train or not
if [ -z "$env_override" ]
then
    # the env was not given as an argument so ask for it
    echo "Which environment was the test taken in?"
    PS3="Choose wisely: "
    select opt in "${environments[@]}" "neither"; do

        case "$REPLY" in

        * ) test ! -z $opt && echo "Environment was: $opt" && env_chosen="$opt" && break || echo "No valid option. Try again.";;

        esac

    done
else
    # the env was given as an argument
    echo "Environment was: $env_override"
    env_chosen="$env_override"
fi
echo

# ask for the location
echo "Where was the test taken?"
while test -z "$location"
do
    read -p "Location: " location
done
echo

# result overview
result="| $prov_chosen | $date | $location | $env_chosen | $tech_chosen | $sig_chosen | $pingavg ms | $speed Kb/s |"
echo "++++++++++++++++++++++++"
echo "Overview of the results:"
echo "++++++++++++++++++++++++"
echo "$table_header"
echo "$result"
echo

# ask for confirmation
read -sp "Correct? If so, press Enter, otherwise Ctrl-C. " blah
echo

# write result to the file
echo "$result" >> $resultfile
