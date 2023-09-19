# codeium.nvim

Native [Codeium](https://www.codeium.com/) plugin for Neovim

## Contributing

Feel free to create an issue/PR if you want to see anything else implemented.

## Screenshots

[Completion in Action](https://user-images.githubusercontent.com/522465/215312040-d5e91a6b-cffa-48f1-909f-360328b5af79.webm)

## Installation

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "jcdickinson/codeium.nvim",
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

#### Optional [http.nvim](https://github.com/jcdickinson/http.nvim) support

```lua
use {
    "jcdickinson/http.nvim",
    run = "cargo build --workspace --release"
}

use {
    "jcdickinson/codeium.nvim",
    requires = {
        "jcdickinson/http.nvim",
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
    "jcdickinson/codeium.nvim",
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

#### Optional [http.nvim](https://github.com/jcdickinson/http.nvim) support

```lua
{
    {
        "jcdickinson/http.nvim",
        build = "cargo build --workspace --release"
    },
    {
        "jcdickinson/codeium.nvim",
        dependencies = {
            "jcdickinson/http.nvim",
            "nvim-lua/plenary.nvim",
            "hrsh7th/nvim-cmp",
        },
        config = function()
            require("codeium").setup({
            })
        end
    }
}
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
  - `uuidgen`: not needed on Windows, default implemenation given.
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
