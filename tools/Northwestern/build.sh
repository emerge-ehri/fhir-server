#!/bin/bash

dotnet publish "./src/Microsoft.Health.Fhir.R4.Web/Microsoft.Health.Fhir.R4.Web.csproj" -c Release -o "./target" -r osx-x64

rm ./target/*
cp src/Microsoft.Health.Fhir.R4.Web/target/* ./target
cp config/appsettings.json target/

cd target/ 
dotnet Microsoft.Health.Fhir.R4.Web.dll

cd ..
