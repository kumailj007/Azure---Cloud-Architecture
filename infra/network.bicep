// =============================================================
// network.bicep — Azure VNet, Subnets, and NSGs (sample IaC)
// =============================================================
// Author : Kumail Janjua
// Purpose: Codifies the networking layer of the proposed cloud
//          architecture. Demonstrates the design-as-code principle:
//          the architecture is implementable, version-controlled,
//          and reproducible — not just diagrammed.
//
// Design : Three subnets, matching architecture.md
//            1. Gateway subnet          — Application Gateway WAF v2 (dedicated, required)
//            2. Application subnet      — App Service VNet integration (delegated)
//            3. Private endpoint subnet — private endpoints for SQL and Blob Storage
//
// Validate locally:
//   az bicep build --file network.bicep
//
// Deploy (requires an Azure subscription and resource group):
//   az deployment group create \
//     --resource-group <your-rg> \
//     --template-file network.bicep
// =============================================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Environment tag — used for cost tracking and governance.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'prod'

@description('Base name applied to networking resources.')
param namePrefix string = 'ecom'

// ---------- Variables ----------
var vnetName          = '${namePrefix}-vnet-${environment}'
var gatewaySubnetName = '${namePrefix}-appgw-subnet'
var appSubnetName     = '${namePrefix}-app-subnet'
var peSubnetName      = '${namePrefix}-pe-subnet'

var gatewaySubnetPrefix = '10.10.1.0/24'
var appSubnetPrefix     = '10.10.2.0/24'
var peSubnetPrefix      = '10.10.3.0/24'

var commonTags = {
  project:     'cloud-consulting-project'
  environment: environment
  owner:       'Kumail Janjua'
  managedBy:   'Bicep'
}

// ---------- NSG: Application Gateway subnet ----------
// Application Gateway v2 requires a dedicated subnet and will not deploy
// unless the infrastructure ports below are reachable. Locking this NSG down
// further than shown here is the most common cause of a failed AppGW deploy.
resource gatewayNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name:     '${namePrefix}-appgw-nsg-${environment}'
  location: location
  tags:     commonTags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority:                 100
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      'Internet'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '443'
        }
      }
      {
        // Port 80 exists only so the gateway can redirect to HTTPS.
        name: 'Allow-HTTP-Redirect'
        properties: {
          priority:                 110
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      'Internet'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '80'
        }
      }
      {
        // Required by Application Gateway v2 for health and configuration
        // management. Source is the GatewayManager service tag, not the internet.
        name: 'Allow-GatewayManager-Inbound'
        properties: {
          priority:                 120
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      'GatewayManager'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '65200-65535'
        }
      }
      {
        // Required for the gateway's internal health probes.
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority:                 130
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 '*'
          sourceAddressPrefix:      'AzureLoadBalancer'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          priority:                 4000
          direction:                'Inbound'
          access:                   'Deny'
          protocol:                 '*'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
        }
      }
    ]
  }
}

// ---------- NSG: Application subnet ----------
// The App Service backend is never reached directly from the internet —
// only from the gateway subnet.
resource appNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name:     '${namePrefix}-app-nsg-${environment}'
  location: location
  tags:     commonTags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-From-Gateway-Subnet'
        properties: {
          priority:                 100
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      gatewaySubnetPrefix
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '443'
        }
      }
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority:                 4000
          direction:                'Inbound'
          access:                   'Deny'
          protocol:                 '*'
          sourceAddressPrefix:      'Internet'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
        }
      }
    ]
  }
}

// ---------- NSG: Private endpoint subnet ----------
// Private endpoints for SQL and Blob Storage. Reachable only from the
// application tier; no inbound internet path exists.
resource peNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name:     '${namePrefix}-pe-nsg-${environment}'
  location: location
  tags:     commonTags
  properties: {
    securityRules: [
      {
        name: 'Allow-SQL-From-App-Subnet'
        properties: {
          priority:                 100
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      appSubnetPrefix
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '1433'
        }
      }
      {
        name: 'Allow-Storage-From-App-Subnet'
        properties: {
          priority:                 110
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      appSubnetPrefix
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '443'
        }
      }
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority:                 4000
          direction:                'Inbound'
          access:                   'Deny'
          protocol:                 '*'
          sourceAddressPrefix:      'Internet'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
        }
      }
    ]
  }
}

// ---------- Virtual Network ----------
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name:     vnetName
  location: location
  tags:     commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        // Dedicated to Application Gateway — the service cannot share a subnet
        // with any other resource.
        name: gatewaySubnetName
        properties: {
          addressPrefix: gatewaySubnetPrefix
          networkSecurityGroup: {
            id: gatewayNsg.id
          }
        }
      }
      {
        // Delegated to App Service so VNet integration can inject outbound
        // traffic from the web app into this subnet.
        name: appSubnetName
        properties: {
          addressPrefix: appSubnetPrefix
          networkSecurityGroup: {
            id: appNsg.id
          }
          delegations: [
            {
              name: 'appservice-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        // Private endpoints for Azure SQL Database and Blob Storage.
        // Network policies are disabled so private endpoint NICs can be placed here.
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetPrefix
          networkSecurityGroup: {
            id: peNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// ---------- Outputs ----------
output vnetId           string = vnet.id
output gatewaySubnetId  string = vnet.properties.subnets[0].id
output appSubnetId      string = vnet.properties.subnets[1].id
output peSubnetId       string = vnet.properties.subnets[2].id
output gatewayNsgId     string = gatewayNsg.id
