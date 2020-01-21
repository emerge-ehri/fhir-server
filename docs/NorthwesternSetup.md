# Northwestern Setup Notes

Instructions and notes specific to the Northwestern setup for the eMERGE genomics FHIR use case project.

## Objectives
We need to be able to run the FHIR server under the following constraints:

* Run on FSM-hosted infrastructure.  For this use case we are not able to seek approvals to run on Azure.
* Use Microsoft SQL Server, or some alternative local (non-Azure) database to store data


## Build Notes
* I had to change `global.json` with the specific version of .NET Core SDK that I had installed.  We can control this if we deploy using Docker, and should confirm that the version of the SDK is the latest, stable, with all security patches applied.
* From the root directory, I just had to run `dotnet build`.  This built fine without error or warning the first time I tried.
	* Very likely this passed because it didn't do anything.  Not seeing any DLL output that I can try to run.
* I then ran `dotnet test` just to see what the unit tests would do.
	* This failed wherever it was calling CosmoDB.  It looks like it's tied to that pretty heavily at least for the main tests.
* There is information for [running in Docker](../samples/docker).  This gives us the instructions needed to build this locally as well.
* 
```
 dotnet add "./tools/Microsoft.Health.Extensions.BuildTimeCodeGenerator/Microsoft.Health.Extensions.BuildTimeCodeGenerator.csproj" package Microsoft.CodeAnalysis.Analyzers  --version 2.9.4
 
 mkdir target
 
 dotnet publish "./src/Microsoft.Health.Fhir.R4.Web/Microsoft.Health.Fhir.R4.Web.csproj" -c Release -o "./target"
 
 rm ./target/*
 cp src/Microsoft.Health.Fhir.R4.Web/target/* ./target
 
 dotnet target/Microsoft.Health.Fhir.R4.Web.dll
```

The above block worked pretty well.  We have compiled code and a final DLL.  We get this error when running the last command however:

```
Error:
  An assembly specified in the application dependencies manifest (Microsoft.Health.Fhir.R4.Web.deps.json) was not found:
    package: 'Microsoft.Win32.Registry', version: '4.6.0'
    path: 'runtimes/unix/lib/netstandard2.0/Microsoft.Win32.Registry.dll'
```

Maybe we're targeting the wrong runtime?  This never occurred to me, but took a guess after [reading this post](https://github.com/dotnet/cli/issues/10025).  There [is a list of supported runtimes](https://docs.microsoft.com/en-us/dotnet/core/rid-catalog) available, which gives us what to use for macOS: `osx-x64`.

```
 dotnet add "./tools/Microsoft.Health.Extensions.BuildTimeCodeGenerator/Microsoft.Health.Extensions.BuildTimeCodeGenerator.csproj" package Microsoft.CodeAnalysis.Analyzers  --version 2.9.4
 
 mkdir target
 
 dotnet publish "./src/Microsoft.Health.Fhir.R4.Web/Microsoft.Health.Fhir.R4.Web.csproj" -c Release -o "./target" -r osx-x64
 
 rm ./target/*
 cp src/Microsoft.Health.Fhir.R4.Web/target/* ./target
 
 dotnet target/Microsoft.Health.Fhir.R4.Web.dll
```

Looks like the target runtime was part of the issue.  We're getting a little bit further along now.  It crashes, but it's a different error this time around:

```
Unhandled Exception: System.NullReferenceException: Object reference not set to an instance of an object.
   at Microsoft.Health.Fhir.Web.Startup.ConfigureServices(IServiceCollection services) in /Users/lvr491/Development/emerge-ehri/fhir-server/src/Microsoft.Health.Fhir.Shared.Web/Startup.cs:line 36
--- End of stack trace from previous location where exception was thrown ---
   at Microsoft.AspNetCore.Hosting.ConventionBasedStartup.ConfigureServices(IServiceCollection services)
   at Microsoft.AspNetCore.Hosting.Internal.WebHost.EnsureApplicationServices()
   at Microsoft.AspNetCore.Hosting.Internal.WebHost.Initialize()
   at Microsoft.AspNetCore.Hosting.WebHostBuilder.Build()
   at Microsoft.Health.Fhir.Web.Program.Main(String[] args) in /Users/lvr491/Development/emerge-ehri/fhir-server/src/Microsoft.Health.Fhir.Shared.Web/Program.cs:line 19
Abort trap: 6
```

Turns out we needed to modify the Program.cs to explicitly add the appsettings.json file, [like how this example did it](https://github.com/aspnet/AspNetCore.Docs/blob/master/aspnetcore/fundamentals/configuration/index/samples/3.x/ConfigurationSample/Program.cs).  That got things running, and we can try to reach [http://localhost:5000](http://localhost:5000) but it times out.  Not putting in the full stack trace, it's because we configured to use CosmoDb instead of SqlServer (so that's expected).  Next we'll modify the `appsettings.json` to have the correct setup.

That got us one step forward.  We didn't put in the SqlServer details, and now it's complaining (again, appropriately):

```
crit: Microsoft.Health.Fhir.SqlServer.Features.Schema.SchemaInitializer[0]
      There was no connection string supplied. Schema initialization can not be completed.

```

Since we're going to need a database, now's a good time to figure that out.  We're going to use the Microsoft [SQL Server Docker image](https://hub.docker.com/_/microsoft-mssql-server) to start with.  They have good instructions for getting this run.  We started by pulling it down:

```
docker pull mcr.microsoft.com/mssql/server
```

We'll run this just as the Developer edition.  Yes, we're putting our password in this document, but this is a throwaway instance so not a big concern:

```
docker run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=tMk%e9?FsE7=tsSz' -p 1433:1433 -d mcr.microsoft.com/mssql/server:2017-CU8-ubuntu

```

In retrospect, we probably didn't need to specify `2017-CU8-ubuntu` but that's what we'll run with for now.

Here's what we set up in the `appsettings.json` for our instance.  This connects to our local Docker image that's running:

```
    "SqlServer" : {
        "ConnectionString" : "Server=127.0.0.1,1433;User Id=SA;Password=tMk%e9?FsE7=tsSz"
    },
    "DataStore": "SqlServer",
```

The server now comes up without any warnings.  Navigating to [http://localhost:5000/](http://localhost:5000/) gives us an error though:

```
Application started. Press Ctrl+C to shut down.
fail: Microsoft.Health.Fhir.SqlServer.Features.Storage.SqlServerFhirModel[0]
      The current version of the database is not available. Unable in initialize SqlServerFhirModel.
fail: Microsoft.Health.Fhir.SqlServer.Features.Storage.SqlServerFhirModel[0]
      The current version of the database is not available. Unable in initialize SqlServerFhirModel.
fail: Microsoft.AspNetCore.Diagnostics.ExceptionHandlerMiddleware[1]
      An unhandled exception has occurred while executing the request.
System.IO.FileNotFoundException: View was not found.
File name: 'ViewJson.cshtml'
   at Microsoft.Health.Fhir.Api.Features.Formatters.HtmlOutputFormatter.WriteResponseBodyAsync(OutputFormatterWriteContext context, Encoding 
```

Digging in a little more, I forgot that there was [this Docker file](https://github.com/microsoft/fhir-server/blob/master/samples/docker/docker-compose.yaml), which gave some helpful hints.  I needed to tell the system to create the database:

```
    "SqlServer" : {
        "ConnectionString": "Server=127.0.0.1,1433;Initial Catalog=FHIR;Persist Security Info=False;User Id=SA;Password=tMk%e9?FsE7=tsSz",
        "AllowDatabaseCreation": "true",
        "Initialize": "true"
    },
```

Cool - so even though going to [http://localhost:5000/](http://localhost:5000/) gives us an error, we get a response when going through Postman.

At the end of the day, here's how we stop our SQL Server docker container:

```
docker ps  # shows running containers, get ID
docker stop <ID>  # ID is like b1e226adc4e0
docker ps  # Confirm it shut down
```

## Starting Back Up
When getting back to this, here's how to get stuff running again:

```
docker run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=tMk%e9?FsE7=tsSz' -p 1433:1433 -d mcr.microsoft.com/mssql/server:2017-CU8-ubuntu

cd ~/Development/emerge-ehri/fhir-server

dotnet publish "./src/Microsoft.Health.Fhir.R4.Web/Microsoft.Health.Fhir.R4.Web.csproj" -c Release -o "./target" -r osx-x64
 
rm ./target/*
cp src/Microsoft.Health.Fhir.R4.Web/target/* ./target
cp config/nu.appsettings.json ./target/appsettings.json

cd target
dotnet Microsoft.Health.Fhir.R4.Web.dll
```

Now when you call [http://localhost:5000/metadata](http://localhost:5000/metadata) from Postman it will return the conformance details.

## Configuration

Next up is following the configuration steps at [https://github.com/emerge-ehri/fhir-implementation/wiki/HAPI-FHIR-Server-Configuration](https://github.com/emerge-ehri/fhir-implementation/wiki/HAPI-FHIR-Server-Configuration).  We will download the `package.tgz` file, unzip it, and place the contents in this project under `config/genomics-reporting-package`.

It looks like we may be able to use the hapi-fhir-cli.  Let's get that built.  Or maybe it'll be easier to just [download it from the releases](https://github.com/jamesagnew/hapi-fhir/releases).  We'll try both and see what works first.

**UPDATE**: Looks like download wins.  It's located and can be run as:

```
./tools/Northwestern/hapi-fhir-4.1.0-cli/hapi-fhir-cli
```

**UPDATE 2**: Looks like there's a fix we need not yet in a release.  Back to the build option.

```
cd ~/Development/emerge-ehri/hapi-fhir/hapi-fhir-cli
git pull origin master
mvn clean package
cp ~/Development/emerge-ehri/hapi-fhir/hapi-fhir-cli/hapi-fhir-cli-app/target/hapi-fhir-cli.jar ~/Development/emerge-ehri/fhir-server/tools/Northwestern/hapi-fhir-4.1.0-cli/hapi-fhir-cli.jar
```

Commands we ran, with the [full output logged elsewhere](hapi-client-load.txt):

```
./tools/Northwestern/hapi-fhir-4.1.0-cli/hapi-fhir-cli upload-definitions -t http://localhost:5000/ -v r4
```

A few other preparatory things.  Looks like we need to download LOINC.  Guessing based off of the names in the commands in the wiki, I think we'll try the [LOINC and RELMA Complete Download File](https://loinc.org/file-access/download-id/8809/).  Note that we downloaded 2.67 because it was released after the HGSC team did this.

```
./tools/Northwestern/hapi-fhir-4.1.0-cli/hapi-fhir-cli upload-terminology -v r4 -t http://localhost:5000/ -u http://loinc.org -d ./config/Loinc_2.67.zip -d ./config/loincupload.properties
```

Note that we are missing the loinc.properties file that's referenced in the wiki.  And unfortunately this fails:

```
(base) lvr491@ ~/Development/emerge-ehri/fhir-server (northwestern) $ ./tools/Northwestern/hapi-fhir-4.1.0-cli/hapi-fhir-cli upload-terminology -v r4 -t http://localhost:5000/ -u http://loinc.org -d ./config/Loinc_2.67.zip
------------------------------------------------------------
🔥  HAPI FHIR 4.1.0 - Command Line Tool
------------------------------------------------------------
Process ID                      : 86632@FSMC02XC2SPJGH5
Max configured JVM memory (Xmx) : 8.0GB
Detected Java version           : 11.0.4
------------------------------------------------------------
2020-01-03 11:02:52.111 [main] INFO  c.u.f.c.UploadTerminologyCommand Adding ZIP file: ./config/Loinc_2.67.zip
2020-01-03 11:02:53.746 [main] INFO  c.u.f.c.UploadTerminologyCommand File size is greater than 10 MB - Going to use a local file reference instead of a direct HTTP transfer. Note that this will only work when executing this command on the same server as the FHIR server itself.
2020-01-03 11:02:54.492 [main] INFO  c.u.f.c.UploadTerminologyCommand Beginning upload - This may take a while...
2020-01-03 11:02:55.09 [main] ERROR c.u.f.c.UploadTerminologyCommand Received the following response:
{
  "resourceType": "OperationOutcome",
  "id": "3751eab3-fc15-4659-a94f-23a2790c5a93",
  "issue": [
    {
      "severity": "error",
      "code": "not-found",
      "diagnostics": "The requested route was not found."
    }
  ]
}
2020-01-03 11:02:55.11 [main] ERROR ca.uhn.fhir.cli.App Error during execution: 
ca.uhn.fhir.rest.server.exceptions.ResourceNotFoundException: HTTP 404 Not Found: The requested route was not found.
	at java.base/jdk.internal.reflect.NativeConstructorAccessorImpl.newInstance0(Native Method)
	at java.base/jdk.internal.reflect.NativeConstructorAccessorImpl.newInstance(NativeConstructorAccessorImpl.java:62)
	at java.base/jdk.internal.reflect.DelegatingConstructorAccessorImpl.newInstance(DelegatingConstructorAccessorImpl.java:45)
	at java.base/java.lang.reflect.Constructor.newInstance(Constructor.java:490)
	at ca.uhn.fhir.rest.server.exceptions.BaseServerResponseException.newInstance(BaseServerResponseException.java:302)
	at ca.uhn.fhir.rest.client.impl.BaseClient.invokeClient(BaseClient.java:351)
	at ca.uhn.fhir.rest.client.impl.GenericClient$BaseClientExecutable.invoke(GenericClient.java:434)
	at ca.uhn.fhir.rest.client.impl.GenericClient$OperationInternal.execute(GenericClient.java:1173)
	at ca.uhn.fhir.cli.UploadTerminologyCommand.invokeOperation(UploadTerminologyCommand.java:204)
	at ca.uhn.fhir.cli.UploadTerminologyCommand.run(UploadTerminologyCommand.java:113)
	at ca.uhn.fhir.cli.BaseApp.run(BaseApp.java:251)
	at ca.uhn.fhir.cli.App.main(App.java:43)
2020-01-03 11:02:55.11 [Thread-0] INFO  ca.uhn.fhir.cli.App HAPI FHIR is shutting down...

```

Maybe try skipping for now?  I guess we can see what happens.

Turns out skipping wasn't the right option, really.  We need this.  After some [discussion with the Baylor team](https://github.com/emerge-ehri/fhir-implementation/issues/37), we got a copy of the loincupload.properties file (which I updated for our version of LOINC):

```
# This is the version identifier for the AnswerList file
answerlist.version=2.67

# This is the version identifier for uploaded ConceptMap resources
conceptmap.version=2.67
```

This didn't work because the hapi-fhir-cli said it couldn't handle `properties` files.  This required (per an update note above) us to build the cli from source, and that error went away.  We're still getting that 404 error though.  Time to turn on debugging!  This is done in our appsettings.json down in the `Logging` section:

```
    "Logging": {
        "IncludeScopes": false,
        "LogLevel": {
            "Default": "Debug"
        },
```

So now we're seeing a little more information from the server on why a 404 error is coming back:

```
info: Microsoft.Health.Fhir.Api.Features.ApiNotifications.ApiNotificationMiddleware[0]
      ApiNotificationMiddleware executed in 00:00:01.5057269.
dbug: Microsoft.AspNetCore.Server.Kestrel[9]
      Connection id "0HLSK8KOMRKK5" completed keep alive response.
info: Microsoft.AspNetCore.Hosting.Internal.WebHost[2]
      Request finished in 1565.4897ms 200 application/fhir+xml; charset=utf-8
info: Microsoft.AspNetCore.Hosting.Internal.WebHost[1]
      Request starting HTTP/1.1 POST http://localhost:5000/CodeSystem/$upload-external-code-system application/fhir+json; charset=UTF-8 665
dbug: Microsoft.AspNetCore.StaticFiles.StaticFileMiddleware[1]
      POST requests are not supported
dbug: Microsoft.AspNetCore.Routing.Tree.TreeRouter[1]
      Request successfully matched the route with name '(null)' and template '{typeParameter:fhirResource}/{idParameter}'
dbug: Microsoft.AspNetCore.Mvc.Internal.ActionSelector[2]
      Action 'Microsoft.Health.Fhir.Api.Controllers.FhirController.Update (Microsoft.Health.Fhir.R4.Api)' with id '4ff61d52-ddc5-4d26-a6ac-89e5e7812f23' did not match the constraint 'Microsoft.AspNetCore.Mvc.Internal.HttpMethodActionConstraint'
dbug: Microsoft.AspNetCore.Mvc.Internal.ActionSelector[2]
      Action 'Microsoft.Health.Fhir.Api.Controllers.FhirController.Read (Microsoft.Health.Fhir.R4.Api)' with id 'c93d7dab-3329-43eb-b7da-03adfbb8b6eb' did not match the constraint 'Microsoft.AspNetCore.Mvc.Internal.HttpMethodActionConstraint'
dbug: Microsoft.AspNetCore.Mvc.Internal.ActionSelector[2]
      Action 'Microsoft.Health.Fhir.Api.Controllers.FhirController.Delete (Microsoft.Health.Fhir.R4.Api)' with id 'a58dcdd5-3404-4193-9148-14aa0e523a33' did not match the constraint 'Microsoft.AspNetCore.Mvc.Internal.HttpMethodActionConstraint'
dbug: Microsoft.AspNetCore.Mvc.Internal.ActionSelector[2]
      Action 'Microsoft.Health.Fhir.Api.Controllers.FhirController.Patch (Microsoft.Health.Fhir.R4.Api)' with id '94bdfb51-9970-4f5c-b93c-f70e818cf08e' did not match the constraint 'Microsoft.AspNetCore.Mvc.Internal.HttpMethodActionConstraint'
dbug: Microsoft.AspNetCore.Mvc.Internal.MvcAttributeRouteHandler[3]
      No actions matched the current request. Route values: typeParameter=CodeSystem, idParameter=$upload-external-code-system
dbug: Microsoft.AspNetCore.Builder.RouterMiddleware[1]
      Request did not match any routes
```

Let's get past 'n-of-1' and see if the same thing happens with SNOMED CT.  
I am looking at [this SNOMED-CT download site](https://www.nlm.nih.gov/healthit/snomedct/us_edition.html).

```
./tools/Northwestern/hapi-fhir-4.1.0-cli/hapi-fhir-cli upload-terminology -v r4 -t http://localhost:5000/ -u http://snomed.info/sct -d ./config/SnomedCT_USEditionRF2_PRODUCTION_20190901T120000Z.zip
```

Okay - same type of error, so it's not tied to LOINC (not that we expected it to be).  Next up, we'll try the hosted Azure option to see if it works or not.

Deploying from [the FHIR Server template to Azure](https://github.com/microsoft/fhir-server/blob/master/docs/DefaultDeployment.md#deploying-the-fhir-server-template), we end up getting the exact same results unfortunately.  I've [submited a GitHub issue](https://github.com/microsoft/fhir-server/issues/809) to hopefully get additional help.

Is [this sufficient for SNOMED-CT](https://www.hl7.org/fhir/codesystem-snomedct.json)?  Seems like it's not enough.  We're able to POST to /ConceptSet to get it loaded at least.