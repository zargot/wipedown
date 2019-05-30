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
# - rate limit: https://ptb.discordapp.com/developers/docs/topics/rate-limits

import
    httpclient, json,
    strformat, strutils,
    times

from os import paramStr, sleep

type
    Id = uint64

using
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

proc toStr(id: Id): string =
    $id

proc getUser(req): auto =
    const
        users = server/"users"
        me = users/"@me"
    let res = req.get me
    checkStatus res
    let
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

proc getMessageIds(req: HttpClient, channel, userId: string, lastId: var string,
                   res: var seq[Id]): bool =
    ## returns false when done
    let json = getMessages(req, channel, lastId)
    if json.len == 0:
        return
    #echo fmt"parsing {json.len} messages"
    for msg in json:
        let id = msg["id"].getStr
        lastId = id
        if msg["author"]["id"].getStr == userId:
            #echo "msg: ", msg["content"].getStr
            res.add id.toId
    json.len >= batchSize

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
        let res = req.delete messages/id.toStr
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
    while getMessageIds(req, channel, userId, lastId, ids):
        break
        #discard

    echo fmt"{ids.len} messages found"
    if not prompt("are you sure you want to delete them?"):
        return
    if true: quit 0
    deleteMessages req, channel, ids

main()
