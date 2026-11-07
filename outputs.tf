output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "app_url" {
  description = "Public URL of the application via Route53"
  value       = "http://${var.domain_name}"
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.app.zone_id
}

output "ns_records" {
  description = "NS records to delegate at the pp.ua registrar"
  value       = aws_route53_zone.app.name_servers
}

output "ecs_cluster" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "autoscaling" {
  description = "Autoscaling thresholds"
  value = {
    min_capacity         = var.min_capacity
    max_capacity         = var.max_capacity
    scale_out_above_pct  = var.scale_out_threshold
    scale_in_below_pct   = var.scale_in_threshold
    scale_in_cooldown_min = var.scale_in_cooldown_seconds / 60
  }
}
