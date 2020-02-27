# Johns Hopkins Setup Notes

## Considerations
* [Pricing to use Azure API for FHIR](https://azure.microsoft.com/en-us/pricing/details/azure-api-for-fhir/)
* [Cosmos Capacity Calculator](https://cosmos.azure.com/capacitycalculator/)

## Getting started
* Get an Azure subscription to install managed FHIR server
* Complete quick start steps to deploy Azure API for FHIR
  * [Quickstart: Deploy Azure API for FHIR using Azure portal](https://docs.microsoft.com/en-us/azure/healthcare-apis/fhir-paas-portal-quickstart)
  * Note: there is an open source alternative [option](https://docs.microsoft.com/en-us/azure/healthcare-apis/fhir-oss-portal-quickstart)

## Once ready to begin paying
* Ways to connect to FHIR server
  * [Postman FHIR server in Azure](https://docs.microsoft.com/en-us/azure/healthcare-apis/access-fhir-postman-tutorial)
  * [Azure Active Directory SMART on FHIR proxy](https://docs.microsoft.com/en-us/azure/healthcare-apis/use-smart-on-fhir-proxy)
  
## Using a test data set
* Simulate sample patients using Synthea
  * [Synthetic Patient Population Simulator](https://github.com/synthetichealth/synthea)
* Import sample patients 
  * [Azure FHIR Importer Function](https://github.com/microsoft/fhir-server-samples/tree/master/src/FhirImporter)
