#!/usr/bin/coffee

http = require 'http'
util = require 'util'
xml2js = require 'xml2js'
url = 'http://rss.theweathernetwork.com/weather/caon0512'
link = 'http://www.theweathernetwork.com/weather/canada/ontario/ottawa'

http.get(url, (response) -> 
    parser = new xml2js.Parser()
    response.on 'data', (chunk) ->
        parser.parseString(chunk)
    parser.addListener 'end', (json) -> 
        displayWeather json
        console.log "Full details at #{link}"
).on 'error', (e) ->
    console.log "Error: #{e.message}"

displayWeather = (json) ->
    json.rss.channel[0].item.forEach (item) ->
        console.log item.title[0]
        console.log formatDescription item.description[0]
        console.log ""

# strip html tags, convert entities, indent
formatDescription = (desc) ->
    desc = desc.replace /<[^>]+>/gi, ""
    desc = desc.replace /&nbsp;/g, " "
    desc = desc.replace /&deg;/g, "˚"
    desc = desc.replace /\s+/g, " "
    desc = desc.replace /^|\n/g, "$&   "
