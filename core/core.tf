provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

data "aws_caller_identity" "current" {}

# data "aws_region" "current" {
#   current = true
# }

resource "aws_dynamodb_table" "minecraft_terraform_dynamodb" {
  name           = "${var.aws_dynamodb_terraform_lock}"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

resource "aws_s3_bucket" "minecraft_terraform_plan" {
  bucket = "${var.aws_s3_terraform_plan}"
  acl    = "private"

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket" "minecraft_terraform_state" {
  bucket = "${var.aws_s3_terraform_state}"
  acl    = "private"

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket" "minecraft_world_backup" {
  bucket = "${var.aws_s3_world_backup}"
  acl    = "private"

  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket" "minecraft_server_dashboard" {
  bucket = "${var.aws_s3_server_dashboard}"
  acl    = "public-read"

  policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement":[{
    "Sid":"PublicReadGetObject",
    "Effect":"Allow",
    "Principal": "*",
    "Action":["s3:GetObject"],
    "Resource":["arn:aws:s3:::${var.aws_s3_server_dashboard}/*"],
    "Condition":{
      "Bool":{
        "aws:SecureTransport":"true"
      }
    }
  }]
}
EOF

  #"Resource":["arn:aws:s3:::example-bucket/*"]

  website {
    index_document = "index.html"

    #error_document = "error.html"
  }
}

resource "aws_s3_bucket_object" "dashboard_index" {
  bucket       = "${aws_s3_bucket.minecraft_server_dashboard.id}"
  key          = "index.html"
  content      = "${data.template_file.dashboard_index.rendered}"
  content_type = "text/html"
  etag         = "${md5(data.template_file.dashboard_index.rendered)}"
}

#resource "aws_s3_bucket_object" "dashboard_error" {
#  bucket       = "${aws_s3_bucket.minecraft_server_dashboard.id}"
#  key          = "error.html"
#  content      = "${data.template_file.dashboard_error.rendered}"
#  content_type = "text/html"
#  etag         = "${md5(data.template_file.dashboard_error.rendered)}"
#}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    origin_id   = "${var.aws_s3_server_dashboard}"
    domain_name = "${aws_s3_bucket.minecraft_server_dashboard.bucket_domain_name}"
  }

  # If using route53 aliases for DNS we need to declare it here too, otherwise we'll get 403s.
  #aliases = ["${var.domain}"]

  enabled             = true
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${var.aws_s3_server_dashboard}"

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # The cheapest priceclass
  #price_class = "PriceClass_100"

  # This is required to be specified even if it's not used.
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_object" "auto_shutoff" {
  bucket = "${aws_s3_bucket.minecraft_world_backup.id}"
  key    = "auto_shutoff.py"

  # source = "auto_shutoff.py"
  content = "${data.template_file.auto_shutoff.rendered}"

  # etag = "${md5(file("auto_shutoff.py"))}"
  etag = "${md5(data.template_file.auto_shutoff.rendered)}"
}

resource "aws_key_pair" "aws_minecraft_ssh_key" {
  key_name   = "terraform-minecraft-key"
  public_key = "${file("${var.ssh_minecraft_public_key}")}"
}

resource "aws_api_gateway_rest_api" "minecraft_api" {
  name        = "minecraft-api"
  description = "This is my API for demonstration purposes"
}

resource "aws_api_gateway_resource" "minecraft_api_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  parent_id   = "${aws_api_gateway_rest_api.minecraft_api.root_resource_id}"
  path_part   = "minecraft"
}

# One resource per method to avoid:
# https://github.com/terraform-providers/terraform-provider-aws/issues/483

resource "aws_api_gateway_resource" "minecraft_api_deploy" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  parent_id   = "${aws_api_gateway_resource.minecraft_api_resource.id}"
  path_part   = "deploy"
}

resource "aws_api_gateway_resource" "minecraft_api_destroy" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  parent_id   = "${aws_api_gateway_resource.minecraft_api_resource.id}"
  path_part   = "destroy"
}

resource "aws_api_gateway_resource" "minecraft_api_status" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  parent_id   = "${aws_api_gateway_resource.minecraft_api_resource.id}"
  path_part   = "status"
}

resource "aws_api_gateway_method" "minecraft_api_deploy_post" {
  rest_api_id   = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id   = "${aws_api_gateway_resource.minecraft_api_deploy.id}"
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "minecraft_api_destroy_delete" {
  rest_api_id   = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id   = "${aws_api_gateway_resource.minecraft_api_destroy.id}"
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "minecraft_api_status_get" {
  rest_api_id   = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id   = "${aws_api_gateway_resource.minecraft_api_status.id}"
  http_method   = "GET"
  authorization = "NONE"
}

# resource "aws_api_gateway_stage" "minecraft_api_prod" {
#   # ??????? This is only needed by aws_api_gateway_method_settings
#   # stage_name = "${aws_api_gateway_deployment.minecraft_api_deployment.stage_name}"
#   stage_name = "prod"
#   rest_api_id   = "${aws_api_gateway_rest_api.minecraft_api.id}"
#   deployment_id = "${aws_api_gateway_deployment.minecraft_api_deployment.id}"
# }

resource "aws_api_gateway_method_settings" "minecraft_api_deploy_post_settings" {
  # ????????? This doesn't actually enable logging

  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"

  # stage_name = "${aws_api_gateway_stage.minecraft_api_prod.stage_name}"
  stage_name  = "${aws_api_gateway_deployment.minecraft_api_deployment.stage_name}"
  method_path = "${aws_api_gateway_resource.minecraft_api_deploy.path_part}/${aws_api_gateway_method.minecraft_api_deploy_post.http_method}"

  settings {
    caching_enabled = false
    metrics_enabled = true
    logging_level   = "INFO"
  }

  depends_on = ["aws_api_gateway_account.api_gateway_account"]
}

resource "aws_api_gateway_method" "minecraft_api_deploy_options" {
  rest_api_id   = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id   = "${aws_api_gateway_resource.minecraft_api_deploy.id}"
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "minecraft_api_deploy_integration_options" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_deploy.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_deploy_options.http_method}"
  type        = "MOCK"

  request_templates = {
    "application/json" = <<EOT
{"statusCode": 200}
EOT
  }
}

resource "aws_api_gateway_method" "minecraft_api_status_options" {
  rest_api_id   = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id   = "${aws_api_gateway_resource.minecraft_api_status.id}"
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "minecraft_api_status_integration_options" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_status.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_status_options.http_method}"
  type        = "MOCK"

  request_templates = {
    "application/json" = <<EOT
{"statusCode": 200}
EOT
  }
}

resource "aws_api_gateway_integration" "minecraft_api_deploy_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_deploy.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_deploy_post.http_method}"

  # type = "AWS_PROXY"
  # AWS_PROXY is not compatible with the asynchronous event type
  type = "AWS"

  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.minecraft_lambda_deploy.arn}/invocations"
  integration_http_method = "POST"

  request_parameters = {
    "integration.request.header.X-Amz-Invocation-Type" = "'Event'"
  }

  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_api_gateway_integration" "minecraft_api_destroy_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_destroy.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_destroy_delete.http_method}"

  # type = "AWS_PROXY"
  # AWS_PROXY is not compatible with the asynchronous event type
  type = "AWS"

  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.minecraft_lambda_destroy.arn}/invocations"
  integration_http_method = "POST"

  request_parameters = {
    "integration.request.header.X-Amz-Invocation-Type" = "'Event'"
  }

  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_api_gateway_integration" "minecraft_api_status_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_status.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_status_get.http_method}"
  type        = "AWS_PROXY"

  # AWS_PROXY is not compatible with the asynchronous event type
  # type = "AWS"
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.minecraft_lambda_status.arn}/invocations"

  integration_http_method = "POST"

  # request_parameters = {
  #   "integration.request.header.X-Amz-Invocation-Type" = "'Event'"
  # }
  # passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_api_gateway_method_response" "destroy_200" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_destroy.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_destroy_delete.http_method}"
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_method_response" "deploy_200" {
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_deploy.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_deploy_post.http_method}"
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "deploy_integration_response" {
  depends_on  = ["aws_api_gateway_integration.minecraft_api_deploy_integration"]
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_deploy.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_deploy_post.http_method}"
  status_code = "${aws_api_gateway_method_response.deploy_200.status_code}"

  response_parameters {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates {
    "application/json" = "{}"

    # "application/json" = ""
  }
}

resource "aws_api_gateway_integration_response" "destroy_integration_response" {
  depends_on  = ["aws_api_gateway_integration.minecraft_api_destroy_integration"]
  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  resource_id = "${aws_api_gateway_resource.minecraft_api_destroy.id}"
  http_method = "${aws_api_gateway_method.minecraft_api_destroy_delete.http_method}"
  status_code = "${aws_api_gateway_method_response.destroy_200.status_code}"

  response_templates {
    "application/json" = "{}"
  }
}

resource "aws_api_gateway_deployment" "minecraft_api_deployment" {
  depends_on = [
    "aws_api_gateway_integration.minecraft_api_deploy_integration",
    "aws_api_gateway_integration.minecraft_api_destroy_integration",
    "aws_api_gateway_integration.minecraft_api_status_integration",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.minecraft_api.id}"
  stage_name  = "prod"

  # stage_name  = "dev"
}

# Note: As there is no API method for deleting account settings or resetting it
# to defaults, destroying this resource will keep your account settings intact.
# Applied region-wide per provider block
resource "aws_api_gateway_account" "api_gateway_account" {
  cloudwatch_role_arn = "${aws_iam_role.cloudwatch.arn}"
}

resource "aws_iam_role" "cloudwatch" {
  name = "api_gateway_cloudwatch_global"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatch" {
  # lifecycle {
  #   prevent_destroy = true
  # }
  name = "cloudwatch_logs"

  role = "${aws_iam_role.cloudwatch.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

data "template_file" "auto_shutoff" {
  template = "${file("auto_shutoff.py")}"

  vars = {
    lambda_destroy_url = "${aws_api_gateway_deployment.minecraft_api_deployment.invoke_url}${aws_api_gateway_resource.minecraft_api_destroy.path}"
  }
}

data "template_file" "dashboard_index" {
  template = "${file("../web/index_src.html")}"

  vars = {
    lambda_deploy_url = "${aws_api_gateway_deployment.minecraft_api_deployment.invoke_url}${aws_api_gateway_resource.minecraft_api_deploy.path}"
    lambda_status_url = "${aws_api_gateway_deployment.minecraft_api_deployment.invoke_url}${aws_api_gateway_resource.minecraft_api_status.path}"
  }
}

resource "local_file" "dashboard_index" {
  content  = "${data.template_file.dashboard_index.rendered}"
  filename = "../web/index.html"
}

#data "template_file" "dashboard_error" {
#  template = "${file("../web/error_src.html")}"
#
#  vars = {
#    #https_url = "https://${aws_s3_bucket.minecraft_server_dashboard.bucket_domain_name}/${aws_s3_bucket_object.dashboard_index.key}"
#    https_url = "https://s3.amazonaws.com/${aws_s3_bucket.minecraft_server_dashboard.id}/${aws_s3_bucket_object.dashboard_index.key}"
#  }
#}
#
#resource "local_file" "dashboard_error" {
#  content  = "${data.template_file.dashboard_error.rendered}"
#  filename = "../web/error.html"
#}

data "archive_file" "lambda_destroy_deploy_zip" {
  type        = "zip"
  source_dir  = "lambda_destroy_deploy"
  output_path = "lambda_destroy_deploy.zip"
}

resource "aws_lambda_permission" "apigw_lambda_deploy" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.minecraft_lambda_deploy.arn}"
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.minecraft_api.id}/*/${aws_api_gateway_method.minecraft_api_deploy_post.http_method}/minecraft/deploy"
}

resource "aws_lambda_permission" "apigw_lambda_destroy" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.minecraft_lambda_destroy.arn}"
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.minecraft_api.id}/*/${aws_api_gateway_method.minecraft_api_destroy_delete.http_method}/minecraft/destroy"
}

resource "aws_lambda_permission" "apigw_lambda_status" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.minecraft_lambda_status.arn}"
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.minecraft_api.id}/*/${aws_api_gateway_method.minecraft_api_status_get.http_method}/minecraft/status"
}

resource "aws_lambda_function" "minecraft_lambda_deploy" {
  filename      = "lambda_destroy_deploy.zip"
  function_name = "minecraft-deploy"
  handler       = "lambda_destroy_deploy.lambda_handler_deploy"
  role          = "${aws_iam_role.lambda_minecraft_provision_role.arn}"
  runtime       = "python3.6"

  # runtime          = "python2.7"
  timeout          = 300
  memory_size      = 320
  publish          = true
  source_code_hash = "${data.archive_file.lambda_destroy_deploy_zip.output_base64sha256}"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DISCORD_CLIENT_TOKEN     = "${var.discord_client_token}"
      DISCORD_CHANNEL          = "${var.discord_channel}"
      S3_TERRAFORM_PLAN_BUCKET = "${var.aws_s3_terraform_plan}"
    }
  }

  depends_on = [
    "aws_iam_role_policy.minecraft_provision_policy",
    "aws_iam_instance_profile.minecraft_provision_instance_profile",
  ]
}

resource "aws_lambda_function" "minecraft_lambda_destroy" {
  filename      = "lambda_destroy_deploy.zip"
  function_name = "minecraft-destroy"
  handler       = "lambda_destroy_deploy.lambda_handler_destroy"
  role          = "${aws_iam_role.lambda_minecraft_provision_role.arn}"
  runtime       = "python3.6"

  # runtime          = "python2.7"
  timeout          = 300
  memory_size      = 320
  publish          = true
  source_code_hash = "${data.archive_file.lambda_destroy_deploy_zip.output_base64sha256}"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DISCORD_CLIENT_TOKEN     = "${var.discord_client_token}"
      DISCORD_CHANNEL          = "${var.discord_channel}"
      S3_TERRAFORM_PLAN_BUCKET = "${var.aws_s3_terraform_plan}"
    }
  }

  depends_on = [
    "aws_iam_role_policy.minecraft_provision_policy",
    "aws_iam_instance_profile.minecraft_provision_instance_profile",
  ]
}

resource "aws_lambda_function" "minecraft_lambda_status" {
  filename      = "lambda_status.zip"
  function_name = "minecraft-status"
  handler       = "lambda_status.lambda_handler_status"
  role          = "${aws_iam_role.lambda_minecraft_provision_role.arn}"
  runtime       = "python3.6"

  # runtime          = "python2.7"
  timeout          = 300
  publish          = true
  source_code_hash = "${base64sha256(file("lambda_status.zip"))}"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      S3_TERRAFORM_PLAN_BUCKET  = "${var.aws_s3_terraform_plan}"
      S3_TERRAFORM_STATE_BUCKET = "${var.aws_s3_terraform_state}"
    }
  }

  depends_on = [
    "aws_iam_role_policy.minecraft_provision_policy",
    "aws_iam_instance_profile.minecraft_provision_instance_profile",
  ]
}

resource "aws_iam_instance_profile" "minecraft_provision_instance_profile" {
  name = "minecraft_provision_instance_profile"
  role = "${aws_iam_role.lambda_minecraft_provision_role.name}"
}

resource "aws_iam_role_policy" "minecraft_provision_policy" {
  name = "minecraft_provision_policy"
  role = "${aws_iam_role.lambda_minecraft_provision_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "ec2:*",
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": "s3:*",
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": "iam:*",
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": "dynamodb:*",
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "lambda_minecraft_provision_role" {
  name = "minecraft_lambda_minecraft_provision_role"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_eip" "ip" {}

output "ip" {
  value = "${aws_eip.ip.public_ip}"
}

output "aws_eip_id" {
  value = "${aws_eip.ip.id}"
}

output "aws_key_pair" {
  value = "${aws_key_pair.aws_minecraft_ssh_key.id}"
}

output "api_destroy_url" {
  value = "${aws_api_gateway_deployment.minecraft_api_deployment.invoke_url}${aws_api_gateway_resource.minecraft_api_destroy.path}"
}

output "api_deploy_url" {
  value = "${aws_api_gateway_deployment.minecraft_api_deployment.invoke_url}${aws_api_gateway_resource.minecraft_api_deploy.path}"
}

output "api_status_url" {
  value = "${aws_api_gateway_deployment.minecraft_api_deployment.invoke_url}${aws_api_gateway_resource.minecraft_api_status.path}"
}

output "dashboard_url" {
  #value = "${aws_s3_bucket.minecraft_server_dashboard.website_domain}  ${aws_s3_bucket.minecraft_server_dashboard.website_endpoint}  ${aws_s3_bucket.minecraft_server_dashboard.bucket_domain_name}"
  value = "https://s3.amazonaws.com/${aws_s3_bucket.minecraft_server_dashboard.id}/${aws_s3_bucket_object.dashboard_index.key}"
}

output "aws_dynamodb_terraform_lock" {
  value = "${aws_dynamodb_table.minecraft_terraform_dynamodb.name}"
}

output "aws_s3_terraform_state" {
  value = "${aws_s3_bucket.minecraft_terraform_state.id}"
}

output "aws_s3_terraform_plan" {
  value = "${aws_s3_bucket.minecraft_terraform_plan.id}"
}

output "aws_s3_world_backup" {
  value = "${aws_s3_bucket.minecraft_world_backup.id}"
}

# output "region_var" {
#   value = "${var.aws_region}"
# }


# output "region_current" {
#   value = "${data.aws_region.current.name}"
# }


# vim: ts=2 sw=2 et

