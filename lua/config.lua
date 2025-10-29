local CFG = {
  scan_dirs = { "src/translations" },
  scan_glob = "**/*.json",
  patterns  = {
    "t%(%s*['\"]([%w%._%-]+)['\"]%s*%)",
    "%$t%(%s*['\"]([%w%._%-]+)['\"]%s*%)",
    "i18n%.t%(%s*['\"]([%w%._%-]+)['\"]%s*%)",
  },
}

return CFG
