<p align="center">
  <img width="300" alt="Codeium" src="codeium.svg"/>
</p>

---

[![Discord](https://img.shields.io/discord/1027685395649015980?label=community&color=5865F2&logo=discord&logoColor=FFFFFF)](https://discord.gg/3XFf78nAx5)
[![Twitter Follow](https://img.shields.io/badge/style--blue?style=social&logo=twitter&label=Follow%20%40codeiumdev)](https://twitter.com/intent/follow?screen_name=codeiumdev)
![License](https://img.shields.io/github/license/Exafunction/codeium.nvim)
[![Docs](https://img.shields.io/badge/Codeium%20Docs-09B6A2)](https://docs.codeium.com)
[![Canny Board](https://img.shields.io/badge/Feature%20Requests-6b69ff)](https://codeium.canny.io/feature-requests/)
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

To use Codeium Chat, execute the `:Codeium Chat` command. The chat will be opened
in your default browser using the xdg-open command.

## Options

- `config_path`: the path to the config file, used to store the API key.
- `bin_path`: the path to the directory where the Codeium server will be downloaded to.
- `api`: information about the API server to use:
  - `host`: the hostname. Example: `"codeium.example.com"`. Required when using enterprise mode
  - `port`: the port. Defaults to `443`
  - `path`: the path prefix to the API server. Default for enterprise: `"/_route/api_server"`
  - `portal_url`: the portal URL to use (for enterprise mode). Defaults to `host:port`
- `enterprise_mode`: enable enterprise mode
- `detect_proxy`: enable or disable proxy detection
- `enable_chat`: enable chat functionality
- `workspace_root`:
  - `use_lsp`: Use Neovim's LSP support to find the workspace root, if possible.
  -	`paths`: paths to files that indicate a workspace root when not using the LSP support
  - `find_root`: An optional function that the plugin will call to find the workspace root.
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

If you are seeing the `codeium` source as unused in `:CmpStatus`, make sure that `nvim-cmp` setup happens before the `codeium.nvim` setup.

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

### Workspace Root Directory

The plugin uses a few techniques to find the workspace root directory, which helps to inform the autocomplete and chat context. 

1. Call the optional `workspace_root.find_root` function, if provided. This is described below.
2. Query Neovim's built-in LSP support for the workspace root, if `workspace_root.use_lsp` is not set to `false`.
3. Search upward in the filesystem for a file or directory in `workspace_root.paths` that indicates a workspace root.

The default configuration is:

```lua
require('codeium').setup({
	workspace_root = {
		use_lsp = true,
		find_root = nil,
		paths = {
			".bzr",
			".git",
			".hg",
			".svn",
			"_FOSSIL_",
			"package.json",
		}
	}
})
```

The `find_root` function can help the plugin find the workspace root when you are not using Neovim's built-in LSP
provider. For example, this snippet calls into `coc.nvim` to find the workspace root.

```lua
require('codeium').setup({
	workspace_root = {
		find_root = function()
			return vim.fn.CocAction("currentWorkspacePath")
		end
	}
})
```



## Troubleshooting

The plugin log is written to `~/.cache/nvim/codeium/codeium.log`.

You can set the logging level to one of `trace`, `debug`, `info`, `warn`,
`error` by exporting the `DEBUG_CODEIUM` environment variable.

## Credits

This plugin was initially developed by [@jcdickinson](https://github.com/jcdickinson).
