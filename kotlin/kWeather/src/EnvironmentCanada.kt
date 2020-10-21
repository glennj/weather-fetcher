package kWeather

class EnvironmentCanada(val rss: String, val link: String) {

    fun getWeather(): String {
        return "Weather from $rss, see $link"
    }
}
