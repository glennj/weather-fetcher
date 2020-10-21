#[
    Fetch weather from AccuWeather
]#

import os
import strformat
import strutils
import httpclient
import uri
import json
import times
from xdg import configHome

const Host = "http://dataservice.accuweather.com"
const CacheAge = 2 # hours

proc apiKey(): string =
  var file = configHome() / "accuWeather.apikey"
  file.readFile.strip


type AccuWeather* = object
  latitude: float
  longitude: float
  apiKey: string
  client: HttpClient

proc initAccuWeather*(lat, long: float): AccuWeather =
  result = AccuWeather(latitude: lat, longitude: long)
  result.apiKey = apiKey()
  result.client = newHttpClient()

############################################################
proc url(path: string, query: openArray[(string, string)]): Uri =
  result = parseUri(Host) / path ? query

proc getLocation(w: AccuWeather): JsonNode =
  var uri = url("/locations/v1/cities/geoposition/search", {
    "q": &"{w.latitude},{w.longitude}",
    "details": "false",
    "toplevel": "false",
    "language": "en-us",
    "apikey": w.apiKey,
  })
  var content = w.client.getContent $uri
  var json = parseJson content
  %* {
    "key": json["Key"],
    "name": json["LocalizedName"],
    "city": json["ParentCity"]["LocalizedName"],
  }

proc getWeather(w: AccuWeather, location: string): JsonNode =
  var uri = url(&"/currentconditions/v1/{location}", {
    "details": "true",
    "language": "en-us",
    "apikey": w.apiKey,
  })
  w.client.getContent($uri).parseJson

proc getHourly(w: AccuWeather, location: string): JsonNode =
  var uri = url(&"/forecasts/v1/hourly/12hour/{location}", {
    "details": "false",
    "metric": "true",
    "language": "en-us",
    "apikey": w.apiKey,
  })
  w.client.getContent($uri).parseJson

proc getForecast(w: AccuWeather, location: string): JsonNode =
  var uri = url(&"/forecasts/v1/daily/5day/{location}", {
    "details": "false",
    "metric": "true",
    "language": "en-us",
    "apikey": w.apiKey,
  })
  w.client.getContent($uri).parseJson

############################################################
# since AccuWeather limits the API calls, the weather data
# gets stashed. Determine if we already have fresh data
#
proc useCachedData(cacheFile: string): bool =
  if not fileExists cacheFile: return false
  let mtime = cacheFile.getLastModificationTime
  return (getTime() - mtime) < initDuration(hours = CacheAge)

proc getCachedData(w: AccuWeather): JsonNode =
  let cacheFile = configHome() / "accuWeather.json"

  if useCachedData(cacheFile):
    result = cacheFile.readFile.parseJson

  else:
    # go fetch it from the source
    let location = w.getLocation
    let locationKey = location["key"].getStr

    result = newJObject()
    result["location"] = location
    result["current"] = w.getWeather locationKey
    result["forecast"] = w.getForecast locationKey
    result["hourly"] = w.getHourly locationKey
    cacheFile.writeFile $result


############################################################
proc title(location: JsonNode): string =
  format "$1 - $2 - AccuWeather\n",
    location["name"].getStr,
    location["city"].getStr

proc formatTime(epochNode: JsonNode, withTime = false): string =
  let epoch = epochNode.getInt.fromUnix
  result = epoch.format("ddd d MMM UUUU")
  if withTime:
    result.add ", "
    let time = epoch.format("h:mm tt")
    result.add &"{time:>8}"

proc temperature(t: JsonNode): string =
  let temp = t["Value"].getFloat.toInt
  let unit = t["Unit"].getStr
  &"{temp:3d}°{unit}"

proc uv(weather: JsonNode): string =
  format "$1 or $2",
    weather["UVIndex"].getInt,
    weather["UVIndexText"].getStr

proc pressure(weather: JsonNode): string =
  format "$1 $2 and $3",
    weather{"Pressure", "Metric", "Value"}.getFloat,
    weather{"Pressure", "Metric", "Unit"}.getStr,
    weather{"PressureTendency", "LocalizedText"}.getStr

proc wind(weather: JsonNode): string =
  format "$1 $2 $3 gusts $4",
    weather{"Wind", "Direction", "Localized"}.getStr,
    weather{"Wind", "Speed", "Metric", "Value"}.getFloat,
    weather{"Wind", "Speed", "Metric", "Unit"}.getStr,
    weather{"WindGust", "Speed", "Metric", "Value"}.getFloat

############################################################
proc currentConditions(weather: JsonNode): string =
  result.add format("\nCurrent Conditions: $1 $2\n",
    weather["WeatherText"].getStr,
    temperature(weather{"Temperature", "Metric"})
  )

  result.add format("""
        Observed at: $1
        RealFeel®: $2
        Wind Chill: $3
        Relative Humidity: $4 %
        UV Index: $5
        Pressure: $6
        Wind: $7""",
    formatTime(weather["EpochTime"], true),
    temperature(weather{"RealFeelTemperature", "Metric"}),
    temperature(weather{"WindChillTemperature", "Metric"}),
    weather["RelativeHumidity"].getInt,
    uv(weather),
    pressure(weather),
    wind(weather)
  ).unindent.indent(2)

  result.add "\n" & weather["Link"].getStr & "\n"

############################################################
proc forecast(f: JsonNode): string =
  result.add format("\nForecast: $1\n",
    f{"Headline", "Text"}.getStr
  )
  for day in f["DailyForecasts"]:
    result.add format("  $1; Day: $2, high $3; Night: $4, low $5\n",
      formatTime(day["EpochDate"]),
      day{"Day", "IconPhrase"}.getStr,
      temperature(day{"Temperature", "Maximum"}),
      day{"Night", "IconPhrase"}.getStr,
      temperature(day{"Temperature", "Minimum"})
    )
  result.add f{"Headline", "Link"}.getStr & "\n"

############################################################
# "hfs" = hourly forcasts
proc hourly(hfs: JsonNode): string =
  result = "\nHourly Forecasts:\n"
  for hf in hfs:
    let time = hf["EpochDateTime"].getInt.fromUnix
    if time < getTime(): continue
    result.add format("  $1 - $2; POP $3; $4\n",
      formatTime(hf["EpochDateTime"], true),
      temperature(hf["Temperature"]),
      hf["PrecipitationProbability"].getInt,
      hf["IconPhrase"].getStr,
    )


############################################################
proc current*(w: AccuWeather): string =
  var json = w.getCachedData
  try:
    result.add title(json["location"])
    result.add currentConditions(json["current"][0])
    result.add hourly(json["hourly"])
    result.add forecast(json["forecast"])
  except KeyError as e:
    return &"Error: {e.msg}"

