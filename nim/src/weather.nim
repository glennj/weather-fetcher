import posix
from strutils import repeat
import opts, wttrin, environmentCanada, accuWeather

proc horizRule() = echo "=".repeat(80)

proc hitEnter(msg = "to continue") =
  horizRule()
  stdout.write("Hit enter " & msg & ":")
  flushFile(stdout)
  discard stdin.readLine
  echo ""


proc main() =
  # suppress stacktrace on Ctrl+C
  onSignal(SIGINT): quit(0)

  let opts = parseCli()
  var count = 0

  var wttrIn: WttrIn
  if opts.wttrin or opts.moon:
    wttrIn = initWttrIn("ottawa")

  if opts.wttrin:
    echo wttrIn.current
    count.inc

  if opts.envcan:
    if count > 0: hitEnter("for Environment Canada")
    echo initEnvironmentCanada("on-118").current
    count.inc

  if opts.accuw:
    if count > 0: hitEnter("for AccuWeather")
    echo initAccuWeather(45.370, -75.766).current
    count.inc

  if opts.moon:
    if count > 0: hitEnter("for phase of moon")
    echo wttrIn.moon
    count.inc

main()
