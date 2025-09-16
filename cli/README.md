# codexpc-cli (planned)

A minimal CLI that uses the Kotlin/Native client to send a request and print streamed tokens.

Planned usage:

```
codexpc-cli \
  --service com.yourorg.codexpc \
  --model gpt-oss-20b \
  --checkpoint ~/models/gpt-oss-20b/metal/model.bin \
  --prompt "hello"
```

