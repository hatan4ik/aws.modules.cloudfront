# Upgrading from v1.x to v2.0

v2.0.0 has breaking interface changes. Each one is listed below with what
breaks, why, and exactly what to change. Changes that are not breaking but are
worth knowing about (the `web_acl_arn` validation fix, the new
`required_kms_key_policy_json` output) are in [CHANGELOG.md](../CHANGELOG.md).

## 1. `cache_behaviors` is now an ordered list, not a map

**What breaks.** `cache_behaviors` changed type from
`map(object({...}))` keyed by `path_pattern` to
`list(object({ path_pattern = string, ... }))`. A v1.x map value fails type
conversion at plan time.

**Why.** CloudFront evaluates ordered cache behaviors in the order it
receives them and uses the **first** one whose `path_pattern` matches. In
v1.x the map was rendered through a `dynamic` block, which iterates a map in
lexical key order, so precedence was decided by string sort, not by the
caller. For example `"/static/*"` sorts before `"/static/images/*"`, so the
broader pattern was always rendered first and the narrower one could never
match. That was a silent correctness bug for any caller with overlapping
patterns. With a list, the order you write is the order CloudFront evaluates.

**What to change.** Move each map key into a `path_pattern` field and write
the entries in the precedence order you actually want, most specific first:

```hcl
# v1.x
cache_behaviors = {
  "/static/*"        = {}
  "/static/images/*" = { cache_policy_id = "<policy-id>" }
}

# v2.0
cache_behaviors = [
  { path_pattern = "/static/images/*", cache_policy_id = "<policy-id>" },
  { path_pattern = "/static/*" },
]
```

All other entry fields (`allowed_methods`, `cached_methods`,
`cache_policy_id`, `compress`) and their defaults are unchanged.

**Plan impact.** If you list entries in the same lexical order v1.x rendered
them in (sorted by `path_pattern`), the plan shows no change to the
distribution. If you reorder them, which is the point for overlapping
patterns, the plan shows an in-place update of `aws_cloudfront_distribution.this`
reordering `ordered_cache_behavior`; nothing is replaced. Review it: an
update changes which behavior serves which requests once it deploys.

**New validations.** A list, unlike map keys, can repeat a value, so
`path_pattern` must now be unique (a duplicate could never match) and
non-empty. `"*"` is still rejected; it is reserved for
`default_cache_behavior`.

## 2. `minimum_protocol_version` no longer accepts policies that allow TLS 1.0 or 1.1

**What breaks.** `TLSv1`, `TLSv1_2016`, and `TLSv1.1_2016` are rejected at
plan time. The default is unchanged (`TLSv1.2_2021`).

**Why.** Those security policies let viewers negotiate TLS 1.0 or TLS 1.1,
both deprecated (RFC 8996). The current policies `TLSv1.2_2025` and
`TLSv1.3_2025` are now accepted.

**What to change.** If you set one of the removed values, choose
`TLSv1.2_2021` (the default), `TLSv1.2_2025`, or `TLSv1.3_2025` (TLS 1.3
only; check your viewers support it). The plan shows an in-place update of
the distribution's viewer certificate settings.

## 3. `partition` accepts only `aws`

**What breaks.** `partition = "aws-cn"`, `"aws-us-gov"`, or any other value
is rejected at plan time, and a distribution whose looked-up partition is not
`aws` fails a resource precondition.

**Why.** v1.x accepted any partition but always returned the standard
partition's CloudFront hosted zone ID, which is wrong in China. More
fundamentally, this module cannot work outside the standard partition at all:
CloudFront in the China Regions does not support Origin Access Control (this
module's only origin access mechanism), ACM viewer certificates, or AWS WAF,
and AWS GovCloud (US) has no CloudFront. Rejecting the value is honest;
silently accepting it produced a wrong output and an apply that could not
succeed.

**What to change.** Nothing, if you were on `aws` (or left `partition` unset
in a standard-partition account). There was no working configuration in any
other partition to migrate.
