# tfvc.nvim

tfvc.nvim is an unofficial plugin for integration of TeamFoundation verion
control, also known as TFS, referred to as 'tfvc' from here on.

It provides commands to checkout files, undo changes, add files, show status,
view history, compare pending changes and some others. Some commands of the TF
cli tool do not -and will not- have dedicated commands though.

The goal is to optimize the workflow around working with a tfvc repository using nvim.
Not to replace the commandline tool.

Tested on Windows 10/11 and TF Version 17.10.34824.3, although it'll probably
work with earlier versions.

## Requirements

This plugin depends on the TF executable bundled with Visual Studio.
It also depends on you having setup an active workspace with `TF.exe workspace`.

## Installation & Setup

Add this repository with your plugin-manager of choice. Here's Lazy:

```lua
  { 'mkwpaul/tfvc.nvim', dependencies = { 'nvim-lua/plenary.nvim', } },
```

Ensure that the parent directory of the TF.exe is listed in your PATH variable,
Either by appending the location of the executable manually or by running nvim
within Visual Studios's developer Shell profile. You can alternatively specify
the absolute path to the TF executable via the `executable_path` option.

As of writing the TF.exe can be found here:
`C:/Program Files/Microsoft Visual Studio/18/Professional/Common7/IDE/CommonExtensions/Microsoft/TeamFoundation/Team Explorer/TF.exe`
, assuming your Visual Studio installation is in its default location.

Different commands also require additional data, like the url to the
TeamFoundation server, or the local workfold-mapping, which can be inferred
automatically, but is better to be set manually.

Specifically, `version_control_web_url` and `workfold` are required for the
`:TF openWebHistory` command.

## Configuration

Every user-option can be either be set by setting `vim.g.tf_option = 'value'`,
setting `vim.g.tf.option = 'value'`, or by calling `require('tfvc').setup { option = 'value' }`

Note that calling `setup` isn't required to initialize this plugin, it just
merges the provided options table with `vim.g.tf`.

Options set as namespaced fields on vim.g have priority, so that setting them
interactively via something like `:let g:tf_diff_open_folds = v:false` is
easier.

---

`debug` verbose output for debugging. You should probably leave this unset.
Default is false.

`default_versionspec` Versionspec to use with commands when no versionspec is
specified, Default is 'T' which indicates to use the latest server version.

`diff_no_split` if true, then hide the buffer that is compared against, when
using TF diff, Default is false.

`diff_open_folds` if true, then don't collapse regions without changes, when
using TF diff Default is false.

`executable_path` Full path to the TF executable. If not set, the it will be
assumed that the tf executable is in the PATH. Only necessary when you can't
make the TF executable availible via PATH. Default to `TF`

`filter_status_by_cwd` When using TF status, only show changed files under the
current working directory Default to true, i.e. do filter by CWD.

`history_entry_limit` Number of entries to load in history buffers.
Default to 300 entries.

`history_open_cmd` command to use when navigating to `tfvc:///` paths via
commands, should be one of `edit`, `split`, `vsplit` etc. Default is `edit`

`output_encoding` if specified, use iconv to convert output from tf.exe from
the specified encoding to utf-8, value is passed as-is to iconv, so it should
be an encoding it understands

`version_control_web_url` this should look something like
`http://{host}/tfs/{collection}/{project}/_versionControl`

`workfold` The default workfold to use. Run `tf.exe workfold` to see what you
have configured with TF itself. If set, value must be table of type workfold,
i.e. it must have fields:
```
  --@type workfold
  vim.g.tf_workfold = {
    collection = 'http://zesrvtfs:8080/tfs/defaultcollection',
    localPath = 'C:/dev/tfs',
    serverPath = '$/MyProject',
  }
```
Required for `:TF openWebHistory` 

## Commands

:TF add
Adds the current file to TFS. 
Non-blocking equivalent to `:!tf add "%"

:TF checkout
Check out the current file from TFS.
Non-blocking equivalent to `:!tf checkout "%"`
Does not work with directories (for safetey).

:TF diff {version spec?}
Diffs the local version of the current file with a specific server version.
The versionspec is passed directly to the `tf view command.`

Tip:
To quickly review your pending changes bevor commiting, you can use :TF diff,
`:TF status` and `:TF loadDiffs` if you've got a slow server, in combination with
the quickfix list, the `:cnext` and `cprev` commands and |CTRL-W_o| to

First, run `:TF loadDiffs` to preload all server files.
Then open the changed files in telescope with `:TF status` and press `<C-q>` to
put the files into the quickfix list.

Then you can use `:cnext` followed by |CTRL-W_o| and `:TF diff` to view and diff
the next file.

:TF history
Open changelog (history) of the current file or directory in an interactive buffer.

:TF openWebHistory
Opens the history of the current file or directory in a browser.
Requires the `version_control_web_url` to be set during setup.
The |tfvc.workfold| should also be setup to avoid unnecessary queries.

:TF loadDiffs [version spec]
- Preloads a specific server version of all files with pending changes.

:TF status {all/in_cwd,fresh/cached}
Opens the quickfix list with all checked out files.
Optional flags: `all`, `cached`, `fresh`, `in_cwd` or their initials
- `in_cwd`: only show changed files under the current working directory. (default)
- `all`: opposite of `in_cwd` 
- `fresh` ignore cache for pending changes and query from TF.exe (default)
- `cached` load pending changes from cache if availible, otherwise query fresh

:TF undo
Undoes any pending changes in the current file.
Non-blocking equivalent to `:!tf undo "%"`
Does not work with directories (for safetey)

:TF info
Shows status of the current file or directory
Non-blocking equivalent to `:!tf info "%"`

:TF rename
Moves or renames a file or directory

:TF delete
 Deletes current file or directory
Non-blocking equivalent to `:!tf delete "%"`

## Keybinds
For default keybinds see `lua/tfvc/default_keymaps.lua`

You can disable default keymaps via `vim.g.tf_disable_default_keymaps = true`
Note that unlike other options, this must be set exactly like this, and must be
set before the plugin is loaded.

## Versionspec
Some commands require a file-version which can specified a number of ways.
The versionspec format is as follows (taken from the TF.exe help):

```
  Versionspec:
    Date/Time         D"any .NET Framework-supported format"
                      or any of the date formats of the local machine
    Changeset number  Cnnnnnn
    Label             Llabelname
    Latest version    T
    Workspace         Wworkspacename;workspaceowner
```

# Questions & Answers

- `How do I check in changes`?
Run `tf checkin` outside of nvim.
It will open a gui-tool. It has usable keyboard navigation and you need to use
it if you want to associate a specfic work item with your changeset as you
check in, as far as I can tell.

- `How to I get the latest changes from the tfvc server?`
Run `tf get . /recursive /noprompt` outside of nvim.
if you have conflicts you can run `tf resolve /noprompt /auto:[strat]
to resolve them.

- `How do I reload a serverFile or history buffer`
The same way you reload local files. With `:e!`

- `How do I use nvim to resolve merge conflicts?`
I don't know. You tell me, when you figure it out.
