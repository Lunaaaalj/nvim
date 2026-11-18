-- neotest consumer: one sound when a test run finishes (`ok`, or `fail` if any
-- test failed). Registered in lua/plugins/neotest.lua as `consumers.sounds`.
--
-- `run` arms the consumer, so results that neotest loads from disk when you focus
-- a test file (which also arrive with partial = false) stay silent. `results`
-- arrives piecemeal while the run goes (partial = true) and once more at the end.
return function(client)
  local armed, failed = false, false

  client.listeners.run = function()
    armed, failed = true, false
  end

  client.listeners.results = function(_, results, partial)
    if not armed then return end
    for _, result in pairs(results) do
      if result.status == "failed" then failed = true end
    end
    if partial then return end
    armed = false
    local bad = failed
    vim.schedule(function() require("sounds").emit("tests", bad and "fail" or "ok") end)
  end

  return {}
end
