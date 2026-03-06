param redisCacheName string
param location string

resource redisCache 'Microsoft.Cache/Redis@2021-06-01' = {
  name: redisCacheName
  location: location
  properties: {
    sku: {
      name: 'Standard'
      family: 'C'
      capacity: 1
    }
    enableNonSslPort: false
  }
  identity: {
    type: 'SystemAssigned'
  } 
}
output redisCacheName string = redisCache.name
output redisHostName string = '${redisCache.name}.redis.cache.windows.net'
output redisPrincipalId string = redisCache.identity.principalId
