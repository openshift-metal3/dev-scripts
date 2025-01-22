# Metal support tool

This is a TUI program that collects Metal CI information and displays an
overview of the health of the CI pipeline.

## Running

``` sh
make
./metal-support --help
A tool for monitoring/troubleshooting metal-ipi OpenShift CI releases

Usage:
  metal-support [flags]

Flags:
  -h, --help                       help for metal-support
      --release-repo-path string    (default "release")
      --versions string            OpenShift release versions to be analyzed (comma separated) (default "4.19,4.18,4.17,4.16,4.15,4.14,4.13,4.12")
```

In order to provide an up-to-date list of jobs and to avoid hardcoding values, this program reads job configuration from a git checkout of the [openshift/release](https://github.com/openshift/release) repo.  Before starting, make sure you have a local copy available.

Data will be stored at `~/.cache/metal-wall.json`.
