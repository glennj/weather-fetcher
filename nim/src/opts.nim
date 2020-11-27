import parseopt, strutils

proc usage(status: int) =
  echo """
usage: weather [options]

where the options select the source(s)
      --accuweather
      --environmentcanada
      --wttrin
      --moon 

Specifying no options selects all of them.
Options can be specified with any prefix, such as `--acc`."""


  quit(status)




type Opts* = object
  wttrin*: bool
  envcan*: bool
  accuw*: bool
  moon*: bool


proc parseCli*(): Opts =
  for kind, key, val in getopt():
    let k = key.toLowerAscii
    case kind
      of cmdLongOption, cmdShortOption:
        if "environmentcanada".find(k) == 0:
          result.envcan = true
        elif "accuweather".find(k) == 0:
          result.accuw = true
        elif "wttrin".find(k) == 0:
          result.wttrin = true
        elif "moon".find(k) == 0:
          result.moon = true
        else:
          usage(QuitFailure)
      else: discard

  # if none specified, show them all
  if not(result.envcan or result.accuw or result.wttrin or result.moon):
    result.envcan = true
    result.accuw = true
    result.wttrin = true
    result.moon = true
