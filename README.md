# wpm.nvim

A dirt simple WPM counter for your interface needs in neovim.

## Contributing

Feel free to create an issue/PR if you want to see anything else implemented.

## Screenshots

![WPM and History Graph](./docs/wpm_and_history_graph.png)

## Installation

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "jcdickinson/wpm.nvim",
    config = function()
        require("wpm").setup({
        })
    end
}
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "jcdickinson/wpm.nvim",
    config = function()
        require("wpm").setup({
        })
    end
}
```

## Usage

This provides a few functions to use in other UI plugins, these functions are:

- `wpm`: return the current 80th (by default) percentile WPM
- `sorted_graph`: returns a sparkline graph of the historic WPM samples in
  ascending order.
- `historic_graph`: returns a sparkline graph of the historic WPM samples in
  chronological order.
- `samples`: return the historic samples in a table, in chronological order.
- `sorted_samples`: return the historic samples in a table, in ascending
  order.
- `historic_samples`: return the historic samples in a table, in
  chronological order.
- `wpm_at_sample`: returns the WPM at a given sample index.

### [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)

```lua
local wpm = require("wpm")
sections = {
    lualine_x = {
        wpm.wpm,
        wpm.historic_graph
    }
}
```

### Setup Options

The setup options can contain the following keys:

- `sample_count`: the number of samples to record. Default is `10`.
- `sample_interval`: the time between samples ms. Default is `2000`.
- `percentile`: the percentile to use for `wpm`. Expressed as a range between
  `0` and `1`. Defaults to `0.8`.
