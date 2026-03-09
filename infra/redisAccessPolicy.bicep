param redisCacheName string
param principalId string

resource redisCache 'Microsoft.Cache/Redis@2024-03-01' existing = {
  name: redisCacheName
}

resource accessPolicyAssignment 'Microsoft.Cache/redis/accessPolicyAssignments@2024-03-01' = {
  name: 'containerapp-data-owner'
  parent: redisCache
  properties: {
    accessPolicyName: 'Data Owner'
    objectId: principalId
    objectIdAlias: 'containerapp-identity'
  }
}
