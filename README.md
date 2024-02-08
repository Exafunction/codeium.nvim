<p align="center">
  <img width="300" alt="Codeium" src="codeium.svg"/>
</p>

---

[![Discord](https://img.shields.io/discord/1027685395649015980?label=community&color=5865F2&logo=discord&logoColor=FFFFFF)](https://discord.gg/3XFf78nAx5)
[![Twitter Follow](https://img.shields.io/badge/style--blue?style=social&logo=twitter&label=Follow%20%40codeiumdev)](https://twitter.com/intent/follow?screen_name=codeiumdev)
![License](https://img.shields.io/github/license/Exafunction/codeium.nvim)
[![built with Codeium](https://codeium.com/badges/main)](https://codeium.com?repo_name=exafunction%2Fcodeium.nvim)

[![Visual Studio](https://img.shields.io/visual-studio-marketplace/i/Codeium.codeium?label=Visual%20Studio&logo=visualstudio)](https://marketplace.visualstudio.com/items?itemName=Codeium.codeium)
[![JetBrains](https://img.shields.io/jetbrains/plugin/d/20540?label=JetBrains)](https://plugins.jetbrains.com/plugin/20540-codeium/)
[![Open VSX](https://img.shields.io/open-vsx/dt/Codeium/codeium?label=Open%20VSX)](https://open-vsx.org/extension/Codeium/codeium)
[![Google Chrome](https://img.shields.io/chrome-web-store/users/hobjkcpmjhlegmobgonaagepfckjkceh?label=Google%20Chrome&logo=googlechrome&logoColor=FFFFFF)](https://chrome.google.com/webstore/detail/codeium/hobjkcpmjhlegmobgonaagepfckjkceh)

# codeium.nvim

Native [Codeium](https://www.codeium.com/) plugin for Neovim.

## Contributing

Feel free to create an issue/PR if you want to see anything else implemented.

## Screenshots

[Completion in Action](https://user-images.githubusercontent.com/522465/215312040-d5e91a6b-cffa-48f1-909f-360328b5af79.webm)

## Installation

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "Exafunction/codeium.nvim",
    requires = {
        "nvim-lua/plenary.nvim",
        "hrsh7th/nvim-cmp",
    },
    config = function()
        require("codeium").setup({
        })
    end
}
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "Exafunction/codeium.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "hrsh7th/nvim-cmp",
    },
    config = function()
        require("codeium").setup({
        })
    end
},
```

## Usage

After installation and configuration, you will need to authenticate with
Codeium. This can be done by running `:Codeium Auth`, copying the token from
your browser and pasting it into API token request.

## Options

- `config_path`: the path to the config file, used to store the API key.
- `bin_path`: the path to the directory where the Codeium server will be downloaded to.
- `api`: information about the API server to use:
  - `host`: the hostname
  - `port`: the port
- `tools`: paths to binaries used by the plugin:

  - `uname`: not needed on Windows, defaults given.
  - `uuidgen`
  - `curl`:
  - `gzip`: not needed on Windows, default implemenation given using powershell.exe Expand-Archive instead

  - `language_server`: The path to the language server downloaded from the [official source.](https://github.com/Exafunction/codeium/releases/tag/language-server-v1.1.32)

- `wrapper`: the path to a wrapper script/binary that is used to execute any
  binaries not listed under `tools`. This is primarily useful for NixOS, where
  a FHS wrapper can be used for the downloaded codeium server.

### [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)

After calling `setup`, this plugin will register a source in nvim-cmp. nvim-cmp
can then be set up to use this source using the `sources` configuration:

```lua
cmp.setup({
    -- ...
    sources = {
        -- ...
        { name = "codeium" }
    }
})
```

To set a symbol for codeium using lspkind, use the `Codeium` keyword. Example:

```lua
cmp.setup({
    -- ...
    formatting = {
        format = require('lspkind').cmp_format({
            mode = "symbol",
            maxwidth = 50,
            ellipsis_char = '...',
            symbol_map = { Codeium = "", }
        })
    }
})
```

## Troubleshooting

The plugin log is written to `~/.cache/nvim/codeium.log`.

You can set the logging level to one of `trace`, `debug`, `info`, `warn`,
`error` by exporting the `DEBUG_CODEIUM` environment variable.

## Credits

This plugin was initially developed by [@jcdickinson](https://github.com/jcdickinson).
