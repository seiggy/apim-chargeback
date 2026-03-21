// Create an API Management instance
// https://docs.microsoft.com/en-us/azure/templates/microsoft.apimanagement/2021-08-01/service

param apimInstanceName string
param location string

resource apimInstance 'Microsoft.ApiManagement/service@2021-08-01' = {
  name: apimInstanceName
  location: location
  sku: {
    // name: 'Consumption' // Developer, Consumption, Basic, Standard, Premium, Isolated
    // capacity: 0 // Capacity is not applicable for the Consumption tier
    name: 'Developer' // Developer, Consumption, Basic, Standard, Premium, Isolated
    capacity: 1 // Capacity is not applicable for the Consumption tier
  }
  properties: {
    publisherEmail: 'admin@contoso.com'
    publisherName: 'Contoso'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

output name string = apimInstance.name
output clientId string = apimInstance.identity.principalId
