# Wipedown
Collection of wipedown utilities

## License
This project is licensed under the MIT License

## #1 Discord DM Deleter
Wipes your messages from a Discord DM

### Requirements
- Nim v0.19 (devel)
- OpenSSL
- GNU Make (optional)

### Usage
```
cd wipedown
make
./wipe_discord -c:CHANNEL_ID -a:AUTH_TOKEN [-n] [--backup]
```

### Limitations
- Server-side rate limiting makes this rather slow at about 10k msg/hour
- Must provide channel id and auth token manually
- Currently only works on private DMs with one recipient
- Only deletes default message type; not pins, calls, etc.
- Does not handle multi-attachment messages with identical filenames
