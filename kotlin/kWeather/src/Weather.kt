package kWeather

fun main() {
    println("Hello")
    val ec = EnvironmentCanada(
        rss = "https://weather.gc.ca/rss/city/on-118_e.xml",
        link = "https://weather.gc.ca/city/pages/on-118_metric_e.html"
    )
    println(ec.getWeather())
}
