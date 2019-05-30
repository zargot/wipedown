# Discord DM Deleter
# Copyright 2019 (c) zargot
#
# Limitations:
# - must provide channel id and auth token manually
# - currently only works on private DMs with one recipient
# - only deletes default message type; not pins, calls, etc.
#
# API: https://github.com/discordapp/discord-api-docs/blob/master/docs/Reference.md
#
# TODO
# - more dynamic rate limit
# - optimize eta calculation
# - option to set delete-before date

import json, streams, strformat, strutils, times
import httpclient except get, delete
from os import paramStr, sleep
from stats import mean
from terminal import eraseLine

type
    Id = uint64

using
    str: string
    client: HttpClient
    res: Response

func `/`(a, b: string): string =
    a & "/" & b

const
    server = "https://discordapp.com/api/v6"
    channels = server/"channels"
    batchSize = 100

var
    requestDelay = 175

proc require(cond: bool, err: string) =
    if not cond:
        raise newException(Exception, err)

proc waitForRateLimit(res: Response) =
    let
        json = res.body.parseJson
        ms = json["retry_after"].getInt
    echo ""
    echo fmt"rate limited for {ms} ms..."
    sleep ms + 1
    requestDelay += 10

template req(client, kind, uri): Response =
    var res: Response
    while true:
        res = httpclient.kind(client, uri)
        if res.status == Http429:
            waitForRateLimit(res)
            continue
        break
    require res.status == Http200 or res.status == Http204, res.status
    res

proc get(client: HttpClient, uri: string): auto =
    req(client, get, uri)

proc delete(client: HttpClient, uri: string) =
    sleep requestDelay
    discard req(client, delete, uri)

proc toId(str): Id =
    str.parseUInt.uint64

proc toStr(id: Id): string =
    $id

proc getUser(client): auto =
    const
        users = server/"users"
        me = users/"@me"
    let
        res = client.get me
        user = res.body.parseJson
        id = user["id"].getStr
        name = user["username"].getStr
    (id, name)

#proc timestampToDateTime(s: string): DateTime =
#    const
#        fmt0Str = "YYYY-MM-dd'T'HH:mm:sszzz"
#        fmt1Str = "YYYY-MM-dd'T'HH:mm:ss'.'ffffffzzz"
#        fmt0 = initTimeFormat fmt0Str
#        fmt1 = initTimeFormat fmt1Str
#        fmtLengths = [25, 25+7]
#    let n = s.len
#    require n in fmtLengths, "invalid timestamp: " & s
#    s.parse(if n == fmtLengths[0]: fmt0 else: fmt1, utc())

#proc timestampToUnix(s: string): int64 =
#    let date = s.timestampToDateTime
#    date.toTime.toUnix

proc getMessages(client: HttpClient, channel, lastId: string): JsonNode =
    #echo "requesting more messages"
    let messages = channel/"messages"
    var params: seq[string]
    if lastId != "":
        params.add "before=" & lastId
    params.add "limit=" & $batchSize
    let
        paramStr = "?" & params.join("&")
        query = messages & paramStr
    let res = client.get query
    res.body.parseJson

proc getMessageIds(client: HttpClient, channel, userId: string, lastId: var string,
                   total: var int, res: var seq[Id]): bool =
    ## returns false when done
    let json = getMessages(client, channel, lastId)
    if json.len == 0:
        return
    total += json.len
    #echo fmt"parsing {json.len} messages"
    for msg in json:
        let id = msg["id"].getStr
        lastId = id
        if msg["type"].getInt == 0 and msg["author"]["id"].getStr == userId:
            #echo "msg: ", msg["content"].getStr
            res.add id.toId
    json.len >= batchSize

proc getChannelName(client; channel: string): string =
    let
        res = client.get channel
        json = res.body.parseJson()
    require json["type"].getInt == 1, "channel is not a DM"
    json["recipients"][0]["username"].getStr

proc prompt(q: string): bool =
    stdout.write q & " [y/N]"
    let yn = stdin.readLine
    case yn.normalize
    of "y", "yes":
        return true

proc deleteMessages(client; channel: string, ids: openArray[Id]) =
    echo ""
    let messages = channel/"messages"
    var
        t0 = epochTime() - 1
        mpsv: array[100, float]
    for i, id in ids:
        let
            j = i+1
            progress = (j / ids.len) * 100
            remaining = ids.len - j
            t1 = epochTime()
            dt = t1 - t0
            mps = 1 / dt
        mpsv[i mod mpsv.len] = mps
        let
            avgMps = mpsv.mean
            eta = (remaining.float / avgMps).int
            etaSec = if eta < 60: eta else: 0
            etaMin = convert(Seconds, Minutes, eta) mod 60
            etaHour = convert(Seconds, Hours, eta)
        t0 = t1
        client.delete messages/id.toStr
        stdout.eraseLine
        stdout.write fmt"deleting {j}/{ids.len} ({progress:.1f}%)"
        stdout.write fmt", eta: {etaHour:02}:{etaMin:02}:{etaSec:02}"
    echo ""

proc main =
    setStdIoUnbuffered()

    let
        chanId = paramStr 1
        auth = paramStr 2
        channel = channels/chanId
        client = newHttpClient()
    client.headers.add "authorization", auth

    let
        (userId, userName) = getUser(client)
        chanName = getChannelName(client, channel)
    echo fmt"deleting messages from {userName} in DM with {chanName}"
    if not prompt("continue?"):
        return

    echo ""
    var
        ids: seq[Id]
        lastId: string
        total: int
    while getMessageIds(client, channel, userId, lastId, total, ids):
        stdout.eraseLine
        stdout.write fmt"processed over {total} ({ids.len}) messages so far..."
        break
    echo ""

    echo fmt"{ids.len} messages found"
    if not prompt("are you sure you want to delete them?"):
        return
    if true: quit 0
    deleteMessages client, channel, ids

main()
