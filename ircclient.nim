import strutils, asyncnet, asyncdispatch
include ircconstants

const CR = chr(0x0d)
const LF = chr(0x0a)
#const SPACE = chr(0x20)
#const MAX_COMMAND_LENGTH = 512

type
  IrcClientBase = object
    socket: AsyncSocket
    address: string
    port: int
    nick: string
    userName: string
    realName: string
    serverPass: string
    status: IrcClientStatus

  IrcClient* = ref IrcClientBase

  ParsedMessage = tuple
    prefix: string
    command: string
    args: seq[string]

  IrcClientStatus* = enum
    disconnected
    connecting
    connected
    registered

proc parsemsg(msg: string): ParsedMessage =
    #Breaks a message from an IRC server into its prefix, command, and arguments
    result.prefix = ""
    var trailing = ""
    var s = msg
    if s == nil:
        echo "Nil or empty line."
    if s[0] == ':':
      var tmp = s[1..s.high].split(' ', 1)
      result.prefix = tmp[0]
      s = tmp[1]
    if s.find(" :") != -1:
      var tmp = s.split(" :", 1)
      s = tmp[0]
      trailing = tmp[1]
      result.args = s.split()
      result.args.add(trailing)
    else:
      result.args = s.split()
    result.command = result.args[0]
    result.args = result.args[1..result.args.high]

proc send(client: IrcClient, msg: string) {.async.} =
  await client.socket.send(msg & CR & LF)

proc sendPass*(client: IrcClient) =
  asyncCheck client.send("PASS " & client.serverPass)

proc sendNick*(client: IrcClient) =
  asyncCheck client.send("NICK " & client.nick)

proc sendUser*(client: IrcClient) =
  asyncCheck client.send("USER $1 * 0 : $2" % [client.userName, client.realName])

proc sendPong(client: IrcClient, servers: string) =
  asyncCheck client.send("PONG " & servers)

proc newIrcClient*(nick: string, serverPass: string = "", address: string, port: int=6667): IrcClient =
  new result
  result.socket = newAsyncSocket()
  result.address = address
  result.nick = nick
  result.realName = "nimBotty"
  result.userName = "nimBotty"
  result.serverPass = "serverPass"
  result.port = port
  result.status = IrcClientStatus.disconnected

proc isNumericCommand(command: string): bool =
    if len(command) != 3:
      result = false
    for i in 0..2:
      if not (command[i] in {'0'..'9'}):
        return false
    return true

proc processMessage(client: IrcClient, msg: ParsedMessage) =
  case msg.command
  of "NOTICE":
    echo "$1: $2" % [msg.prefix, msg.args[1]]
  of "PING":
    sendPong(client, join(msg.args, " "))
  of RPL_WELCOME:
    #just echo the welcome message
    echo "$1: $2" % [msg.prefix, msg.args[1]]
  of RPL_YOURHOST:
    echo "$1: $2" % [msg.prefix, msg.args[1]]
  of RPL_CREATED:
    echo "$1: $2" % [msg.prefix, msg.args[1]]
  else:
    echo "unknown command \"$1\"" % [msg.command]

proc aconnect(client: IrcClient){.async.} =
   echo "Connecting to ", client.address
   client.status = IrcClientStatus.connecting
   await client.socket.connect(client.address, Port(client.port))
   client.status = IrcClientStatus.connected
   echo "Connected!"
   client.sendPass()
   client.sendNick()
   client.sendUser()
   while true:
     let line = await client.socket.recvLine()
     if line == "":
          echo("Disconnected")
          break
     let parsed = parsemsg(line)
     #echo line
     echo "Prefix: $1, Command: $2, Args: $3" % [parsed.prefix, parsed.command, repr(parsed.args)]
     #if parsed.command.isNumericCommand():
     echo "COMMAND: ", parsed.command
     client.processMessage(parsed)

proc connect*(client: IrcClient) =
  asyncCheck client.aconnect()

if isMainModule:
  #echo repr(parsemsg(":test!~test@test.com PRIVMSG #channel :Hi!"))
  var client = newIrcClient(nick="nimBotty", address="chat.freenode.net")
  client.connect()
  runForever()
