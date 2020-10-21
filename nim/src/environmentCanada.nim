#[
    Fetch weather from Environment Canada
]#

import strutils
import strformat
import htmlparser
import xmltree
import FeedNim


type EnvironmentCanada* = object
  city: string
  lang: string

proc initEnvironmentCanada*(
    cityCode: string,
    lang: string = "e"
): EnvironmentCanada =
  result = EnvironmentCanada(city: cityCode, lang: lang)

proc rssUrl(w: EnvironmentCanada): string =
  &"https://weather.gc.ca/rss/city/{w.city}_{w.lang}.xml"

proc html2text(html: string): string =
  var node: XmlNode
  node = parseHtml(html)
  #try:
  #  node = parseHtml(html)
  #except AssertionError:
  #  return html
  if node.kind == xnText:
    return node.innerText
  for item in node.items:
    if item.kind == xnText:
      result.add $item
    elif item.kind == xnElement and item.tag != "br":
      result.add item.innerText


proc current*(w: EnvironmentCanada): string =
  var output: seq[string]
  let url = w.rssUrl
  let feed = url.getAtom
  var humanUrl = ""
  output.add feed.title.text & "\n"

  for entry in feed.entries:
    for category in entry.categories:
      output.add entry.title.text
      if category.term == "Current Conditions":
        output.add entry.summary.html2text.strip.indent(2) & "\n"
        humanUrl = entry.link.href
      if category.term == "Warnings and Watches":
        output.add entry.summary.html2text.strip.indent(2) & "\n"

  if humanUrl != "": output.add &"\nFull details as {humanUrl}"

  output.join("\n")
