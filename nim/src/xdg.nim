import os

proc configHome*(): string =
  if existsEnv("XDG_CONFIG_HOME"):
    getEnv("XDG_CONFIG_HOME")
  else:
    getEnv("HOME") / ".config"

