provider "aws" {}

resource "random_pet" "main" {
  length    = 2
  separator = "-"
}

locals {
  # under probe_metrics.py's prefix, so the probe finds these endpoints too
  name = "c7n-endpoint-metrics-async-${random_pet.main.id}"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# the bucket name has to contain "sagemaker" for AmazonSageMakerFullAccess to
# let the execution role read the model and requests, and write responses
resource "aws_s3_bucket" "main" {
  bucket        = "c7n-sagemaker-async-metrics-${random_pet.main.id}"
  force_destroy = true
}

# see README.md for how model.tar.gz is built
resource "aws_s3_object" "model" {
  bucket = aws_s3_bucket.main.id
  key    = "model.tar.gz"
  source = "${path.module}/model.tar.gz"
  etag   = filemd5("${path.module}/model.tar.gz")
}

# an async request isn't sent with the call: the endpoint fetches it from s3
resource "aws_s3_object" "request" {
  bucket  = aws_s3_bucket.main.id
  key     = "request.csv"
  content = "1.0\n"
}

data "aws_sagemaker_prebuilt_ecr_image" "xgboost" {
  repository_name = "sagemaker-xgboost"
  image_tag       = "1.7-1"
}

resource "aws_sagemaker_model" "main" {
  name               = local.name
  execution_role_arn = aws_iam_role.execution.arn

  # the arn alone orders this after the role, not after its policy, and an
  # endpoint whose role can't yet read the artifact fails to come up
  depends_on = [aws_iam_role_policy_attachment.execution]

  primary_container {
    image          = data.aws_sagemaker_prebuilt_ecr_image.xgboost.registry_path
    model_data_url = "s3://${aws_s3_bucket.main.id}/${aws_s3_object.model.key}"
  }
}

# The async inference config is what makes an endpoint async, and both
# endpoints share this one. A configuration can't be edited, and an
# endpoint follows its configuration by name, hence name_prefix.
resource "aws_sagemaker_endpoint_configuration" "async" {
  name_prefix = "c7n-em-async-"

  lifecycle {
    create_before_destroy = true
  }

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.main.name
    initial_instance_count = 1
    instance_type          = "ml.c5.large"
  }

  async_inference_config {
    output_config {
      s3_output_path = "s3://${aws_s3_bucket.main.id}/responses"
    }
  }
}

# invoked when recording
resource "aws_sagemaker_endpoint" "busy" {
  name                 = "${local.name}-busy"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.async.name
}

# never invoked
resource "aws_sagemaker_endpoint" "idle" {
  name                 = "${local.name}-idle"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.async.name
}

output "request_location" {
  value = "s3://${aws_s3_bucket.main.id}/${aws_s3_object.request.key}"
}
