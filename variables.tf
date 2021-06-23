variable "cloudwatch_logs_export_bucket" {
  default     = ""
  description = "Bucket to export logs"
}

variable "exporter_name" {
    default = "log_exporter_s3"
    description = "Unique name to create all the resources for log exporting"
}

variable "bucket_name" {
    description = "Bucket Name to store the logs"
}

variable "log_group_names" {
    description = "List of log group names to export"
    default = []
}

variable "schedule_period" {
    description = "Period to export logs"
    default ="rate(24 hours)"
}