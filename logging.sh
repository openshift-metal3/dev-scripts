# Log output automatically
DEFAULT_LOGDIR="$(dirname $0)/logs"
LOGDIR=${LOGDIR:-$DEFAULT_LOGDIR}
if [[ -z "${LOGPREFIX:-}" ]]; then
    LOGFILE="$LOGDIR/$(basename $0 .sh)-$(date +%F-%H%M%S).log"
else
    LOGFILE="$LOGDIR/${LOGPREFIX}$(basename $0 .sh)-$(date +%F-%H%M%S).log"
fi
if [ ! -d "$(dirname $LOGFILE)" ]; then
    mkdir -p "$(dirname $LOGFILE)"
fi
echo "Logging to $LOGFILE"
# Set fd 1 and 2 to write to the log file
exec 1> >( tee "${LOGFILE}" ) 2>&1
