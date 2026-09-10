// External authentication provider for ARO HCP
// Source: https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/03-aro.html
// API version pinned for preview — update when GA version is published.

@description('The name of the external auth provider configuration')
param externalAuthName string

@description('The issuer url')
param issuerURL string

@description('The audiences for the issuer')
param issuerAudiences array = []

@description('The client ID for the OpenShift CLI')
param cliClientID string

@description('The client ID for the OpenShift Console')
param consoleClientID string

@description('Name of the ARO cluster')
param clusterName string

@description('Name of the claim associated with the username')
param usernameClaim string = 'email'

@description('Name of the claim associated with the groups')
param groupsClaim string = 'groups'

@description('Extra scopes to request during authentication')
param extraScopes array = []

@description('Username prefix policy')
param usernamePrefixPolicy string = 'NoPrefix'

resource hcp 'Microsoft.RedHatOpenShift/hcpOpenShiftClusters@2024-06-10-preview' existing = {
  name: clusterName
}

resource externalauth 'Microsoft.RedHatOpenShift/hcpOpenShiftClusters/externalAuths@2024-06-10-preview' = {
  parent: hcp
  name: externalAuthName
  properties: {
    claim: {
      mappings: {
        username: {
          claim: usernameClaim
          prefixPolicy: usernamePrefixPolicy
        }
        groups: {
          claim: groupsClaim
        }
      }
    }
    clients: [
      {
        clientId: consoleClientID
        component: {
          name: 'console'
          authClientNamespace: 'openshift-console'
        }
        type: 'Confidential'
        extraScopes: extraScopes
      }
      {
        clientId: cliClientID
        component: {
          name: 'cli'
          authClientNamespace: 'openshift-console'
        }
        type: 'Public'
        extraScopes: extraScopes
      }
    ]
    issuer: {
      url: issuerURL
      audiences: issuerAudiences
    }
  }
}
