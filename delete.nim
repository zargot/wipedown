# API: https://github.com/discordapp/discord-api-docs/tree/master/docs/resources

# TODO
# - rate limit: https://ptb.discordapp.com/developers/docs/topics/rate-limits

import
    algorithm, httpclient, json, os,
    sequtils, strformat, strutils, sugar,
    times

type
    Id = array[24, char]

const
    server = "https://discordapp.com/api/v6"
    channels = server/"channels"
    batchSize = 100

using
    id: Id
    str: string
    req: HttpClient
    res: Response

template checkStatus(res: Response) =
    if res.status != Http200:
        raise newException(Exception, res.status)

proc toId(str): Id =
    let n = min(result.sizeof, str.len)
    copyMem result[0].addr, str.cstring, n
    result[n] = '\0'

converter toStr(id): string =
    $id[0].unsafeAddr.cstring

proc getUser(req): auto =
    const me = "users/@me"
    let res = req.get me
    checkStatus res
    let
        user = res.body.parseJson
        id = user["id"].getStr.toId
        name = user["name"].getStr
    (id, name)

proc getMessageIds(req: HttpClient, channel, userId: string, lastId: var string): seq[Id] =
    echo "requesting more messages"
    let messages = channel/"messages"
    var params: string
    if lastId != "":
        params.add "before=" & lastId
    params.add "limit=" & $batchSize
    let
        query = messages / "?" & params.join("&")
        res = req.get query
    if res.status != Http200:
        raise newException(Exception, res.status)
    let json = res.body.parseJson

    echo "parsing {json.len} messages"
    var idTimes {.global.}: seq[tuple[i, time: int]]
    idTimes.setLen 0
    for msg in json:
        if msg["author"]["id"].getStr != userId:
            continue
        let
            timeStr = msg["timestamp"].getStr
            fmt = initTimeFormat "YYYY-MM-DD'T'HH:mm:ss.ffffffzzz"
            date = timeStr.parse(fmt, utc())
            time = date.toTime.toUnix
            id = msg["id"].getStr.toId
        result.add id
        idTimes.add (idTimes.len, time.int)
    idTimes.sort((a,b) => cmp(a.time, b.time))
    let first = idTimes[0].i
    lastId = result[first]

proc getChannelName(req; channel: string): string =
    let res = req.get channel
    checkStatus res
    res.body.parseJson()["name"].getStr

proc prompt(q: string): bool =
    echo q & " [y/N]"
    let yn = stdin.readLine
    case yn.normalize
    of "y", "yes":
        return true

proc main =
    let
        chanId = paramStr 1
        auth = paramStr 2
        channel = channels/chanId
        messages = channel/"messages"
        req = newHttpClient()
    req.headers.add "authorization", auth

    let
        (userId, userName) = getUser(req)
        chanName = getChannelName(req, channel)
    echo fmt"deleting messages from {userName} in {chanName}"
    if not prompt("continue?"):
        return

    var
        ids: seq[Id]
        lastId: string
    while true:
        let batch = getMessageIds(req, channel, userId, lastId)
        ids.add batch
        if batch.len < batchSize:
            break

    echo fmt"deleting {ids.len} messages"
    var n = 0
    for id in ids:
        let res = req.delete messages/id
        checkStatus res
        n.inc
        break
    echo fmt"result: {n} messages deleted"

main()
