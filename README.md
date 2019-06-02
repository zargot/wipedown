# Collection of wipedown utilities

## License
This project is licensed under the MIT License

## #1 Discord DM Deleter
Wipes your messages from a Discord DM.

Usage:
```
wipe_discord CHANNEL_ID AUTH_TOKEN
```

Limitations:
- Server-side rate limiting makes this rather slow at about 10k msg/hour.
- Must provide channel id and auth token manually.
- Currently only works on private DMs with one recipient.
- Only deletes default message type; not pins, calls, etc.
