![Architecture Diagram](./architecture.png)

# Azure Cloud Architecture Design

## Architecture Overview

The proposed architecture is designed for scalability, security and high
availability using Microsoft Azure PaaS services. It is a single-region design
with geo-redundant backup, sized for a mid-size e-commerce workload.

### Core Components

| Layer | Service | Purpose |
|-------|---------|---------|
| Ingress | Azure Application Gateway (WAF v2) | L7 routing, TLS termination, OWASP managed rule set |
| Compute | Azure App Service | Managed PaaS hosting for the web application |
| Data | Azure SQL Database | Transactional store for customer and order data |
| Storage | Azure Blob Storage | Static content, media, backups |
| Networking | Azure Virtual Network, NSGs, private endpoints | Segmentation and private service access |
| Identity | Microsoft Entra ID | RBAC, MFA, Conditional Access, least privilege |
| Resilience | Azure Backup & Recovery Services | Geo-redundant backups, DR strategy |

## Network Design

The VNet is segmented into three subnets:

- **Gateway subnet** — dedicated to Application Gateway (required; it cannot share a subnet)
- **Application subnet** — App Service VNet integration for outbound traffic
- **Private endpoint subnet** — private endpoints for Azure SQL Database and Blob Storage

Traffic flow: internet → Application Gateway (WAF inspection, TLS termination) →
App Service → private endpoint → SQL Database. No inbound path reaches the data
tier directly.

**Note on PaaS placement:** Azure SQL Database, Blob Storage and Microsoft Entra
ID are platform services, not VNet-resident resources. SQL and Storage are
reached over **private endpoints**, which project a private IP for the service
into the VNet. Entra ID is a global identity service accessed over the public
Microsoft endpoint and secured by Conditional Access, not by network placement.

### Network Security Groups

- Gateway subnet: inbound 443 from the internet, 80 for HTTP-to-HTTPS redirect, plus the Azure infrastructure ports Application Gateway requires
- Application subnet: no inbound from the internet; traffic arrives only from the gateway subnet
- Private endpoint subnet: no inbound internet access

## Identity & Access Management

- Role-Based Access Control, scoped to resource group rather than subscription
- Multi-Factor Authentication enforced for all users via Conditional Access
- Privileged Identity Management for admin roles — eligible, not standing, access
- Managed identities for App Service to reach SQL and Storage without stored credentials

## Security Controls

- OWASP Core Rule Set enforced at the gateway
- TLS 1.2 minimum, HTTPS-only, TLS terminated at the gateway and re-encrypted to the backend
- Encryption at rest (Transparent Data Encryption on SQL, Storage Service Encryption on Blob)
- Private endpoints so data services have no public network exposure
- Microsoft Defender for Cloud on the App Service and SQL plans
- Diagnostic logs and WAF logs centralised in Log Analytics

## High Availability & Resilience

- App Service autoscaling across multiple instances, zone-redundant where the region supports it
- Application Gateway WAF v2 is zone-redundant and autoscaling by default
- Azure SQL Database with geo-redundant backup and point-in-time restore
- Documented RTO/RPO targets and a tested restore procedure

## Design Decisions

**Why Application Gateway and not Azure Load Balancer.** Azure Load Balancer is
a layer-4 service that targets VMs and VM Scale Sets; it cannot front App
Service. App Service already load-balances across its own instances. Application
Gateway is the correct L7 entry point and adds the WAF.

**Why no Azure Firewall.** Azure Firewall filters egress across a hub-and-spoke
estate. This is a single-VNet PaaS workload, and its perimeter needs are met by
the WAF, NSGs, and private endpoints — at roughly 840 EUR/month less. See
[`cost-model.md`](./cost-model.md) for the full comparison.
