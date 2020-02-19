# fhir-server Commands

Start up

```
docker run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=tMk%e9?FsE7=tsSz' -p 1433:1433 -d mcr.microsoft.com/mssql/server:2017-CU8-ubuntu

cd ~/Development/emerge-ehri/fhir-server

dotnet publish "./src/Microsoft.Health.Fhir.R4.Web/Microsoft.Health.Fhir.R4.Web.csproj" -c Release -o "./target" -r osx-x64
 
rm ./target/*
cp src/Microsoft.Health.Fhir.R4.Web/target/* ./target
cp config/nu.appsettings.json ./target/appsettings.json

cd target
dotnet Microsoft.Health.Fhir.R4.Web.dll

## IN A NEW COMMAND WINDOW
cd ~/Development/emerge-ehri/fhir-server
./tools/Northwestern/hapi-fhir-4.1.0-cli/hapi-fhir-cli upload-definitions -t http://localhost:5000/ -v r4

```



Shut down

* Kill the dotnet process running

```
docker ps  # shows running containers, get ID
docker stop <ID>  # ID is like b1e226adc4e0
docker ps  # Confirm it shut down
```