.PHONY: default all auth qlserver kafka nfs windows_vm knative tweet uhc
default: all auth sqlserver kafka nfs windows_vm knative tweet uhc

all: default

auth:
	./00_auth.sh

sqlserver:
	./01_sqlserver.sh

kafka:
	./02_kafka.sh

nfs:
	./03_nfs.sh

windows_vm:
	./04_windows_vm.sh

knative:
	./05_knative.sh

tweet:
	./06_tweet.sh

uhc:
	./07_uhc.sh
