# XHSBridge module

`Classes/XHSBridge/` adds a small XHS-specific layer to the injectable FLEX
dylib. It does not forward FLEX UI state or arbitrary model/runtime logs.

## Forwarded data

Only filtered request transactions are sent to the configured collector:

- request URL scheme, host, path and HTTP method;
- query parameter names;
- request and response byte lengths;
- HTTP status and error code;
- bounded JSON shape summaries;
- a bounded response-body preview for filtered requests.

The module uses FLEX's existing `FLEXNetworkObserver` and
`FLEXNetworkRecorder`, so it sees the same URLSession/NSURLConnection traffic
that FLEX displays. It subscribes to recorder notifications rather than adding
a second broad network swizzle.

Request headers, cookies, authorization values, device identifiers and tokens
are not forwarded. Response bodies are capped at 256 KiB and credential-like
JSON keys are redacted before forwarding.

## Deep-link commands

The module polls the configured collector command endpoint:

```json
{"command":"open_note","note_id":"<id>","note_type":"video"}
```

Video notes use:

```text
xhsdiscover://item/<id>?type=video
```

Other notes use:

```text
xhsdiscover://item/<id>
```

`{"command":"go_back"}` performs one guarded return after a bridge-opened
detail page. A second return command is a no-op at the root controller.

## Optional request blocking

In `Network History`, configure:

```text
XHS Request Blocking
XHS Allowed Path Prefixes
```

Enter semicolon-separated path prefixes, for example:

```text
/api/sns/v1/note;/api/sns/v2/note;/api/sns/v5/note
```

When blocking is enabled, only matching `NSURLSessionTask` paths are allowed
to resume. Non-matching tasks are cancelled before network activity starts.
The collector request itself is always allowed. Blocking is disabled by
default and an empty allowlist fails closed, so configure the allowlist before
turning it on.

The build script automatically compiles these files because it collects every
Objective-C source under `Classes/`.
