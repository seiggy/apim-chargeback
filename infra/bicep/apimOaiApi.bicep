param apimInstanceName string
param oaiApiName string
param apiSpecFileUri string
param openAiServiceUrl string
//param policyContent string


resource apimInstance 'Microsoft.ApiManagement/service@2021-08-01' existing = {
  name: apimInstanceName
}

resource openAiBackend 'Microsoft.ApiManagement/service/backends@2021-08-01' = {
  parent: apimInstance
  name: 'openAiBackend'
  properties: {
    url: openAiServiceUrl
    protocol: 'http'
    title: 'OpenAI Backend'
    description: 'Backend for OpenAI APIs (Language, DALL-E, Whisper)'
  }
}

resource apimOaiApi 'Microsoft.ApiManagement/service/apis@2021-08-01' = {
  parent: apimInstance
  name: oaiApiName
  properties: {
    format: 'openapi-link'
    value: apiSpecFileUri
    path: 'openapi' // this matches the route in function.json
    protocols: [
      'http','https'
    ]
  }
}

resource apimOaiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2021-08-01' = {
  parent: apimOaiApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    //value: loadTextContent('../policies/example-policy.xml') // Load the policy content directly
    value: '''
    <policies>
      <inbound>
        <base />
        <!-- Set the backend service to the Azure OpenAI endpoint -->
        <set-backend-service id="apim-generated-policy" backend-id="openAiBackend" />
        <!-- Use managed identity to authenticate against the Azure Cognitive Services -->
        <authentication-managed-identity resource="https://cognitiveservices.azure.com/" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
    </policies>
    '''
  }
}
