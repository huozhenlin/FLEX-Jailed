# XHSBridge module

`Classes/XHSBridge/` adds a small XHS-specific layer to the injectable FLEX
dylib. It does not forward FLEX UI state or arbitrary model/runtime logs.

## Forwarded data

Only filtered request transactions are sent to the configured collector:

- request URL scheme, host, path and HTTP method;
- query parameter names;
- request and response byte lengths;
- HTTP status and error code;
- bounded JSON shape summaries.

The module uses FLEX's existing `FLEXNetworkObserver` and
`FLEXNetworkRecorder`, so it sees the same URLSession/NSURLConnection traffic
that FLEX displays. It subscribes to recorder notifications rather than adding
a second broad network swizzle.

Headers, cookies, authorization values, device identifiers, tokens and raw
request/response bodies are not forwarded.

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

The build script automatically compiles these files because it collects every
Objective-C source under `Classes/`.
