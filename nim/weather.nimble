# Package

version     = "0.1.0"
author      = "Glenn Jackman"
description = "Fetch current weather from various sources."
license     = "MIT"
srcDir      = "src"
bin         = @["weather"]

# Deps

requires "nim >= 1.0"
requires "FeedNim"

