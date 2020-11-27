from os import `/`, existsEnv, getEnv

proc configHome*(): string =
  if existsEnv("XDG_CONFIG_HOME"):
    getEnv("XDG_CONFIG_HOME")
  else:
    getEnv("HOME") / ".config"

proc dataHome*(): string =
  if existsEnv("XDG_DATA_HOME"):
    getEnv("XDG_DATA_HOME")
  else:
    getEnv("HOME") / ".local" / "share"
