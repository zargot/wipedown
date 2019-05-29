# API: https://github.com/discordapp/discord-api-docs/tree/master/docs/resources

# TODO
# - rate limit: https://ptb.discordapp.com/developers/docs/topics/rate-limits

import
    algorithm, httpclient, json,
    sequtils, strformat, strutils, sugar,
    times

import os except `/`

type
    Id = uint64

using
    id: Id
    str: string
    req: HttpClient
    res: Response

func `/`(a, b: string): string =
    a & "/" & b

const
    server = "https://discordapp.com/api/v6"
    channels = server/"channels"
    batchSize = 100

proc require(cond: bool, err: string) =
    if not cond:
        raise newException(Exception, err)

template checkStatus(res: Response) =
    require res.status == Http200, res.status

proc toId(str): Id =
    str.parseUInt.uint64

converter toStr(id): string =
    $id

proc getUser(req): auto =
    const
        users = server/"users"
        me = users/"@me"
    let res = req.get me
    checkStatus res
    let
        user = res.body.parseJson
        id = user["id"].getStr.toId
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

proc timestampToUnix(s: string): int64 =
    let date = s.timestampToDateTime
    date.toTime.toUnix

proc getMessages(req: HttpClient, channel, lastId: string): JsonNode =
    #echo "requesting more messages"
    let messages = channel/"messages"
    var params: seq[string]
    if lastId != "":
        params.add "before=" & lastId
    params.add "limit=" & $batchSize
    let
        paramStr = "?" & params.join("&")
        query = messages & paramStr
    let res = req.get query
    checkStatus res
    res.body.parseJson

proc getMessageIds(req: HttpClient, channel, userId: string, lastId: var string):
        tuple[done: bool, ids: seq[Id]] =
    let json = getMessages(req, channel, lastId)
    echo fmt"parsing {json.len} messages"
    var
        ids {.global.}: seq[Id]
        idTimes {.global.}: seq[tuple[i: int, time: int64]]
    ids.setLen 0
    idTimes.setLen 0
    for msg in json:
        let
            timeStr = msg["timestamp"].getStr
            time = timeStr.timestampToUnix
            id = msg["id"].getStr.toId
        ids.add id
        idTimes.add (ids.high, time)
        if msg["author"]["id"].getStr == userId:
            #echo "msg: ", msg["content"].getStr
            result.ids.add id
    idTimes.sort((a,b) => cmp(a.time, b.time))
    let first = idTimes[0].i
    lastId = ids[first]
    if json.len < batchSize:
        result.done = true

proc getChannelName(req; channel: string): string =
    let res = req.get channel
    checkStatus res
    let json = res.body.parseJson()
    require json["type"].getInt == 1, "channel is not a DM"
    json["recipients"][0]["username"].getStr

proc prompt(q: string): bool =
    stdout.write q & " [y/N]"
    let yn = stdin.readLine
    case yn.normalize
    of "y", "yes":
        return true

proc deleteMessages(req; channel: string, ids: openArray[Id]) =
    echo fmt"deleting {ids.len} messages"
    let messages = channel/"messages"
    var n = 0
    for id in ids:
        let res = req.delete messages/id
        checkStatus res
        n.inc
        break
    echo fmt"result: {n} messages deleted"

proc main =
    let
        chanId = paramStr 1
        auth = paramStr 2
        channel = channels/chanId
        req = newHttpClient()
    req.headers.add "authorization", auth

    let
        (userId, userName) = getUser(req)
        chanName = getChannelName(req, channel)
    echo fmt"deleting messages from {userName} in DM with {chanName}"
    if not prompt("continue?"):
        return

    var
        ids: seq[Id]
        lastId: string
    #while true:
    for i in 0..3:
        let batch = getMessageIds(req, channel, userId, lastId)
        ids.add batch.ids
        if batch.done:
            break

    echo fmt"{ids.len} messages found"
    if not prompt("are you sure you want to delete them?"):
        return
    if true: quit 0
    deleteMessages req, channel, ids

main()
