// =============================================================
// network.bicep — Azure VNet, Subnets, and NSG (sample IaC)
// =============================================================
// Author : Kumail Janjua
// Purpose: Codifies the networking layer of the proposed cloud
//          architecture. Demonstrates the design-as-code principle:
//          the architecture is implementable, version-controlled,
//          and reproducible — not just diagrammed.
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
var vnetName        = '${namePrefix}-vnet-${environment}'
var publicSubnet    = '${namePrefix}-public-subnet'
var privateSubnet   = '${namePrefix}-private-subnet'
var nsgName         = '${namePrefix}-public-nsg-${environment}'

var commonTags = {
  project:     'cloud-consulting-project'
  environment: environment
  owner:       'Kumail Janjua'
  managedBy:   'Bicep'
}

// ---------- Network Security Group (public subnet) ----------
// Least-privilege inbound rules: only HTTPS from the internet.
// HTTP is allowed only to redirect to HTTPS at the App Service level.
resource publicNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name:     nsgName
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

// ---------- Virtual Network with public + private subnets ----------
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
        name: publicSubnet
        properties: {
          addressPrefix: '10.10.1.0/24'
          networkSecurityGroup: {
            id: publicNsg.id
          }
        }
      }
      {
        name: privateSubnet
        properties: {
          addressPrefix: '10.10.2.0/24'
          // Private subnet — no public NSG, no inbound internet access.
          // Reachable only from the public subnet via App Service VNet integration.
          serviceEndpoints: [
            { service: 'Microsoft.Sql' }
            { service: 'Microsoft.Storage' }
          ]
        }
      }
    ]
  }
}

// ---------- Outputs ----------
output vnetId          string = vnet.id
output publicSubnetId  string = vnet.properties.subnets[0].id
output privateSubnetId string = vnet.properties.subnets[1].id
output nsgId           string = publicNsg.id
