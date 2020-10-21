package weather

import java.net.URL


class EnvironmentCanada(val rss: String, link: String) {
    val rssUrl = URL(rss)
    val linkUrl = URL(link)

    fun getWeather(): String {
        return "here it is"
    }
}
