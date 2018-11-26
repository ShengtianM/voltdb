#!/bin/bash
# Script that contains functions that may be useful for a variety of different
# test frameworks in the directories below. Many of these were originally
# developed in connection with the SQL-grammar-generator tests, but they may
# be equally useful for other test frameworks, such as SqlCoverage, the (GEB)
# VMC tests, etc. Some examples: building VoltDB, starting a VoltDB server,
# and shutting down the VoltDB server at the end.

# Remember the directory where we started, and find the <voltdb>, <voltdb>/bin/,
# and <voltdb>/tests/ directories; and set variables accordingly
function test-tools-find-directories() {
    if [[ "$TT_DEBUG" -ge "2" ]]; then
        echo -e "\n$0 performing: test-tools-find-directories"
    fi
    TT_HOME_DIR=$(pwd)
    if [[ -e $TT_HOME_DIR/tests/test-tools.sh ]]; then
        # It looks like we're running from a <voltdb> directory
        VOLTDB_COM_DIR=$TT_HOME_DIR
    elif [[ -e $TT_HOME_DIR/voltdb/tests/test-tools.sh ]]; then
        # It looks like we're running from just 'above' a <voltdb> directory
        VOLTDB_COM_DIR=$TT_HOME_DIR/voltdb
    elif [[ $TT_HOME_DIR == */tests ]] && [[ -e $TT_HOME_DIR/test-tools.sh ]]; then
        # It looks like we're running from a <voltdb>/tests/ directory
        VOLTDB_COM_DIR=$(cd $TT_HOME_DIR/..; pwd)
    elif [[ $TT_HOME_DIR == */tests/* ]] && [[ -e $TT_HOME_DIR/../test-tools.sh ]]; then
        # It looks like we're running from a <voltdb>/tests/FOO/ directory,
        # e.g., from <voltdb>/tests/sqlgrammar/ or <voltdb>/tests/sqlcoverage/
        VOLTDB_COM_DIR=$(cd $TT_HOME_DIR/../..; pwd)
    elif [[ $TT_HOME_DIR == */tests/*/* ]] && [[ -e $TT_HOME_DIR/../../test-tools.sh ]]; then
        # It looks like we're running from a <voltdb>/tests/FOO/BAR/ directory,
        # e.g., from <voltdb>/tests/geb/vmc/
        VOLTDB_COM_DIR=$(cd $TT_HOME_DIR/../../..; pwd)
    elif [[ $TT_HOME_DIR == */tests/*/*/* ]] && [[ -e $TT_HOME_DIR/../../../test-tools.sh ]]; then
        # It looks like we're running from a <voltdb>/tests/FOO/BAR/BAZ/ directory,
        # e.g., from <voltdb>/tests/geb/vmc/src/
        VOLTDB_COM_DIR=$(cd $TT_HOME_DIR/../../../..; pwd)
    elif [[ -n "$(which voltdb 2> /dev/null)" ]]; then
        # It looks like we're using VoltDB from the PATH
        VOLTDB_BIN_DIR=$(dirname "$(which voltdb)")
        if [[ $VOLTDB_BIN_DIR == */pro/obj/pro/voltdb-ent-*/bin ]]; then
            # It looks like we found a VoltDB 'pro' directory
            VOLTDB_PRO_DIR=$(cd $VOLTDB_BIN_DIR/../../../..; pwd)
            VOLTDB_COM_DIR=$(cd $VOLTDB_PRO_DIR/../voltdb; pwd)
        else
            # It looks like we found a VoltDB 'community' directory
            VOLTDB_COM_DIR=$(cd $VOLTDB_BIN_DIR/..; pwd)
        fi
    else
        echo "Unable to find VoltDB installation."
        echo "Please add VoltDB's bin directory to your PATH."
        exit -1
    fi
    VOLTDB_COM_BIN=$VOLTDB_COM_DIR/bin
    VOLTDB_TESTS=$VOLTDB_COM_DIR/tests
    # These directories may or may not exist, so ignore any errors
    VOLTDB_PRO_DIR=$(cd $VOLTDB_COM_DIR/../pro 2> /dev/null; pwd)
    VOLTDB_PRO_BIN=$(cd $VOLTDB_PRO_DIR/obj/pro/voltdb-ent-*/bin 2> /dev/null; pwd)
    # Use 'community', open-source VoltDB by default (not 'pro')
    if [[ -z "$VOLTDB_BIN_DIR" ]]; then
        VOLTDB_BIN_DIR=$VOLTDB_COM_BIN
    fi
}

# Find the directories and set variables, only if not set already
function test-tools-find-directories-if-needed() {
    if [[ -z "$TT_HOME_DIR" || -z "$VOLTDB_COM_DIR" || -z "$VOLTDB_COM_BIN" || -z "$VOLTDB_TESTS" ]]; then
        test-tools-find-directories
    fi
}

# Echo environment variables that are commonly used in Jenkins jobs
function tt-echo-build-args() {
    echo -e "\n${BASH_SOURCE[0]} performing: $FUNCNAME"
    echo "VOLTDB_REV: $VOLTDB_REV"
    echo "PRO_REV   : $PRO_REV"
    echo "BUILD_OPTS: $BUILD_OPTS"
    echo "BUILD_ARGS: $BUILD_ARGS"
    echo "SEED      : $SEED"
    echo "SETSEED   : $SETSEED"
    BUILD_ARGS_WERE_ECHOED="true"
}

# Echo environment variables that are commonly used in Jenkins jobs,
# only if not echoed already
function tt-echo-build-args-if-needed() {
    if [[ -z "$BUILD_ARGS_WERE_ECHOED" ]]; then
        tt-echo-build-args
    fi
}

# Set build arguments to be passed to a build of VoltDB (community or pro),
# based on simpler arguments passed to this function, such as 'debug', 'pool',
# 'memcheck', etc.
function tt-set-build-args() {
    tt-echo-build-args-if-needed
    echo -e "\n${BASH_SOURCE[0]} performing: $FUNCNAME $@"

    if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
        echo -e "\nWARNING: ${BASH_SOURCE[0]} function $FUNCNAME called without 'source' or '.':"
        echo -e "    will have no external effect!\n"
    fi

    if [[ -z "$1" || "$1" == tt-* || "$1" == test-tools* ]]; then
        echo -e "\nWARNING: ${BASH_SOURCE[0]} function $FUNCNAME called without an argument:"
        echo -e "    will have no effect!\n"
    fi

    while [[ -n "$1" ]]; do
        # Stop if we encounter other "test-tools" functions as args
        if [[ "$1" == tt-* || "$1" == test-tools* ]]; then
            break
        fi

        IFS=',' read -r -a build_options <<< "$1"
        for option in "${build_options[@]}"; do
            # Check for standard BUILD_ARGS abbreviations
            if [[ "$option" == "reset" || "$option" == "release" ]]; then
                BUILD_ARGS=
            elif [[ "$option" == "debug" ]]; then
                BUILD_ARGS="$BUILD_ARGS -Dbuild=debug"
            elif [[ "$option" == "pool" ]]; then
                BUILD_ARGS="$BUILD_ARGS -Dbuild=debug -DVOLT_POOL_CHECKING=true"
            elif [[ "$option" == "memcheck" ]]; then
                BUILD_ARGS="$BUILD_ARGS -Dbuild=memcheck"
            elif [[ "$option" == "memcheckrelease" || "$option" == "memcheck-release" || \
                    "$option" == "memcheck_release" ]]; then
                BUILD_ARGS="$BUILD_ARGS -Dbuild=memcheck_release"
            elif [[ "$option" == "jmemcheck" ]]; then
                BUILD_ARGS="$BUILD_ARGS -Djmemcheck=MEMCHECK_FULL"
            elif [[ "$option" == "nojmemcheck" ]]; then
                BUILD_ARGS="$BUILD_ARGS -Djmemcheck=NO_MEMCHECK"
            # User is allowed to specify their own -D... option(s)
            elif [[ "$option" == -D* ]]; then
                BUILD_ARGS="$BUILD_ARGS $option"
            else
                echo -e "\nERROR: Unrecognized arg / build option in ${BASH_SOURCE[0]} function $FUNCNAME:"
                echo -e "    $1 / $option"
                exit -4
            fi
        done
        shift
        SHIFT_BY=$((SHIFT_BY+1))
    done
    echo -e "\nBUILD_ARGS: $BUILD_ARGS"
}

# Sets the SETSEED variable, typically to be used by SqlCoverage, based on
# an argument passed to this function, or on the current value (if any) of
# the SEED variable
function tt-set-setseed() {
    tt-echo-build-args-if-needed
    echo -e "\n${BASH_SOURCE[0]} performing: $FUNCNAME $1"

    if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
        echo -e "\nWARNING: ${BASH_SOURCE[0]} function $FUNCNAME called without 'source' or '.':"
        echo -e "    will have no external effect!\n"
    fi

    SETSEED=
    if [[ -n "$1" && "$1" != tt-* && "$1" != test-tools* ]]; then
        SETSEED="-Dsql_coverage_seed=$1"
        SHIFT_BY=$((SHIFT_BY+1))
    elif [[ -n "$SEED" ]]; then
        SETSEED="-Dsql_coverage_seed=$SEED"
    fi
    echo -e "SETSEED: $SETSEED"
}

# Call the 'killstragglers' script, passing it the standard PostgreSQL port number
function tt-killstragglers() {
    test-tools-find-directories-if-needed
    echo -e "\n${BASH_SOURCE[0]} performing: $FUNCNAME"

    cd $VOLTDB_COM_DIR
    ant killstragglers -Dport=5432
    cd -
}

# Call the start_postgresql.sh script
function tt-start-postgresql() {
    test-tools-find-directories-if-needed
    echo -e "\n${BASH_SOURCE[0]} performing: $FUNCNAME"

    # SqlCoverage will only work well with PostgreSQL, if PostgreSQL is
    # started by user 'test'
    if [[ `whoami` != "test" ]]; then
        echo -e "\nWARNING: ${BASH_SOURCE[0]} function $FUNCNAME called as user '`whoami`', not 'test':"
        echo -e "    SqlCoverage will not work well!!!\n"
    fi

    if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
        echo -e "\nWARNING: ${BASH_SOURCE[0]} function $FUNCNAME called without 'source' or '.':"
        echo -e "    stop-postgresql will be unable to access the environment variables set here!\n"
    fi

    # Start the PostgreSQL server, in a new temp directory ('source' is used so that
    # the environment variables defined here can be used by stop_postgresql.sh later)
    source $VOLTDB_TESTS/sqlcoverage/start_postgresql.sh

    # TODO: does this have any effect, inside this script, or only in Jenkins??
    # Prevent exit before stopping the PostgreSQL server & deleting the temp directory,
    # if the sqlCoverage tests fail
    set +e
}

# Equivalent, shorter function name
function tt-start-postgres() {
    tt-start-postgresql $@
}

# Call the stop_postgresql.sh script
function tt-stop-postgresql() {
    test-tools-find-directories-if-needed
    echo -e "\n${BASH_SOURCE[0]} performing: $FUNCNAME"

    # Stop the PostgreSQL server & delete the temp directory
    $VOLTDB_TESTS/sqlcoverage/stop_postgresql.sh
}

# Equivalent, shorter function name
function tt-stop-postgres() {
    tt-stop-postgresql $@
}

# TODO: this could be implemented in the future, to run the SqlCoverage test
# program, with various arguments
function tt-sqlcoverage() {
    echo -e "\n${BASH_SOURCE[0]} performing: [test-tools.]run-sqlcoverage $@"

    echo -e "\nWARNING: ${BASH_SOURCE[0]} function $FUNCNAME not implemented yet!!!\n"
}

# Build VoltDB: 'community', open-source version
# Optionally, you may specify one or more build arguments ($@)
function test-tools-build() {
    test-tools-find-directories-if-needed
    echo -e "\n$0 performing: [test-tools-]build $@"

    cd $VOLTDB_COM_DIR
    ant clean dist "$@"
    code_tt_build=$?
    cd -

    if [[ "$code_tt_build" -ne "0" ]]; then
        echo -e "\ncode_tt_build: $code_tt_build"
    fi
}

# Build VoltDB: 'pro' version
# Optionally, you may specify one or more build arguments ($@)
function test-tools-build-pro() {
    test-tools-find-directories-if-needed
    echo -e "\n$0 performing: [test-tools-]build-pro $@"

    cd $VOLTDB_PRO_DIR
    ant -f mmt.xml dist.pro "$@"
    code_tt_build=$?
    cd -
    VOLTDB_PRO_BIN=$(cd $VOLTDB_PRO_DIR/obj/pro/voltdb-ent-*/bin; pwd)
    cp $VOLTDB_PRO_BIN/../voltdb/license.xml $VOLTDB_COM_DIR/voltdb/

    if [[ "$code_tt_build" -ne "0" ]]; then
        echo -e "\ncode_tt_build(pro): $code_tt_build"
    fi
}

# Build VoltDB ('community'), only if not built already
# Optionally, you may specify one or more build arguments ($@)
function test-tools-build-if-needed() {
    test-tools-find-directories-if-needed
    if [[ "$TT_DEBUG" -ge "2" ]]; then
        echo -e "\n$0 performing: [test-tools-]build-if-needed $@"
    fi
    VOLTDB_COM_JAR=$(ls $VOLTDB_COM_DIR/voltdb/voltdb-*.jar)
    if [[ ! -e $VOLTDB_COM_JAR ]]; then
        test-tools-build "$@"
    fi
}

# Build VoltDB 'pro' version, only if not built already
# Optionally, you may specify one or more build arguments ($@)
function test-tools-build-pro-if-needed() {
    test-tools-find-directories-if-needed
    if [[ "$TT_DEBUG" -ge "2" ]]; then
        echo -e "\n$0 performing: [test-tools-]build-pro-if-needed $@"
    fi
    VOLTDB_PRO_TAR=$(ls $VOLTDB_PRO_DIR/obj/pro/voltdb-ent-*.tar.gz)
    if [[ ! -e $VOLTDB_PRO_TAR ]]; then
        test-tools-build-pro "$@"
    fi
}

# Set CLASSPATH, PATH, and python, as needed
function test-tools-init() {
    test-tools-find-directories-if-needed
    test-tools-build-if-needed "$@"
    if [[ "$TT_DEBUG" -gt "0" ]]; then
        echo -e "\n$0 performing: test-tools-init $@"
    fi

    # Set CLASSPATH to include the VoltDB Jar file
    VOLTDB_COM_JAR=$(ls $VOLTDB_COM_DIR/voltdb/voltdb-*.jar)
    code_voltdb_jar=$?
    if [[ -z "$CLASSPATH" ]]; then
        CLASSPATH=$VOLTDB_COM_JAR
    else
        CLASSPATH=$VOLTDB_COM_JAR:$CLASSPATH
    fi

    # Set PATH to include the voltdb/bin directory, containing the voltdb and sqlcmd executables
    if [[ -z "$(which voltdb)" || -z "$(which sqlcmd)" ]]; then
        PATH=$VOLTDB_BIN_DIR:$PATH
    fi

    # Set python to use version 2.7
    alias python=python2.7
    code_python=$?

    code_tt_init=$(($code_voltdb_jar|$code_python))
    if [[ "$code_tt_init" -ne "0" ]]; then
        echo -e "\ncode_voltdb_jar: $code_voltdb_jar"
        echo -e "code_python    : $code_python"
        echo -e "code_tt_init   : $code_tt_init"
    fi
}

# Set CLASSPATH, PATH, and python, only if not set already
function test-tools-init-if-needed() {
    if [[ -z "${code_tt_init}" ]]; then
        test-tools-init
    fi
}

# Print the values of various variables, mainly those set in the
# test-tools-find-directories() and test-tools-init() functions
function test-tools-debug() {
    test-tools-init-if-needed
    if [[ "$TT_DEBUG" -gt "0" ]]; then
        echo -e "\n$0 performing: test-tools-debug"
        echo "TT_DEBUG       :" $TT_DEBUG
    fi

    echo "TT_HOME_DIR    :" $TT_HOME_DIR
    echo "VOLTDB_COM_DIR :" $VOLTDB_COM_DIR
    echo "VOLTDB_COM_BIN :" $VOLTDB_COM_BIN
    echo "VOLTDB_COM_JAR :" $VOLTDB_COM_JAR
    echo "VOLTDB_PRO_DIR :" $VOLTDB_PRO_DIR
    echo "VOLTDB_PRO_BIN :" $VOLTDB_PRO_BIN
    echo "VOLTDB_PRO_TAR :" $VOLTDB_PRO_TAR
    echo "VOLTDB_BIN_DIR :" $VOLTDB_BIN_DIR
    echo "DEPLOYMENT_FILE:" $DEPLOYMENT_FILE
    echo "DEPLOYMENT_ARG :" $DEPLOYMENT_ARG
    echo "CLASSPATH      :" $CLASSPATH
    echo "PATH           :" $PATH
    echo "which sqlcmd   :" `which sqlcmd`
    echo "which voltdb   :" `which voltdb`
    echo "voltdb version :" `$VOLTDB_BIN_DIR/voltdb --version`
    echo "which python   :" `which python`
    echo "python version :"
    python --version
}

# Wait for a VoltDB server to finish initializing; should not be called directly
function test-tools-wait-for-server-to-start() {
    test-tools-find-directories-if-needed
    if [[ "$TT_DEBUG" -ge "2" ]]; then
        echo -e "\n$0 performing: test-tools-wait-for-server-to-start"
    fi

    SQLCMD_COMMAND="$VOLTDB_COM_BIN/sqlcmd --query='select C1 from NONEXISTENT_TABLE' 2>&1"
    if [[ "$TT_DEBUG" -ge "3" ]]; then
        echo -e "DEBUG: sqlcmd command:\n$SQLCMD_COMMAND"
    fi

    MAX_SECONDS=15
    for (( i=1; i<=${MAX_SECONDS}; i++ )); do
        SQLCMD_RESPONSE=$(eval $SQLCMD_COMMAND)
        if [[ "$TT_DEBUG" -ge "4" ]]; then
            echo -e "\nDEBUG: sqlcmd response $i:\n$SQLCMD_RESPONSE"
        fi

        # If the VoltDB server is now running, we're done
        if [[ "$SQLCMD_RESPONSE" == *"object not found: NONEXISTENT_TABLE"* ]]; then
            echo "VoltDB server is running..."
            break

        # If the VoltDB server has not yet completed initialization, keep waiting
        elif [[ "$SQLCMD_RESPONSE" == *"Unable to connect"* || "$SQLCMD_RESPONSE" == *"Connection refused"* ]]; then
            sleep 1

        # Otherwise, print an error message and exit
        else
            echo -e "\nVoltDB server unable to start: sqlcmd response had error(s):\n$SQLCMD_RESPONSE\n"
            exit -2
        fi
    done

    if [[ "$i" -gt "$MAX_SECONDS" ]]; then
        echo -e "\n\nERROR: VoltDB server unable to start after waiting $MAX_SECONDS seconds"
        echo -e "Here is the end of the VoltDB console output (./volt_console.out):"
        tail -10 volt_console.out
        echo -e "\nHere is the end of the VoltDB log (./voltdbroot/log/volt.log):"
        tail -10 voltdbroot/log/volt.log
        exit -3
    fi
}

# Start a VoltDB server: 'community' or 'pro', depending on the value of the
# VOLTDB_BIN_DIR variable; optionally, you may set the DEPLOYMENT_FILE or
# DEPLOYMENT_ARG variable (the latter should start with '-C ' or '--config=')
# before calling this function; should not be called directly
function test-tools-server-community-or-pro() {
    test-tools-find-directories-if-needed
    if [[ "$TT_DEBUG" -ge "2" ]]; then
        echo -e "\n$0 performing: test-tools-server-community-or-pro"
    fi

    if [[ -z "$DEPLOYMENT_ARG" && -n "$DEPLOYMENT_FILE" ]]; then
        DEPLOYMENT_ARG="--config=$DEPLOYMENT_FILE"
    fi
    INIT_COMMAND="${VOLTDB_BIN_DIR}/voltdb init --force ${DEPLOYMENT_ARG}"
    echo -e "Running:\n${INIT_COMMAND}"
    ${INIT_COMMAND}
    code_voltdb_init=$?

    START_COMMAND="${VOLTDB_BIN_DIR}/voltdb start"
    echo -e "Running:\n${START_COMMAND} > volt_console.out 2>&1 &"
    ${START_COMMAND} > volt_console.out 2>&1 &
    code_voltdb_start=$?
    test-tools-wait-for-server-to-start

    # Prevent exit before stopping the VoltDB server, if your tests fail
    set +e

    code_tt_server=$(($code_voltdb_init|$code_voltdb_start))
    if [[ "$code_tt_server" -ne "0" ]]; then
        echo -e "\ncode_voltdb_init : $code_voltdb_init"
        echo -e "code_voltdb_start: $code_voltdb_start"
        echo -e "code_tt_server   : $code_tt_server"
    fi
}

# Start the VoltDB server: 'community', open-source version
function test-tools-server() {
    test-tools-find-directories-if-needed
    test-tools-build-if-needed
    echo -e "\n$0 performing: [test-tools-]server"

    VOLTDB_BIN_DIR=${VOLTDB_COM_BIN}
    test-tools-server-community-or-pro
}

# Start the VoltDB server: 'pro' version
function test-tools-server-pro() {
    test-tools-find-directories-if-needed
    test-tools-build-pro-if-needed
    echo -e "\n$0 performing: [test-tools-]server-pro"

    VOLTDB_BIN_DIR=${VOLTDB_PRO_BIN}
    test-tools-server-community-or-pro
}

# Start the VoltDB server ('community'), only if not already running
function test-tools-server-if-needed() {
    if jps -l | grep -q org.voltdb.VoltDB; then
        echo -e "\nNot (re-)starting a VoltDB server, because 'jps -l' now includes a VoltDB process."
        #echo -e "    DEBUG: jps -l:" $(jps -l | grep org.voltdb.VoltDB)
    else
        test-tools-server
    fi
}

# Start the VoltDB 'pro' server, only if not already running
function test-tools-server-pro-if-needed() {
    if jps -l | grep -q org.voltdb.VoltDB; then
        echo -e "\nNot (re-)starting a VoltDB server, because 'jps -l' now includes a VoltDB process."
        #echo -e "    DEBUG: jps -l:" $(jps -l | grep org.voltdb.VoltDB)
    else
        test-tools-server-pro
    fi
}

# Stop the VoltDB server, and kill any straggler processes
function test-tools-shutdown() {
    test-tools-find-directories-if-needed
    if [[ "$TT_DEBUG" -gt "0" ]]; then
        echo -e "\n$0 performing: test-tools-shutdown"
    fi

    # Stop the VoltDB server (& kill any stragglers)
    $VOLTDB_BIN_DIR/voltadmin shutdown
    code_tt_shutdown=$?
    cd $VOLTDB_COM_DIR
    ant killstragglers
    cd -

    if [[ "$code_tt_shutdown" -ne "0" ]]; then
        echo -e "\ncode_tt_shutdown: $code_tt_shutdown"
    fi
}

# Builds the latest (local) version of VoltDB (the 'community', open-source
# version), and starts a ('community') VoltDB server, after setting and echoing
# various environment variables
function test-tools-all() {
    echo -e "\n$0 performing: test-tools-all"

    test-tools-build
    test-tools-init
    test-tools-debug
    test-tools-server
}

# Builds the latest (local) version of VoltDB (the 'pro' version), and starts a
# ('pro') VoltDB server, after setting and echoing various environment variables
function test-tools-all-pro() {
    echo -e "\n$0 performing: test-tools-all-pro"

    test-tools-build-pro
    test-tools-init
    test-tools-debug
    test-tools-server-pro
}

# Print a simple help message, describing the options for this script
function tt-help() {
    echo -e "\nUsage: ./test-tools.sh test-tools-{build[-pro]|init|debug|server[-pro]|all[-pro]|shutdown}"
    echo -e "Or   : ./test-tools.sh tt-{echo-build-args|set-build-args|set-setseed|killstragglers|"
    echo -e "                           start-postgres[ql]|stop-postgres[ql]|help}"
    echo -e "This script is largely intended to provide useful functions that may be called"
    echo -e "    by a variety of other test scripts, e.g., <voltdb>/tests/sqlgrammar/run.sh,"
    echo -e "    but it may also be called directly on the command line."
    echo -e "Options:"
    echo -e "    test-tools-build      : builds VoltDB ('community', open-source version)"
    echo -e "    test-tools-build-pro  : builds VoltDB ('pro' version)"
    echo -e "    test-tools-init       : sets useful variables such as CLASSPATH and PATH"
    echo -e "    test-tools-debug      : prints the values of variables such as VOLTDB_COM_DIR and PATH"
    echo -e "    test-tools-server     : starts a VoltDB server ('community', open-source version)"
    echo -e "    test-tools-server-pro : starts a VoltDB server ('pro' version)"
    echo -e "    test-tools-all        : runs (almost) all of the above, except the '-pro' options"
    echo -e "    test-tools-all-pro    : runs (almost) all of the above, using the '-pro' options"
    echo -e "    test-tools-shutdown   : stops a VoltDB server that is currently running"
    echo -e "    tt-echo-build-args    : echoes build args commonly used in Jenkins"
    echo -e "    tt-set-build-args     : sets the BUILD_ARGS environment variable"
    echo -e "    tt-set-setseed        : sets the SETSEED environment variable"
    echo -e "    tt-killstragglers     : calls the 'killstragglers' script, passing"
    echo -e "                                it the standard PostgreSQL port number"
    echo -e "    tt-start-postgres[ql] : calls the start_postgresql.sh script"
    echo -e "    tt-stop-postgres[ql]  : calls the stop_postgresql.sh script"
    #echo -e "    tt-sqlcoverage        : NOT YET IMPLEMENTED!"
    echo -e "    tt-help               : prints this message"
    echo -e "Some options (test-tools-build[-pro], test-tools-init, test-tools-server[-pro],"
    echo -e "    tt-echo-build-args) may have '-if-needed' appended, e.g.,"
    echo -e "    'test-tools-server-if-needed' will start a VoltDB server only if"
    echo -e "    one is not already running."
    echo -e "Some options (tt-set-build-args, tt-set-build-args) may be passed argument(s)"
    echo -e "    that determine what the relevant environment variable will be set to."
    echo -e "Multiple options may be specified; but options usually call other options that are prerequisites.\n"
    PRINT_ERROR_CODE=0
}

# Old name for tt-help
function test-tools-help() {
    tt-help
}

# If run on the command line with no options specified, run tt-help
if [[ $# -eq 0 && $0 == *test-tools.sh ]]; then
    tt-help
fi

# Run options passed on the command line, if any; with arguments, if any
while [[ -n "$1" ]]; do
    SHIFT_BY=1  # Can be increased, by a function that handles multiple args
    $@
    shift $SHIFT_BY
done
