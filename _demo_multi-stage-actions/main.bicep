@description('The location into which your Azure resources should be deployed.')
param location string = resourceGroup().location

// param applicationName string = 'toywebsite'

// param kvname string = 'dependency-akv'

// param rgname string = 'cts-dependency-rg'

// @description('Existing Azure DNS zone in target resource group')
// param dnsZone string

@description('Select the type of environment you want to provision. Allowed values are Production and Test.')
@allowed([
  'production'
  'test'
])
param environmentType string

@description('A unique suffix to add to resource names that need to be globally unique.')
@maxLength(13)
param resourceNameSuffix string = uniqueString(resourceGroup().id)

@description('The URL to the product review API.')
param reviewApiUrl string

@secure()
@description('The API key to use when accessing the product review API.')
param reviewApiKey string






param certificateName string = 'toywebsite'
// param appServicePlanId string
// param appServiceName string
param dnsZoneName string = 'toywebsite.com'
param dnsRecordName string = 'www'





// Define the names for resources.
var appServiceAppName = 'toy-website-${resourceNameSuffix}'
var appServicePlanName = 'toy-website'
var logAnalyticsWorkspaceName = 'workspace-${resourceNameSuffix}'
var applicationInsightsName = 'toywebsite'
var storageAccountName = 'mystorage${resourceNameSuffix}'

// Define the SKUs for each component based on the environment type.
var environmentConfigurationMap = {
  Production: {
    appServicePlan: {
      sku: {
        name: 'S1'
        capacity: 1
      }
    }
    storageAccount: {
      sku: {
        name: 'Standard_LRS'
      }
    }
  }
  Test: {
    appServicePlan: {
      sku: {
        name: 'S1'
        capacity: 1
      }
    }
    storageAccount: {
      sku: {
        name: 'Standard_LRS'
      }
    }
  }
}





//#####################################################################


resource appServiceCertificate 'Microsoft.Web/certificates@2021-02-01' = {
  name: certificateName
  location: location
  properties: {
    canonicalName: certificateName
    password: 'YourSecurePassword'
    serverFarmId: appServicePlan.id //appServicePlanId
  }
}

// resource appService 'Microsoft.Web/sites@2021-02-01' = {
//   name: appServiceName
//   location: location
//   properties: {
//     serverFarmId: appServicePlan.id //appServicePlanId
//     httpsOnly: true
//   }
// }

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: dnsZoneName
  location: 'global'
}

resource dnsRecord 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: dnsZone
  name: dnsRecordName
  properties: {
    TTL: 3600
    ARecords: [
      {
        ipv4Address: split(appServiceApp.properties.outboundIpAddresses, ',')[0]
      }
    ]
  }
}

resource hostnameBinding 'Microsoft.Web/sites/hostNameBindings@2021-02-01' = {
  parent: appServiceApp
  name: certificateName
  properties: {
    siteName: appServiceApp.name
    hostNameType: 'Verified'
  }
}

resource sslBinding 'Microsoft.Web/sites/hostNameBindings@2021-02-01' = {
  parent: appServiceApp
  name: '${dnsRecord.name}.${dnsZone.name}'
  properties: {
    sslState: 'SniEnabled'
    thumbprint: appServiceCertificate.properties.thumbprint
  }
}

output certificateThumbprint string = appServiceCertificate.properties.thumbprint

//#####################################################################

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: environmentConfigurationMap[environmentType].appServicePlan.sku
}

resource appServiceApp 'Microsoft.Web/sites@2022-03-01' = {
  name: appServiceAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientCertEnabled: true
    siteConfig: {
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'ReviewApiUrl'
          value: reviewApiUrl
        }
        {
          name: 'ReviewApiKey'
          value: reviewApiKey
        }
      ]
    }
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    Flow_Type: 'Bluefield'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: environmentConfigurationMap[environmentType].storageAccount.sku
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    supportsHttpsTrafficOnly: true
  }
}

output appServiceAppHostName string = appServiceApp.properties.defaultHostName
