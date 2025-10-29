# i18n_goto.nvim

A small Neovim plugin for Vue/JS/TS projects that use JSON-based i18n files.

- Jump to translation keys (`<leader>ig`)
- Peek translations across locales (`<leader>ip`)
- Create missing keys (`<leader>ic`)
- Inline underline hint for missing locales

## 📦 Installation (Lazy.nvim)

```lua
{
  "eriklennstrom/i18n_goto.nvim",
  ft = { "vue", "javascript", "typescript", "javascriptreact", "typescriptreact" },
  opts = {
    scan_dirs = { "src/translations" },
    scan_glob = "**/*.json",
  },
  config = function(_, opts)
    require("i18n_goto").setup(opts)
  end,
  keys = {
    { "<leader>ig", function() require("i18n_goto").goto_definition() end, desc = "i18n: go to/create key" },
    { "<leader>ip", function() require("i18n_goto").peek_translation() end,  desc = "i18n: peek translation" },
    { "<leader>ic", function() require("i18n_goto").create_missing_translation() end, desc = "i18n: create missing" },
  },
}
```
