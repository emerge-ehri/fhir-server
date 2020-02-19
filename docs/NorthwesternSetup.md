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

Okay, the fhir-server group at Microsoft responded quickly and kindly let us know that this isn't supported, but sounds like a future roadmap item.  It makes sense that it's not - what HAPI FHIR has done isn't actually a standard capability that needs to be supported.  It was a nice to have that HAPI built in.

After discussion with our eMERGE team, we're going to look at using external FHIR terminology servers for LOINC and SNOMED-CT if possible.  We will come back to that.  For now, here are two links to remember:

* LOINC - [https://loinc.org/fhir/](https://loinc.org/fhir/)
* SNOMED - [https://confluence.ihtsdotools.org/display/FHIR/FHIR+Terminology+Services+and+Resources](https://confluence.ihtsdotools.org/display/FHIR/FHIR+Terminology+Services+and+Resources)

## Loading patient data

Let's get on to what happens if the data gets loaded.  This lets us test the "what happens if we ignore the steps to load terminologies" question.

We'll start from a brand new, totally clean instance of the server.  This means resettting the database and reloading everything.  Then, from Postman we `GET` from [http://localhost:5000/Patient](http://localhost:5000/Patient) to make sure no patients come back.  Yes - confirmed this is the case.

Now from Postman, we are going to `POST` to the Patient URL at [http://localhost:5000/Patient](http://localhost:5000/Patient).  We will set `Content-Type` in the header to `application/fhir+json`.  For the body, we will [get the raw JSON of a test patient](https://www.hl7.org/fhir/patient-example.json).  We submit and get back a response.  When I `GET` from [http://localhost:5000/Patient](http://localhost:5000/Patient), I can see my new patient. **IT WORKS!!**

The question is about validation now - how do we do it? After some reading, I tried a `POST` to [http://localhost:5000/Patient/$validate](http://localhost:5000/Patient/$validate)

Not sure if [this issue is relevant](https://github.com/microsoft/fhir-server/issues/777), but that returns:

```
{
    "resourceType": "OperationOutcome",
    "id": "ce8fe5aa-9d7a-4221-bec0-f6f9fad82547",
    "issue": [
        {
            "severity": "error",
            "code": "not-found",
            "diagnostics": "The requested route was not found."
        }
    ]
}
```

This may actually be the case.  When we look at the conformance statement for the server, it's not listing a `validate` interaction:

```
{
"type": "Patient",
"interaction": [
    {
        "code": "create"
    },
    {
        "code": "read"
    },
    {
        "code": "vread"
    },
    {
        "code": "history-type"
    },
    {
        "code": "history-instance"
    },
    {
        "code": "update"
    },
    {
        "code": "delete"
    },
    {
        "code": "search-type"
    }
],
```

I noticed though that the [HAPI FHIR reference server](https://fhirtest.uhn.ca/conformance?serverId=home_r4&pretty=true) doesn't list this either, so maybe that's a false lead?  We do know there is a validate command that you can get [from the Patient resource tab](https://fhirtest.uhn.ca/resource?serverId=home_r4&pretty=true&resource=Patient).  Regardless, I did come across [another issue / pull request](https://github.com/microsoft/fhir-server/pull/793) that's looking to add support for `$validate`.  I think that's a good indication it's not supported as of yet.

That PR indicates we can 'validate' by submitting, so maybe that's the best we can do for now.  Assume that if it gets stored, it's valid.

Let's try now with a Bundle.  We have a test bundle from HGSC that we'll fire off.  Of course, a quick `GET` to [http://localhost:5000/Bundle](http://localhost:5000/Bundle) confirms there's nothing there.  We do our `POST` to [http://localhost:5000/Bundle](http://localhost:5000/Bundle) and we get back a response.  This looks like a good first start.  When we `GET` the list of bundles again, we can see the one we added.  Looks like we're able to file results as Bundles.  However, we don't see it in the list of patients.  Just to be safe, we're going to reset the database and just load the bundle.

When we do, here's the log information:

```
info: Microsoft.AspNetCore.Hosting.Internal.WebHost[1]
      Request starting HTTP/1.1 POST http://localhost:5000/Bundle application/fhir+json 143310
dbug: Microsoft.AspNetCore.StaticFiles.StaticFileMiddleware[1]
      POST requests are not supported
dbug: Microsoft.AspNetCore.Routing.Tree.TreeRouter[1]
      Request successfully matched the route with name '(null)' and template '{typeParameter:fhirResource}'
dbug: Microsoft.AspNetCore.Mvc.Internal.ActionSelector[2]
      Action 'Microsoft.Health.Fhir.Api.Controllers.FhirController.ConditionalCreate (Microsoft.Health.Fhir.R4.Api)' with id '552ec694-3942-4abf-bf7d-33d39d1d5a70' did not match the constraint 'Microsoft.Health.Fhir.Api.Features.ActionConstraints.ConditionalConstraintAttribute'
dbug: Microsoft.AspNetCore.Mvc.Internal.ActionSelector[2]
      Action 'Microsoft.Health.Fhir.Api.Controllers.FhirController.ConditionalUpdate (Microsoft.Health.Fhir.R4.Api)' with id '0c0dd708-321f-47f3-8c03-2648e41d746c' did not match the constraint 'Microsoft.AspNetCore.Mvc.Internal.HttpMethodActionConstraint'
dbug: Microsoft.AspNetCore.Mvc.Internal.ActionSelector[2]
      Action 'Microsoft.Health.Fhir.Api.Controllers.FhirController.SearchByResourceType (Microsoft.Health.Fhir.R4.Api)' with id 'e1733b1f-93c6-4f43-8635-9495a66e7a0a' did not match the constraint 'Microsoft.AspNetCore.Mvc.Internal.HttpMethodActionConstraint'
info: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[3]
      Route matched with {action = "Create", controller = "Fhir"}. Executing controller action with signature System.Threading.Tasks.Task`1[Microsoft.AspNetCore.Mvc.IActionResult] Create(Hl7.Fhir.Model.Resource) on controller Microsoft.Health.Fhir.Api.Controllers.FhirController (Microsoft.Health.Fhir.R4.Api).
dbug: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[1]
      Execution plan of authorization filters (in the following order): Microsoft.AspNetCore.Mvc.Authorization.AuthorizeFilter, Microsoft.AspNetCore.Mvc.Authorization.AuthorizeFilter
dbug: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[1]
      Execution plan of resource filters (in the following order): Microsoft.AspNetCore.Mvc.ViewFeatures.Internal.SaveTempDataFilter
dbug: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[1]
      Execution plan of action filters (in the following order): Microsoft.AspNetCore.Mvc.Internal.ControllerActionFilter (Order: -2147483648), Microsoft.Health.Fhir.Api.Features.Filters.FhirRequestContextRouteDataPopulatingFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Audit.AuditLoggingFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Filters.OperationOutcomeExceptionFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Filters.ValidateContentTypeFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Filters.ValidateResourceTypeFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Filters.ValidateModelStateAttribute (Order: 0)
dbug: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[1]
      Execution plan of exception filters (in the following order): None
dbug: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[1]
      Execution plan of result filters (in the following order): Microsoft.AspNetCore.Mvc.ViewFeatures.Internal.SaveTempDataFilter, Microsoft.Health.Fhir.Api.Features.Filters.FhirRequestContextRouteDataPopulatingFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Audit.AuditLoggingFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Filters.OperationOutcomeExceptionFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Filters.ValidateContentTypeFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Filters.ValidateResourceTypeFilterAttribute (Order: 0), Microsoft.Health.Fhir.Api.Features.Filters.ValidateModelStateAttribute (Order: 0)
info: Microsoft.AspNetCore.Authorization.DefaultAuthorizationService[1]
      Authorization was successful.
info: Microsoft.AspNetCore.Authorization.DefaultAuthorizationService[1]
      Authorization was successful.
dbug: Microsoft.AspNetCore.Mvc.ModelBinding.ParameterBinder[22]
      Attempting to bind parameter 'resource' of type 'Hl7.Fhir.Model.Resource' ...
dbug: Microsoft.AspNetCore.Mvc.ModelBinding.Binders.BodyModelBinder[24]
      Attempting to bind model of type 'Hl7.Fhir.Model.Resource' using the name '' in request data ...
dbug: Microsoft.AspNetCore.Mvc.ModelBinding.Binders.BodyModelBinder[1]
      Selected input formatter 'Microsoft.Health.Fhir.Api.Features.Formatters.FhirJsonInputFormatter' for content type 'application/fhir+json'.
dbug: Microsoft.AspNetCore.Server.Kestrel[25]
      Connection id "0HLT3AFJHLOA6", Request id "0HLT3AFJHLOA6:00000003": started reading request body.
dbug: Microsoft.AspNetCore.Mvc.ModelBinding.Binders.BodyModelBinder[25]
      Done attempting to bind model of type 'Hl7.Fhir.Model.Resource' using the name ''.
dbug: Microsoft.AspNetCore.Mvc.ModelBinding.ParameterBinder[23]
      Done attempting to bind parameter 'resource' of type 'Hl7.Fhir.Model.Resource'.
info: Microsoft.Health.Fhir.Api.Features.Audit.IAuditLogger[0]
      ActionType: Executing
      EventType: AuditEvent
      Audience: (null)
      Authority: (null)
      ResourceType: (null)
      RequestUri: http://localhost:5000/Bundle
      Action: create
      StatusCode: (null)
      CorrelationId: 1103aa80-3637-480e-a898-bb3d7e2fa1e5
      Claims: 
info: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[1]
      Executing action method Microsoft.Health.Fhir.Api.Controllers.FhirController.Create (Microsoft.Health.Fhir.R4.Api) - Validation state: Valid
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.4168135.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0005058.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002460.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0158580.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002378.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001471.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001984.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001579.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001415.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001473.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002930.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002227.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002353.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002444.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002521.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001781.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002220.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002404.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001614.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001530.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001487.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001486.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001462.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001858.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001535.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001310.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001900.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002031.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001417.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002090.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002725.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001586.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001418.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001882.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001560.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001368.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001411.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001584.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001246.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001390.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001496.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002990.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002020.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002105.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001674.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0002327.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001690.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001442.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001432.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001595.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001384.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001385.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001382.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001379.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001393.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001400.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001152.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001159.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001155.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001167.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001345.
info: Microsoft.Health.Fhir.Core.Features.Validation.Narratives.NarrativeHtmlSanitizer[0]
      NarrativeHtmlSanitizer.Validate executed in 00:00:00.0001860.
dbug: Microsoft.Health.Fhir.Core.Features.Search.SearchIndexer[0]
      The FHIR element 'id' will be converted using 'Microsoft.Health.Fhir.Core.Features.Search.Converters.IdToTokenSearchValueTypeConverter'.
dbug: Microsoft.Health.Fhir.Core.Features.Search.SearchIndexer[0]
      The FHIR element 'instant' will be converted using 'Microsoft.Health.Fhir.Core.Features.Search.Converters.InstantToDateTimeSearchValueTypeConverter'.
dbug: Microsoft.Health.Fhir.Core.Features.Search.SearchIndexer[0]
      The FHIR element 'code' will be converted using 'Microsoft.Health.Fhir.Core.Features.Search.Converters.CodeOfTToTokenSearchValueTypeConverter'.
info: Microsoft.Health.Fhir.SqlServer.Features.Storage.SqlServerFhirModel[0]
      Cache miss for string ID on dbo.System
info: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[2]
      Executed action method Microsoft.Health.Fhir.Api.Controllers.FhirController.Create (Microsoft.Health.Fhir.R4.Api), returned result Microsoft.Health.Fhir.Api.Features.ActionResults.FhirResult in 662.8601ms.
dbug: Microsoft.AspNetCore.Mvc.Infrastructure.DefaultOutputFormatterSelector[11]
      List of registered output formatters, in the following order: Microsoft.Health.Fhir.Api.Features.Formatters.FhirJsonOutputFormatter, Microsoft.Health.Fhir.Api.Features.Formatters.FhirXmlOutputFormatter, Microsoft.Health.Fhir.Api.Features.Formatters.NonFhirResourceXmlOutputFormatter, Microsoft.Health.Fhir.Api.Features.Formatters.HtmlOutputFormatter, Microsoft.AspNetCore.Mvc.Formatters.HttpNoContentOutputFormatter, Microsoft.AspNetCore.Mvc.Formatters.StringOutputFormatter, Microsoft.AspNetCore.Mvc.Formatters.StreamOutputFormatter, Microsoft.AspNetCore.Mvc.Formatters.JsonOutputFormatter
dbug: Microsoft.AspNetCore.Mvc.Infrastructure.DefaultOutputFormatterSelector[6]
      Attempting to select an output formatter based on Accept header '*/*'.
dbug: Microsoft.AspNetCore.Mvc.Infrastructure.DefaultOutputFormatterSelector[2]
      Selected output formatter 'Microsoft.Health.Fhir.Api.Features.Formatters.FhirJsonOutputFormatter' and content type 'application/fhir+json' to write the response.
info: Microsoft.AspNetCore.Mvc.Infrastructure.ObjectResultExecutor[1]
      Executing ObjectResult, writing value of type 'Hl7.Fhir.Model.Bundle'.
info: Microsoft.Health.Fhir.Api.Features.Audit.IAuditLogger[0]
      ActionType: Executed
      EventType: AuditEvent
      Audience: (null)
      Authority: (null)
      ResourceType: Bundle
      RequestUri: http://localhost:5000/Bundle
      Action: create
      StatusCode: Created
      CorrelationId: 1103aa80-3637-480e-a898-bb3d7e2fa1e5
      Claims: 
info: Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker[2]
      Executed action Microsoft.Health.Fhir.Api.Controllers.FhirController.Create (Microsoft.Health.Fhir.R4.Api) in 920.2426ms
info: Microsoft.Health.Fhir.Api.Features.ApiNotifications.ApiNotificationMiddleware[0]
      ApiNotificationMiddleware executed in 00:00:00.9246478.
dbug: Microsoft.AspNetCore.Server.Kestrel[9]
      Connection id "0HLT3AFJHLOA6" completed keep alive response.
info: Microsoft.AspNetCore.Hosting.Internal.WebHost[2]
      Request finished in 924.7453ms 201 application/fhir+json; charset=utf-8
dbug: Microsoft.AspNetCore.Server.Kestrel[26]
      Connection id "0HLT3AFJHLOA6", Request id "0HLT3AFJHLOA6:00000003": done reading request body.

```


We'll try doing this with an [example bundle from the FHIR website](https://www.hl7.org/fhir/bundle-transaction.json.html) as well.  It also gets submitted, but when I search for patients I don't see it listed.  It's showing up as a Bundle result though.

Doing some more searching it [sounds like this should be supported](https://github.com/microsoft/fhir-server/issues/237).  One thing to check was the app setttings about enabling this.  So in our appsettings.json we have to make sure this is enabled:

```
"CoreFeatures": {
    "SupportsBatch": true,
    "SupportsTransaction": true
},
```

I tested again, and still not working.  So, the bundle exists, but it's not creating the embedded resources.

_....Some time passes...._

Here's the problem - [I'm apparently not smart and couldn't read the spec, misread the spec, something](https://github.com/microsoft/fhir-server/issues/866#issuecomment-580583313).  It turns out that the whole issue was me posting to `http://localhost:5000//Bundle`, when instead I needed to post to `http://localhost:5000/`.  As soon as I do that, I get back a much better response with every data element in the bundle processed correctly.  All of the resource endpoints are now returning the information that I would expect to retrieve.

### Getting data back out

So now we've got it in, and now we can do the typical FHIR searches against the resources.  We can pull a patient using a canonical identifier the system assigned:

`http://localhost:5000/Patient?_id=65092887-1fef-4c29-9107-bc2358aaf88e`

Or we can search by an identifier assigned to the patient by the lab (this will be more meaningful to us);

`http://localhost:5000/Patient?identifier=11429b73-5f5c-4e24-8cfe-82c7e17a7aea`

We can then (following the [FHIR search documentation](https://www.hl7.org/fhir/search.html), since I obviously need to be reading the documentation).

I can get all of the Observation resources back for a single patient, but that of course is a little messy because the Observations conform to different profiles so it's more of a mixed bag.

`http://localhost:5000/Observation?patient:Patient.identifier=11429b73-5f5c-4e24-8cfe-82c7e17a7aea`

We started with this to constrain by profile, but it didn't work.  Let's figure out why that is.

`http://localhost:5000/Observation?_profile=http://hl7.org/fhir/uv/genomics-reporting/StructureDefinition/medication-metabolism`

Interesting - if we use the full search item path (`Resource.meta.profile`) we get back data, but it's kind of a false assurance - we're getting back everything still.  So this **isn't** a valid search, even though it's syntactically correct.

`http://localhost:5000/Observation?patient:Patient.identifier=11429b73-5f5c-4e24-8cfe-82c7e17a7aea&Resource.meta.profile=http://hl7.org/fhir/uv/genomics-reporting/StructureDefinition/medication-metabolism`