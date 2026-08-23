# Cloud Cost Model & Optimization

## Cost Objectives
- Minimize infrastructure cost while maintaining performance and security
- Scale resources based on demand rather than provisioning for peak
- Ensure predictable, defensible monthly cloud spending

## Estimated Monthly Costs

Sized for a mid-size e-commerce workload: a customer-facing web application with
a transactional database, moderate traffic, and a single primary region.

| Resource | Service & sizing | Estimated Monthly Cost (EUR) |
|----------|------------------|------------------------------|
| Web application | Azure App Service (P0v3, autoscale 1–3 instances) | 120 |
| Database | Azure SQL Database (General Purpose, serverless) | 150 |
| Storage | Azure Blob Storage (Hot tier, ~500 GB) | 40 |
| Ingress & WAF | Application Gateway WAF v2 (fixed ~300 + ~8 capacity units) | 375 |
| Networking | VNet, private endpoints, static public IP | 25 |
| Security & monitoring | Microsoft Defender for Cloud (App Service + SQL plans) | 50 |
| Backup & recovery | Azure Backup, geo-redundant | 30 |
| **Total** | | **~790 EUR / month** |

Prices are list rates for a Western European region, rounded. Actual spend varies
with traffic, reservations, and Enterprise Agreement discounts.

### The dominant line item

Application Gateway WAF v2 is roughly 47% of this bill, and almost all of it is
the fixed per-gateway-hour charge — it is billed whether traffic is heavy or
light. Any serious optimisation effort on this architecture starts there, not
with the App Service tier.

## Alternatives considered and rejected

Pricing the alternatives is part of the design work, so they are documented
rather than silently omitted.

| Option | Cost | Decision |
|--------|------|----------|
| **Azure Firewall (Standard)** | ~840 EUR/month fixed, before any traffic | **Rejected.** Azure Firewall filters egress across a hub-and-spoke estate. This is a single-VNet PaaS workload with no such estate, and the perimeter controls it would provide are already covered by the WAF, NSGs, and private endpoints. The cost is not proportionate to the threat model at this scale. |
| **Azure Front Door Standard** | ~32 EUR/month | **Rejected for now.** Substantially cheaper and adds global edge caching, but the Standard tier supports custom WAF rules only — no managed OWASP rule set. For a workload handling customer and payment data, managed rules are not optional. |
| **Azure Front Door Premium** | ~305 EUR/month | **Viable alternative.** Bundles the managed rule set and adds a global edge. Worth revisiting if the client expands beyond a single region — at that point it becomes the better choice than Application Gateway. |
| **Application Gateway WAF v2** | ~375 EUR/month | **Selected.** Correct L7 ingress for a single-region VNet design, supports the managed OWASP rule set, and integrates with private endpoints for the App Service backend. |

## Optimization Strategy

- **Autoscaling** on App Service so instance count follows demand instead of peak
- **Serverless SQL** so the database scales down during off-peak hours
- **Reserved capacity** (1-year) on App Service and SQL once traffic is predictable — typically 30–40% off list
- **Blob lifecycle policies** moving older media and backups to Cool and Archive tiers
- **Budgets and cost alerts** in Azure Cost Management, with tag-based chargeback by environment
- **Right-size the gateway** by monitoring actual capacity unit consumption; the fixed cost is unavoidable, but over-provisioned CUs are not

## Governance

- All resources tagged with `project`, `environment`, and `owner` for cost attribution
- Azure Policy denying deployment of untagged resources and of SKUs outside the approved list
- Monthly cost review against budget, with variance over 10% requiring justification
