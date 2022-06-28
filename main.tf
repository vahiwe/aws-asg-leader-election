##
# Leader election automatically determines a "leader" instance within an autoscaling
# group.  Scaling events will trigger leader election, insuring there is always one
# leader whenever instances are added or removed.

provider "aws" {
  region = "us-east-1"
}

resource "aws_cloudwatch_event_rule" "scaling_event_rule" {
  name        = "scaling_event_rule"
  description = "Rule for scaling event in elastic beanstalk"
  is_enabled = false

  event_pattern = <<EOF
{
  "source": ["aws.autoscaling"],
  "detail-type": ["EC2 Instance Launch Successful", "EC2 Instance Terminate Successful", "EC2 Instance Launch Unsuccessful", "EC2 Instance Terminate Unsuccessful", "EC2 Instance-launch Lifecycle Action", "EC2 Instance-terminate Lifecycle Action"],
  "detail": {
    "AutoScalingGroupName": [ {"prefix": "awseb-"} ]
  }
}
EOF
}

resource "aws_lambda_function" "leader" {
  function_name = "${var.name}"
  description = "Elects a leader in an autoscaling upon receiving scaling events"
  runtime = "nodejs16.x"
  filename = "${path.module}/files/ElectASGLeader.zip"
  source_code_hash = "${filebase64sha256("${path.module}/files/ElectASGLeader.zip")}"
  handler = "ElectASGLeader.handler"
  role = "${aws_iam_role.lambda.arn}"
  timeout = "30"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.scaling_event_rule.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.leader.arn
}

resource "aws_lambda_permission" "eventBridge" {
    statement_id = "AllowExecutionFromEventBridge"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.leader.arn}"
    principal = "events.amazonaws.com" 
    source_arn = "${aws_cloudwatch_event_rule.scaling_event_rule.arn}"
}

resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda" {
    name = "${var.name}-lambda-role-policy"
    role = "${aws_iam_role.lambda.id}"
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Resource": [ "*" ],
            "Action": [
                "ec2:*Tags",
                "ec2:Describe*"
            ],
            "Sid": "Stmt1447795937000",
            "Effect": "Allow"
        },
        {
            "Resource": "arn:aws:logs:*:*:*",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ],
            "Effect": "Allow"
        },
        {
            "Resource": [
                "*"
            ],
            "Action": [
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInstances",
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeTags",
                "s3:ListMyBuckets"
            ],
            "Sid": "Stmt1447796511000",
            "Effect": "Allow"
        }
    ]
}
EOF
}
