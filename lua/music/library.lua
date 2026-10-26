-- Library data for the browser. Music can't be asked for albums or artists,
-- so one bulk dump of every track (~190 ms for 1.2k songs) is grouped here.
-- Cached for the session; R in the browser reloads.
local music = require("music")

local M = { loaded = false }

local QUEUE = "Neovim Queue" -- applemusic.js's stand-in for Up Next

local function lower(s) return (s or ""):lower() end
local function by_name(a, b) return lower(a.name) < lower(b.name) end

local function build(tracks)
  local by_id, albums, artists, album_of, artist_of = {}, {}, {}, {}, {}
  for _, t in ipairs(tracks) do
    by_id[t.id] = t
    local who = t.album_artist ~= "" and t.album_artist or t.artist
    if who == "" then who = "Unknown Artist" end
    local name = t.album ~= "" and t.album or "Unknown Album"
    local key = who .. "\0" .. name
    local al = album_of[key]
    if not al then
      al = { name = name, artist = who, year = 0, tracks = {} }
      album_of[key], albums[#albums + 1] = al, al
      local ar = artist_of[who]
      if not ar then
        ar = { name = who, albums = {}, tracks = {} }
        artist_of[who], artists[#artists + 1] = ar, ar
      end
      table.insert(ar.albums, al)
    end
    table.insert(al.tracks, t)
    if (t.year or 0) > 0 and al.year == 0 then al.year = t.year end
  end
  for _, al in ipairs(albums) do
    table.sort(al.tracks, function(a, b)
      if (a.disc or 0) ~= (b.disc or 0) then return (a.disc or 0) < (b.disc or 0) end
      if (a.track or 0) ~= (b.track or 0) then return (a.track or 0) < (b.track or 0) end
      return by_name(a, b)
    end)
  end
  for _, ar in ipairs(artists) do
    table.sort(ar.albums, function(a, b)
      if a.year ~= b.year then return a.year < b.year end
      return by_name(a, b)
    end)
    for _, al in ipairs(ar.albums) do vim.list_extend(ar.tracks, al.tracks) end
  end
  table.sort(albums, by_name)
  table.sort(artists, by_name)
  local songs = vim.list_slice(tracks)
  table.sort(songs, by_name)
  M.by_id, M.albums, M.artists, M.songs, M.album_of = by_id, albums, artists, songs, album_of
  M.loaded = true
end

function M.load(cb, force)
  if M.loaded and not force then return cb() end
  music.run({ "library" }, function(list)
    build(list)
    cb()
  end)
end

-- The album a track belongs to (for "reveal now playing").
function M.album(t)
  local who = t.album_artist ~= "" and t.album_artist or t.artist
  if who == "" then who = "Unknown Artist" end
  return M.album_of and M.album_of[who .. "\0" .. (t.album ~= "" and t.album or "Unknown Album")]
end

function M.playlists(cb)
  music.run({ "playlists" }, function(list)
    cb(vim.tbl_filter(function(p) return p.name ~= QUEUE end, list))
  end)
end

-- Songs of a playlist id ("queue" = the Neovim Queue, never cached).
local tracks_cache = {}
function M.tracks(id, cb)
  if id ~= "queue" and tracks_cache[id] then return cb(tracks_cache[id]) end
  music.run({ "tracks", id }, function(list)
    if id ~= "queue" then tracks_cache[id] = list end
    cb(list)
  end)
end

function M.reload(cb)
  tracks_cache = {}
  M.load(cb, true)
end

return M
