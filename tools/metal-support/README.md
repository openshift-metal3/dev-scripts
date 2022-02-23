The metal-support utility offers a number of different useful commands to help
the activity of the metal-support role within the metal team.

Run `metal-support -h` to show a complete help of the currently supported commands

# Commands

## metal-wall (mw)

Starts a local web server (by default on port 8081) to monitor all the blocking/informing/upgrade metal release jobs. 
The page gets automatically refreshed every minute, and the status of each job is shown grouped by version.
In case of failure an additional icon is shown next to the job name to indicate the cause of the issue:

* *Equinix*. An error was detected when creating a new Equinix instance
* *Dev-scritps*. A problem was found when installing the cluster
* *Test*. One (or more) of the e2e tests failed

## check

Looks for intermittent e2e test failures on the specified version
