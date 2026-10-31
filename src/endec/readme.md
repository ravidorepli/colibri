<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# Encoding and Decoding Entities

This directory contains entities which perform data encoding and decoding.

### Entities

- `rle_encode` a simple Run-Length Encoder.
- `rle_decode` a simple Run-Length Decoder.
- `decode_8b10b` a simple Run-Length Encoder.
- `encode_8b10b` a simple Run-Length Decoder.


### Development status and testing

| entity       | simulation         | self-checking tb   | formal verification |
| ------------ | ------------------ | ------------------ | ------------------- |
| `rle_encode` | ✅ | ✅ | ✅  |
| `rle_decode` | ✅ | ✅ | ✅  |
| `decoder_8b10b` | ✅ | ✅ | ❌                 |
| `encoder_8b10b` | ✅ | ✅ | ❌                 |
