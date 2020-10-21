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
  return client.getContent(url)

proc current*(w: WttrIn): string = w.get &"{w.city}?T"

proc moon*(w: WttrIn): string = w.get "Moon"

