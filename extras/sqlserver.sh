PASSWORD="P@ssword"
oc new-project dotnet
oc new-app registry.centos.org/microsoft/mssql-server-linux:latest -e 'ACCEPT_EULA=Y' -e "SA_PASSWORD=$PASSWORD" -e 'MSSQL_PID=Express' -l app=mssql
