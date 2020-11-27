#[
    Fetch weather from http://wttr.in
]#

import httpclient
import strformat

type WttrIn* = object
  city: string

const baseUrl = "http://wttr.in"

proc initWttrIn*(city: string): WttrIn = WttrIn(city: city)

proc url(w: WttrIn, uri: string): string = &"{baseUrl}/{uri}"

proc get(w: WttrIn, uri: string): string =
  let url = w.url uri
  var client = newHttpClient()
  client.headers = newHttpHeaders({"User-Agent": "curl"})
  var response = client.get(url)

  var code = response.code
  if code.is3xx: return "Wttr.in has moved: " & $code
  if code.is4xx: return "Wttr.in returned error: " & $code
  if code.is5xx: return "Wttr.in is currently down: " & $code

  return response.body

proc current*(w: WttrIn): string = w.get &"{w.city}?T"

proc moon*(w: WttrIn): string = w.get "Moon"

