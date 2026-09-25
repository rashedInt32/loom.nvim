if vim.g.loaded_loom then
  return
end
vim.g.loaded_loom = true

vim.api.nvim_create_user_command("Loom", function(args)
  local loom = require("loom")
  local sub = args.fargs[1]
  if sub == nil or sub == "toggle" then
    loom.toggle()
  elseif sub == "new" then
    loom.new_tab({ cmd = #args.fargs > 1 and table.concat(args.fargs, " ", 2) or nil })
  elseif sub == "vsplit" then
    loom.split("vertical", { cmd = #args.fargs > 1 and table.concat(args.fargs, " ", 2) or nil })
  elseif sub == "split" then
    loom.split("horizontal", { cmd = #args.fargs > 1 and table.concat(args.fargs, " ", 2) or nil })
  elseif sub == "session" then
    if args.fargs[2] then
      loom.session(args.fargs[2])
    else
      loom.pick_session()
    end
  else
    vim.notify("loom: unknown subcommand " .. sub, vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  desc = "loom floating terminal",
  complete = function(_, line)
    if #vim.split(line, "%s+") <= 2 then
      return { "toggle", "new", "vsplit", "split", "session" }
    end
    return {}
  end,
})
