# =============================================
# CD — GitHub Actions → AWS (OIDC + IAM Role)
# =============================================
# ADR-0008: GitHub Actions 가 OIDC 로 AssumeRole 후
# S3 업로드 + SSM Run Command 로 EC2 배포. 22 포트 의존 제거.
#
# 신뢰 경계: main 브랜치의 push 와 workflow_dispatch 만 허용.

# ─── GitHub OIDC Provider ─────────────────────────────
# token.actions.githubusercontent.com 의 OIDC IdP 를 AWS 에 등록.
# thumbprint 는 GitHub 공식값 (v1, v2 두 개 등록 — rotation 대비).
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Name = "kicklog-github-oidc"
  }
}

# ─── GitHub Actions IAM Role (Assumed via OIDC) ──────
resource "aws_iam_role" "github_actions_ci" {
  name = "kicklog-github-actions-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # main 브랜치 push 와 workflow_dispatch (refs/heads/main 컨텍스트) 만 허용
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo_owner}/${var.github_repo_name}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Name = "kicklog-github-actions-ci"
  }
}

# ─── 최소 권한 정책 ───────────────────────────────────
# S3 업로드 + SSM SendCommand + SSM GetCommandInvocation 만.
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "kicklog-github-actions-deploy"
  role = aws_iam_role.github_actions_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "UploadComposeToStaging"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
        ]
        Resource = "${aws_s3_bucket.deploy_staging.arn}/*"
      },
      {
        Sid    = "RunCommandOnAppInstance"
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.app.id}",
          "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
        ]
      },
      {
        Sid    = "PollCommandResult"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
        ]
        Resource = "*"
      },
    ]
  })
}
