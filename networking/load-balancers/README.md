# Load Balancers

Demos and patterns for AWS load balancer consolidation on OpenShift / ROSA.

## Demos

| Demo | Description |
|------|-------------|
| [alb-ingress-grouping](./alb-ingress-grouping/) | Share a single AWS ALB across multiple Ingresses on ROSA HCP — the OpenShift equivalent of EKS `IngressGroup` |

## Related

- [AWS Load Balancer Operator (Red Hat docs)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/networking_operators/aws-load-balancer-operator-1)
- [AWS Load Balancer Operator on ROSA (RH MOBB)](https://cloud.redhat.com/experts/rosa/aws-load-balancer-operator/)
- [AWS Load Balancer Controller — IngressGroup](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/#group.name)
