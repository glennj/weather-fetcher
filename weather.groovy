#!/usr/bin/env groovyclient
@Grab('org.ccil.cowan.tagsoup:tagsoup:1.2') 
import org.ccil.cowan.tagsoup.Parser as TagsoupParser
@Grab('org.yaml:snakeyaml:1.17')
import org.yaml.snakeyaml.Yaml

import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/* ********************************************************************* */
class Weather {
    static main(args) {
        def opts = parseArgs(args)
        printWeather(opts.e, opts.a, opts.w)
    }

    static parseArgs(args) {
        def cli = new CliBuilder(
            usage: "weather [-options]",
            header: "Fetch weather information from various sources",
            footer: "If no options are given, show weather from all sources",
            stopAtNonOption: false,   // allow invalid options to be handled
        )
        cli.e('show weather from Environment Canada')
        cli.a('show weather from AccuWeather')
        cli.w('show weather from http://Wttr.In')
        cli.h(longOpt: 'help', 'show help')
        def opts = cli.parse(args)
        if (! opts) { // invalid option given
            System.exit(1)
        }
        else if (opts.h) {
            cli.usage()
            System.exit(0)
        }
        return opts
    }

    static printWeather(doEC, doAW, doWI) {
        // always do this
        println getEnvironmentCanadaAlerts()
        println '------------------------------------------------------------'

        def all = !(doEC || doAW || doWI)
        if (all || doEC) {
            println getEnvironmentCanada()
            println '------------------------------------------------------------'
        }
        if (all || doAW) {
            println getAccuWeather()
            println '------------------------------------------------------------'
        }
        if (all || doWI) {
            println getWttrIn()
            println '------------------------------------------------------------'
        }
    }

    static getEnvironmentCanadaAlerts() {
        new EnvironmentCanadaAlertFetcher(
            rssUrl: 'https://www.weather.gc.ca/rss/warning/on-118_e.xml'
        ).getAlert()
    }

    static getEnvironmentCanada() {
        new EnvironmentCanadaFetcher( 
            rssUrl: 'https://weather.gc.ca/rss/city/on-118_e.xml',
            link:   'https://weather.gc.ca/city/pages/on-118_metric_e.html',
        ).getWeather()
    }

    // this one appears to be out of date
    static getWeatherNetwork() {
        new WeatherNetworkFetcher(
            rssUrl: 'http://rss.theweathernetwork.com/weather/caon0512',
            link:   'http://www.theweathernetwork.com/weather/canada/ontario/ottawa',
        ).getWeather()
    }

    static getAccuWeather() {
        new AccuWeatherFetcher( latitude: 45.370, longitude: -75.766 ).getWeather()
    }

    static getWttrIn() {
        // specify userAgent to force ANSI output from server, not HTML
        def extraHeaders = [requestProperties: ['User-Agent': 'curl']]
        def sb = new StringBuilder()
        sb += new URL("http://wttr.in/ottawa?T").getText(extraHeaders) + "\n"
        sb += new URL("http://wttr.in/Moon").getText(extraHeaders)
        return sb.toString()
    }
}

trait TextUtils {
    // ref: https://stackoverflow.com/a/10709585/7552
    def splitIntoLines(text, maxLineSize) {
        def words = text.split(/\s+/)
        def lines = ['']
        words.each { word ->
            def lastLine = (lines[-1] + ' ' + word).trim()
            if (lastLine.size() <= maxLineSize)
                // Change last line.
                lines[-1] = lastLine
            else
                // Add word as new line.
                lines << word
        }
        lines
    }

    def fold(text, lineLength=80) {
        splitIntoLines(text, lineLength).join("\n")
    }

    def indent(text, spaces="   ") {
        spaces + text.replaceAll("\\n", "\n$spaces")
    }
}

/* ********************************************************************* */
class RSSWeatherFetcher {
    def rssUrl
    def link
    def getXml() {
        assert rssUrl != null
        return new XmlParser().parse(rssUrl)
    }
    def html2text(html) {
        html.replaceAll("&nbsp;", " ")
            .replaceAll("&deg;" , "°")
            .replaceAll("\\s+"  , " ")
            .replaceAll("<br/>" , "\n")
            .replaceAll("<.+?>" , "")
            .replaceAll("\\n\\s+" , "\n")
    }
}

/* ********************************************************************* */
class WeatherNetworkFetcher extends RSSWeatherFetcher implements TextUtils {
    def getWeather() {
        def sb = new StringBuilder()
        def xml = getXml()
        xml.channel[0].item.each {item ->
            sb += item.title.text() + "\n"
            sb += indent(html2text( item.description.text() )) + "\n"
            sb += "\n"
        }
        sb += "Full details at ${link}" + "\n"
    }
}

/* ********************************************************************* */
class EnvironmentCanadaAlertParser implements TextUtils {
    def url

    def asText() {
        assert url != null
        
        def parser = new TagsoupParser()
        def slurper = new XmlSlurper(parser)
        def content = slurper.parse(url)
        def main = content.'**'.find {it.name() == "main"}
        def sb = new StringBuilder() 
        if (main) {
            def div = main.'**'.find {node -> 
                node.name() == "div" && 
                node.'@class'.list().find {it.text() == "col-xs-12"}
            }
            if (div) {
                div.p[0].childNodes().each {
                    def txt = fold(it.text())
                    if (it.name() == "strong" || it.name() == "b") {
                        txt = txt.toUpperCase()
                    }
                    if (txt) sb += "$txt\n"
                }
                div.ul.childNodes().each {sb += "* " + fold(it.text()) + "\n"}
                sb += "\n"
                sb += div.p[1].localText().collect {fold(it)}.join("\n") + "\n"
                sb += "\n${url}\n"
            }
        }
        return sb.toString()
    }
}

/* ********************************************************************* */
class EnvironmentCanadaAlertFetcher extends RSSWeatherFetcher implements TextUtils {
    def getAlert() {
        def sb = new StringBuilder()
        def xml = getXml()
        def e = xml.entry.first()
        //TODO what if no alerts?
        if (e) {
            sb += e.title.text() + "\n\n"
            sb += indent(fold(e.summary.text())) + "\n\n"
            def alert = new EnvironmentCanadaAlertParser( url: e.link[0].'@href' ).asText()
            sb += indent(alert)
        }
        return sb.toString()
    }
}

/* ********************************************************************* */
class EnvironmentCanadaFetcher extends RSSWeatherFetcher implements TextUtils {
    def cityCode
    def getWeather() {

        def sb = new StringBuilder()
        def xml = getXml()
        sb += xml.title.text() + "\n\n"
        xml.entry.each { 
            // handled by the EnvironmentCanadaAlertFetcher
            if (it.category.@term.contains( "Warnings and Watches" )) {
                return
            }
            sb += it.title.text()  + "\n"
            if (it.category.@term.contains( "Current Conditions" )) {
                sb += indent(html2text(it.summary.text())) + "\n"
            }
        }
        sb += "\n"
        sb += "Full details at ${link}"
        return sb.toString()
    }
}

/* ********************************************************************* */
class AccuWeatherFetcher {
    static host = "http://dataservice.accuweather.com"
    static dtf = DateTimeFormatter.ofPattern('E d MMM u, h:mm a')
    static deg = '°'
    static cacheAgeInHours = 3

    static ENV = System.getenv()
    static configDir = ENV['XDG_CONFIG_HOME'] ? ENV['XDG_CONFIG_HOME'] : "${ENV['HOME']}/.config"
    static cacheFile = "$configDir/accuWeather.yaml"
    static apiKeyFile = "$configDir/accuWeather.apikey"

    // expected to be set during construction
    def latitude
    def longitude

    // instance vars to be set
    private location
    private cachedData

    def getWeather() {
        assert latitude != null
        assert longitude != null

        getCachedData()
        def sb = new StringBuilder()
        sb += getLocation() + "\n\n"
        def alarms = getAlarms()
        if (alarms) {
            sb += alarms + "\n\n"
        }
        sb += getCurrentConditions() + "\n\n"
        sb += getForecast()
        storeCachedData()
        return sb.toString()
    }

    def getCachedData() {
        cachedData = [:]
        def file = new File(cacheFile)
        if (file.exists()) {
            def data = new Yaml().load( new FileInputStream(file) )
            assert data instanceof Map
            ['latitude', 'longitude', 'location', 'cachedData'].each { assert data.containsKey(it) }

            def observationTime = epoch2localTime(data.cachedData.observationTime)
            def age = Duration.between(observationTime, LocalDateTime.now()).abs()
            if (age < Duration.ofHours(cacheAgeInHours) &&
                data.latitude  == latitude && 
                data.longitude == longitude
            ) {
                location = data.location
                cachedData = data.cachedData
            }
        }
        return
    }

    def storeCachedData() {
        def structure = [
            'latitude': latitude,
            'longitude': longitude,
            'location': location,
            'cachedData': cachedData,
        ]
        new Yaml().dump(structure, new FileWriter(new File(cacheFile)))
    }

    private getApiKey() {
        def file = new File(apiKeyFile)
        if (!file.exists()) {
            System.err.println "Error: ${apiKeyFile} does not exist."
            System.exit(1)
        }
        def apikey = file.getText().trim()
        return apikey
    }

    private fetchData(resource, query = [:]) {
        if (! query.containsKey("apikey")) { query.apikey = getApiKey() }
        if (! query.containsKey("lang"))   { query.lang   = 'en-us' }
        def uri = "${resource}?" + query.collect {"${it.key}=${it.value}"}.join("&")
        def conn = new URL(uri).openConnection()
        if (conn.responseCode != conn.HTTP_OK) {
            System.err.println "Error: cannot connect. code ${conn.responseCode}"
            System.err.println "     : Possibly too many API calls made in the last 24 hr"
            System.exit(1)
        }
        def data = new JsonSlurper().parse( conn.inputStream.newReader() )
        return data
    }

    private getLocation() {
        if (! location) {
            def resource = "$host/locations/v1/cities/geoposition/search"
            def data = fetchData(resource, [q: "$latitude,$longitude"])
            location = [
                key: data.Key, 
                name: data.LocalizedName, 
                city: data.ParentCity.LocalizedName,
            ]
        }
        assert location.containsKey('key') && location.key != null
        return "${location.name} - ${location.city} - AccuWeather"
    }

    private getAlarms() {
        def sb = new StringBuilder()
        def data
        if (cachedData.containsKey('alarms')) {
            data = cachedData.alarms
        }
        else {
            def resource = "$host/alarms/v1/1day/${location.key}"
            data = fetchData(resource)
            cachedData.alarms = data
        }
        if (! data.isEmpty()) {
            sb += "\nAlarms:" + "\n"
            sb += data.toString()
        }
        return sb.toString()
    }
    
    private epoch2localTime(epoch) {
        return LocalDateTime.ofInstant(
            Instant.ofEpochSecond(epoch),
            ZoneId.systemDefault()
        )
    }
    private fmtTemp(info) {
        return "${info.Value}${deg}${info.Unit}"
    }

    private getCurrentConditions() {
        def sb = new StringBuilder()
        def data
        if (cachedData.containsKey('currentConditions')) {
            data = cachedData.currentConditions
        }
        else {
            def resource = "$host/currentconditions/v1/${location.key}"

            /* do we truly need an array of current conditions? sigh.
             * a groovy note, a list of maps, indexing the map key returns values for all maps:
             *     x=[[a:1,b:2],[a:3,b:4]]; x.a // => [1,3]     
             */
            data = fetchData(resource, [details: 'true']).first()
            cachedData.currentConditions = data
        }
        def observationTime = epoch2localTime(data.EpochTime)
        cachedData.observationTime = data.EpochTime

        sb += "Current Conditions: ${data.WeatherText} ${fmtTemp(data.Temperature.Metric)}" + "\n"
        sb += "   ${data.Link}" + "\n"
        sb += "   Observed at: ${observationTime.format(dtf)}" + "\n"
        sb += "   RelativeHumidity: ${data.RelativeHumidity}%" + "\n"
        sb += "   RealFeel®: ${fmtTemp(data.RealFeelTemperature.Metric)}" + "\n"
        sb += "   RealFeel® Shade: ${fmtTemp(data.RealFeelTemperatureShade.Metric)}" + "\n"
        sb += "   Apparent Temp: ${fmtTemp(data.ApparentTemperature.Metric)}" + "\n"
        sb += "   UV Index: ${data.UVIndex} or ${data.UVIndexText}" + "\n"
        sb += "   Cloud Cover: ${data.CloudCover}%" + "\n"
        sb += "   Pressure: ${data.Pressure.Metric.Value} ${data.Pressure.Metric.Unit} ${data.PressureTendency.LocalizedText}" + "\n"
        sb += "   Wind: ${data.Wind.Speed.Metric.Value} ${data.Wind.Speed.Metric.Unit} ${data.Wind.Direction.Localized}"
        return sb.toString()
    }

    private getForecast() {
        def sb = new StringBuilder()
        def data
        if (cachedData.containsKey('forecast')) {
            data = cachedData.forecast
        }
        else {
            def resource = "$host/forecasts/v1/daily/5day/${location.key}"
            data = fetchData(resource, [details: 'true', metric: 'true'])
            cachedData.forecast = data
        }

        sb += "\nForecast: ${data.Headline.Text}" + "\n"
        sb += "   ${data.Headline.Link}" + "\n"
        data.DailyForecasts.each { f ->
            def uv =  f.AirAndPollen?.findAll {it.Name == "UVIndex"}
            def air = f.AirAndPollen?.findAll {it.Name != "UVIndex"}
                        .collect {"${it.Name} ${it.Category}"}.join(", ") 
            sb += "\n"
            sb += "   ${epoch2localTime(f.EpochDate).format(dtf)}" + "\n"

            sb += "      Day: ${f.Day?.LongPhrase}" + "\n"
            def t = fmtTemp(f.Temperature?.Maximum)
            def p = f.Day?.PrecipitationProbability
            def sun = f.Sun?.Rise?.substring(11,16)
            def moon = f.Moon?.Rise?.substring(11,16)
            sb += "         Max $t; Precip $p%; Sunrise $sun; Moonrise $moon" + "\n"
            sb += "         UV Index: ${uv[0].Category}" + "\n"
            sb += "         Air: $air" + "\n"

            sb += "      Night: ${f.Night.LongPhrase}" + "\n"
            t = fmtTemp(f.Temperature?.Minimum)
            p = f.Night?.PrecipitationProbability
            sun = f.Sun?.Set?.substring(11,16)
            moon = f.Moon?.Set?.substring(11,16)
            sb += "         Min $t; Precip $p%; Sunset $sun; Moonset $moon" + "\n"
        }
        return sb.toString().trim()
    }
}
