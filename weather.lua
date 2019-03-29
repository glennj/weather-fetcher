local curl  = require("cURL")            -- https://luarocks.org/modules/moteus/lua-curl
local json  = require("dkjson")          -- https://luarocks.org/modules/dhkolf/dkjson
local yaml  = require("lyaml")           -- https://luarocks.org/modules/gvvaughan/lyaml
local lfs   = require("lfs")             -- https://keplerproject.github.io/luafilesystem/
local cli   = require("cliargs")         -- https://luarocks.org/modules/amireh/lua_cliargs
local split = require("split")           -- https://luarocks.org/modules/telemachus/split
local feedparser = require("feedparser") -- https://luarocks.org/modules/slact/feedparser

-- pre-declare function
local getEnvironmentCanadaAlerts
local getEnvironmentCanadaWeather
local getAccuWeather
local wttrIn
local parseArgs

-- pre-declare classes
local RssFetcher
local EnvironmentCanadaAlert
local EnvironmentCanadaWeather
local AccuWeather

-- other stuff
local wrap
local indent
local formatTime
local separator
local html2text
local kvmap
local CONFIG_DIR = os.getenv('XDG_CONFIG_HOME') or
                  (os.getenv('HOME') .. "/.config")

------------------------------------------------------------------------
local main = function()
  local args = parseArgs()
  if args.e or args.a then
    getEnvironmentCanadaAlerts()
    separator()
  end
  if args.e then
    getEnvironmentCanadaWeather()
    separator()
  end
  if args.a then
    getAccuWeather()
    separator()
  end
  if args.w then
    wttrIn()
  end
end

parseArgs = function()
  cli:set_name("weather")
  cli:option("-e", "show weather from Environment Canada")
  cli:option("-a", "show weather from AccuWeather")
  cli:option("-w", "show weather from Wttr.In")

  local args, err = cli:parse(arg)
  if not args and err then
      print(err)
      os.exit(1)
  end

  if args.h then
    cli:print_help()
    os.exit()
  end

  if not (args.e or args.a or args.w) then
    args = {e = true, a = true, w = true}
  end
  return args
end

------------------------------------------------------------------------
-- TODO put the details in configuration

getEnvironmentCanadaAlerts = function()
  EnvironmentCanadaAlert({
      rssUrl = 'https://www.weather.gc.ca/rss/warning/on-118_e.xml',
  }):getAlert()
end

getEnvironmentCanadaWeather = function()
  EnvironmentCanadaWeather({
      rssUrl = 'https://weather.gc.ca/rss/city/on-118_e.xml',
      link   = 'https://weather.gc.ca/city/pages/on-118_metric_e.html',
  }):getWeather()
end

getAccuWeather = function()
  AccuWeather({ latitude  = 45.370, longitude = -75.766 }):getWeather()
end

wttrIn = function()
  -- default writer to stdout is OK
  local get = function(url)
    curl.easy({
      url = url,
      -- specify userAgent to force ANSI output from server, not HTML
      httpheader = { "User-Agent: curl" },
    }):perform():close()
  end
  get 'http://wttr.in/ottawa?T'
  print("")
  get 'http://wttr.in/Moon'
end

------------------------------------------------------------------------
RssFetcher = {}
RssFetcher.__index = RssFetcher
setmetatable(RssFetcher, {
  __call = function(cls, url)
    local self = setmetatable({}, cls)
    self:_init(url)
    return self
  end,
})

function RssFetcher:_init(url)
  self.rssUrl = url
end

function RssFetcher:getXML()
  assert(self.rssUrl)
  local xml = {}
  curl.easy({
    url = self.rssUrl,
    writefunction = function(a, b)
      local s = type(a) == 'string' and a or b
      xml[#xml+1] = s
      return #s
    end,
  }):perform():close()
  return table.concat(xml)
end

------------------------------------------------------------------------
EnvironmentCanadaAlert = {}
EnvironmentCanadaAlert.__index = EnvironmentCanadaAlert
setmetatable(EnvironmentCanadaAlert, {
  __index = RssFetcher,
  __call = function(cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function EnvironmentCanadaAlert:_init(params)
  assert(params.rssUrl)
  RssFetcher._init(self, params.rssUrl)
end

function EnvironmentCanadaAlert:getAlert()
  local xml = self:getXML()
  local parsed = feedparser.parse(xml, self.rssUrl)
  assert(parsed.entries and parsed.entries[1])
  local alert = parsed.entries[1]
  print(alert.title)
  print(indent(wrap(alert.summary)))
  print("\nFull details at " .. alert.links[1].href)
end

------------------------------------------------------------------------
EnvironmentCanadaWeather = {}
EnvironmentCanadaWeather.__index = EnvironmentCanadaWeather
setmetatable(EnvironmentCanadaWeather, {
  __index = RssFetcher,
  __call = function(cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function EnvironmentCanadaWeather:_init(params)
  assert(params.rssUrl)
  RssFetcher._init(self, params.rssUrl)
  self.link = params.link
end

function EnvironmentCanadaWeather:getWeather()
  local xml = self:getXML()
  local parsed = feedparser.parse(xml, self.rssUrl)
  assert(parsed)
  if not parsed.entries then
    print "Hmm, no weather outside"
    return
  end

  for _, e in ipairs(parsed.entries) do
    if e.category and not e.category:find("Warnings and Watches") then
    print(e.title)
    if e.category:find("Current Conditions") then
      print(indent(html2text(e.summary)))
    end
    end
  end
  print("\nFull details at " .. self.link)
end

------------------------------------------------------------------------
-- AccuWeather has limits on fetching. Cache the returned data
AccuWeather = {}
AccuWeather.__index = AccuWeather
setmetatable(AccuWeather, {
  --__index = RssFetcher,
  __call = function(cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function AccuWeather:_init(params)
  --assert(params.rssUrl)
  --RssFetcher._init(self, params.rssUrl)
  self.latitude = params.latitude
  self.longitude = params.longitude
  self.host = "http://dataservice.accuweather.com"
  self.cacheAgeInHours = 3
  self.cacheFile = CONFIG_DIR .. "/accuWeather.yaml"
  self.apikey = self:getApiKey()
  self.reqParams = {
    language = "en-us",
    details = "true",
    metric = "true"
  }
end

function AccuWeather:getWeather()
  self:getCachedData()

  self:getLocation()
  self:printLocation()

  self:getCurrentConditions()
  self:printCurrentConditions()

  self:getForecast()
  self:printForecast()

  self:storeCachedData()
end

function AccuWeather:getApiKey()
  local file = CONFIG_DIR .. "/accuWeather.apikey"
  local attrs = lfs.attributes(file); assert(attrs)
  local fh = io.open(file);           assert(fh)
  local apikey = fh:read('a')
  fh:close()
  assert(apikey)
  return apikey:trim()
end

function AccuWeather:getCachedData()
  local attrs = lfs.attributes(self.cacheFile)
  if attrs then
    local fh = io.open(self.cacheFile)
    assert(fh, "Can't open " .. self.cacheFile)
    local data = yaml.load(fh:read('a'))
    fh:close()
    assert(data, "Can't read " .. self.cacheFile)

    if data.cachedData then
      local age = math.abs(os.difftime(os.time(), data.cachedData.observationTime))
      if age < (self.cacheAgeInHours * 3600)
          and data.latitude  == self.latitude
          and data.longitude == self.longitude
      then
        self.cachedData = data.cachedData
      end
    end
    self.location = data.location
  end
end

function AccuWeather:fetchData(resource, query)
  query = query or {}
  query.apikey = self.apikey
  query.lang = 'en-us'

  local q = kvmap(query, function(k,v) return k.."="..v end)
  local uri = resource .. "?" .. table.concat(q, "&")

  local jsn = {}
  curl.easy({
    url = uri,
    writefunction = function(a, b)
      local s = type(a) == 'string' and a or b
      jsn[#jsn+1] = s
      return #s
    end,
  }):perform():close()

  return json.decode(table.concat(jsn))
end

function AccuWeather:getLocation()
  if not self.location then
    local resource = self.host .. "/locations/v1/cities/geoposition/search"
    local data = self:fetchData(resource, {q = self.latitude .. "," .. self.longitude})
    self.location = {
      key = data.Key,
      name = data.LocalizedName,
      city = data.ParentCity.LocalizedName,
    }
  end
  assert(self.location.key)
end

function AccuWeather:printLocation()
  print(("%s - %s - AccuWeather"):format(self.location.name, self.location.city))
end

function AccuWeather:getCurrentConditions()
  if not (self.cachedData and self.cachedData.currentConditions) then
    local resource = self.host .. "/currentconditions/v1/" .. self.location.key
    local data = self:fetchData(resource, self.reqParams)
    assert(data and data[1])
    self.cachedData = self.cachedData or {}
    self.cachedData.currentConditions = data[1]
    self.cachedData.observationTime = data[1].EpochTime
  end
end

function AccuWeather:fmtTemp (temp)
  return ("%s°%s"):format(temp.Value, temp.Unit)
end

function AccuWeather:printCurrentConditions()
  local data = self.cachedData.currentConditions

  print(("\nCurrent Conditions: %s %s"):format(
      data.WeatherText,
      self:fmtTemp(data.Temperature.Metric)
  ))
  print("   " .. data.Link)
  print("   Observed at: " .. formatTime(data.EpochTime))
  print("   RelativeHumidity: ".. data.RelativeHumidity .."%")
  print("   RealFeel®: ".. self:fmtTemp(data.RealFeelTemperature.Metric))
  print("   RealFeel® Shade: ".. self:fmtTemp(data.RealFeelTemperatureShade.Metric))
  print("   Apparent Temp: ".. self:fmtTemp(data.ApparentTemperature.Metric))
  print("   UV Index: ".. (data.UVIndex or data.UVIndexText))
  print("   Cloud Cover: ".. data.CloudCover .."%")
  print(("   Pressure: %s %s %s"):format(
      data.Pressure.Metric.Value,
      data.Pressure.Metric.Unit,
      data.PressureTendency.LocalizedText
  ))
  print(("   Wind: %s %s %s"):format(
      data.Wind.Speed.Metric.Value,
      data.Wind.Speed.Metric.Unit,
      data.Wind.Direction.Localized
  ))
end

function AccuWeather:getForecast()
  if not self.cachedData.forecast then
    local resource = self.host .. "/forecasts/v1/daily/5day/" .. self.location.key
    local data = self:fetchData(resource, self.reqParams)
    assert(data)
    self.cachedData.forecast = data
  end
end

function AccuWeather:printForecast()
  local data = self.cachedData.forecast
  print("\nForecast: " .. data.Headline.Text)
  print("   " .. data.Headline.Link)
  for _,forecast in ipairs(data.DailyForecasts) do
    self:printDailyForecast(forecast)
  end
end

function AccuWeather:printDailyForecast(f)
  print("\n   " .. formatTime(f.EpochDate))
  print("      Day: " .. f.Day.LongPhrase)
  print(("        Max %s; Precip %s; Sunrise %s; Moonrise %s"):format(
      self:fmtTemp(f.Temperature.Maximum),
      f.Day.PrecipitationProbability,
      f.Sun.Rise:sub(12, 16),
      f.Moon.Rise:sub(12, 16)
  ))

  if f.AirAndPollen then
    local air = {}
    for _,item in ipairs(f.AirAndPollen) do
      if item.Name == "UVIndex" then
        print((" "):rep(9) .. "UV Index: " .. item.Category)
      else
        air[#air+1] = item.Name .." ".. item.Category
      end
    end
    if #air > 0 then
      print((" "):rep(9) .. "Air: " .. table.concat(air, ", "))
    end
  end

  print("      Night: " .. f.Night.LongPhrase)
  print(("        Min %s; Precip %s; Sunset %s; Moonset %s"):format(
      self:fmtTemp(f.Temperature.Minimum),
      f.Night.PrecipitationProbability,
      f.Sun.Set:sub(12, 16),
      f.Moon.Set:sub(12, 16)
  ))
end

function AccuWeather:storeCachedData()
  local fh = io.open(self.cacheFile, "w")
  assert(fh)
  local err
  fh, err = fh:write(yaml.dump({ {
    location   = self.location,
    latitude   = self.latitude,
    longitude  = self.longitude,
    cachedData = self.cachedData,
  } }))
  assert(fh, err)
  fh:close()
end

------------------------------------------------------------------------
-- careful returning the result of gsub() --  you get the new
-- string AND the number of substitions

wrap = function(text, width)
  width = width or 80
  local words = split.split(text)
  local lines = {""}
  for _,word in ipairs(words) do
    local lastline = ("%s%s%s"):format(
        lines[#lines],
        (#lines[#lines] == 0 and "" or " "),
        word
    )
    if #lastline <= width then
      lines[#lines] = lastline
    else
      lines[#lines+1] = word
    end
  end
  return table.concat(lines, "\n")
end

indent = function(text, spaces)
  spaces = spaces or "   "
  local new = spaces .. text:gsub("\n *", "\n" .. spaces)
  return new
end

function formatTime(epoch)
  local datetime = os.date("%a %d %b %Y, %I:%M %p", (epoch))
      :gsub("%f[%S]0(%d)", "%1")                         -- no `%l`
      :gsub("[AP]M", function(pm) return pm:lower() end) -- no `%P`
  return datetime
end

html2text = function(html)
  local stripped = html
      :gsub("&nbsp;", " ")
      :gsub("&deg;" , "°")
      :gsub("%s+"   , " ")
      :gsub("%s+$"  ,  "")
      :gsub("<br/>" , "\n")
      :gsub("<[^>]+>", "")
  return stripped
end

separator = function()
  print(("\n%s"):format(("-"):rep(72)))
end

kvmap = function(table, func)
  local list = {}
  for key, val in pairs(table) do
    list[#list+1] = func(key, val)
  end
  return list
end

-- monkey patch string package
string.trim = function(s)
  local trimmed = s:gsub("^%s+", ""):gsub("%s+$", "")
  return trimmed
end

------------------------------------------------------------------------
main()
