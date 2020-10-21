import parseopt

proc usage(status: int) =
  echo """
foo
bar
"""
  quit(status)




type Opts* = object
  wttrin*: bool
  envcan*: bool
  accuw*: bool
  moon*: bool


proc parseCli*(): Opts =
  #result = Opts(false, false, false, false)
  for kind, key, val in getopt():
    case kind
      of cmdLongOption, cmdShortOption:
        case key
          of "help", "h": usage(QuitSuccess)
          of "W", "wttrin": result.wttrin = true
          of "E", "environmentcanada": result.envcan = true
          of "A", "accuweather": result.accuw = true
          of "M", "moon": result.moon = true
          else: usage(QuitFailure)
      else: discard

  # if none specified, show them all
  if not(result.envcan or result.accuw or result.wttrin or result.moon):
    result.envcan = true
    result.accuw = true
    result.wttrin = true
    result.moon = true
