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