# Integration probe for the smoke suite in the parent directory: attaches the
# module under test's rendered bucket-policy statement to the fixture bucket
# (or deliberately does not), then fetches a known object through the real
# distribution. The smoke suite applies it twice, attach_bucket_policy = false
# then true, to prove the OAC read path end to end: no policy means 403, the
# module's statement means 200 with the exact object body.
#
# Short-lived test scaffolding, not a deployable pattern; excluded from policy
# scanning like ../setup.

resource "aws_s3_bucket_policy" "origin" {
  count = var.attach_bucket_policy ? 1 : 0

  bucket = var.bucket_name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [jsondecode(var.bucket_policy_statement_json)]
  })
}

resource "time_sleep" "settle" {
  count = var.attach_bucket_policy ? 1 : 0

  create_duration = "${var.settle_seconds}s"

  depends_on = [aws_s3_bucket_policy.origin]
}

data "http" "probe" {
  url = var.url

  request_headers = {
    Accept = "text/html"
  }

  # Retries transport errors and 5xx only; a 403 or 200 is returned as is and
  # asserted by the caller.
  retry {
    attempts     = 5
    min_delay_ms = 2000
    max_delay_ms = 10000
  }

  depends_on = [time_sleep.settle]
}
