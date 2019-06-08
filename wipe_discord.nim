# API: https://github.com/discordapp/discord-api-docs/blob/master/docs/Reference.md

# TODO
# - export copy before delete
# - more dynamic rate limit
# - optimize eta calculation
# - option to set delete-before date

import json, os, parseopt, streams, strformat, strutils, times
import httpclient except get, delete
from algorithm import reverse
#from sequtils import deduplicate
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
    copyBuf: seq[string]

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

proc timestampToDateTime(s: string): DateTime =
    const
        fmt0Str = "YYYY-MM-dd'T'HH:mm:sszzz"
        fmt1Str = "YYYY-MM-dd'T'HH:mm:ss'.'ffffffzzz"
        fmt0 = initTimeFormat fmt0Str
        fmt1 = initTimeFormat fmt1Str
        fmtLengths = [25, 25+7]
    let n = s.len
    require n in fmtLengths, "invalid timestamp: " & s
    s.parse(if n == fmtLengths[0]: fmt0 else: fmt1, utc())

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
                   total: var int, res: var seq[Id], doCopy: bool): bool =
    ## returns false when done
    let json = getMessages(client, channel, lastId)
    if json.len == 0:
        return
    total += json.len
    #var t0 = now()
    for msg in json:
        let id = msg["id"].getStr
        lastId = id
        #let t1 = msg["timestamp"].getStr.timestampToDateTime
        #assert t1 < t0
        #t0 = t1
        let
            kind = msg["type"].getInt
            user = msg["author"]
        if kind != 0:
            continue
        if user["id"].getStr == userId:
            res.add id.toId
        if doCopy:
            let
                date = msg["timestamp"].getStr.timestampToDateTime.format("dd'.'MM'.'yy, HH:mm")
                name = user["username"].getStr
                content = msg["content"].getStr
            copyBuf.add fmt"> {name}, {date}: {content}{'\n'}"
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
    #assert ids.deduplicate.len == ids.len

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

proc initCopy(path: string) =
    require not path.fileExists, "out file exists"
    copyBuf = @[]

proc finalizeCopy(path: string) =
    echo "finalizing copy..."
    copyBuf.reverse
    let s = openFileStream(path, fmWrite)
    for line in copyBuf:
        s.writeLine line
    s.close()

proc main =
    setStdIoUnbuffered()

    var
        opt = initOptParser(shortNoVal={'n'})
        chanId, auth: string
        optNoDelete: bool
        optOut: string
    while true:
        opt.next()
        case opt.kind
        of cmdEnd: break
        of cmdShortOption:
            if opt.key == "c":
                chanId = opt.val
            if opt.key == "a":
                auth = opt.val
            if opt.key == "n":
                optNoDelete = true
        of cmdLongOption:
            if opt.key == "out":
                optOut = opt.val
        of cmdArgument:
            discard
    require chanId.len > 0, "no chan id"
    require auth.len > 0, "no auth token"

    let
        channel = channels/chanId
        client = newHttpClient()
    client.headers.add "authorization", auth

    let
        (userId, userName) = getUser(client)
        chanName = getChannelName(client, channel)
    echo fmt"processing DM ({userName}, {chanName})"
    if not prompt("continue?"):
        return

    let doCopy = optOut.len > 0
    if doCopy:
        initCopy optOut
    var
        ids: seq[Id]
        lastId: string
        total: int
    echo ""
    while getMessageIds(client, channel, userId, lastId, total, ids, doCopy):
        stdout.eraseLine
        stdout.write fmt"processed over {total} ({ids.len}) messages so far..."
    echo ""
    if doCopy:
        finalizeCopy optOut

    echo fmt"{ids.len} messages found"
    if optNoDelete:
        echo "skipping deletion"
    else:
        if not prompt("are you sure you want to delete them?"):
            return
        deleteMessages client, channel, ids
    echo "done"

main()
