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
  },
  config = function(_, opts)
    require("i18n_goto").setup(opts)
  end,
}
```

