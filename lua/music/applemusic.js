// Apple Music bridge for lua/music: `osascript -l JavaScript applemusic.js <cmd> [args]`.
// Every command prints one JSON line. Nothing may touch a Music property before
// running() is checked: any property access launches the app.

function trackInfo(t) {
  return {
    id: t.persistentID(),
    name: t.name(),
    artist: t.artist(),
    album: t.album(),
    duration: t.duration(),
  };
}

function poll(Music) {
  const out = {
    running: true,
    state: Music.playerState(), // "playing" | "paused" | "stopped" | ...
    volume: Music.soundVolume(),
    shuffle: Music.shuffleEnabled(),
    repeat: Music.songRepeat(), // "off" | "one" | "all"
  };
  if (out.state !== "stopped") {
    try {
      out.track = trackInfo(Music.currentTrack);
      out.position = Music.playerPosition();
    } catch (e) {
      // radio has no current track, only a stream title; with neither, Music
      // is between tracks (e.g. just after `play`) and the next poll fills in
      try {
        const title = Music.currentStreamTitle();
        if (title) out.track = { id: "stream", name: title, artist: "", album: "", duration: 0 };
      } catch (e2) {}
    }
  }
  return out;
}

const QUEUE = "Neovim Queue";

// The playlist that stands in for a queue: Music has no scriptable Up Next and
// no "play album", so albums/artists/queued songs are copied here in order.
function queuePlaylist(Music, create) {
  const found = Music.userPlaylists.whose({ name: QUEUE });
  if (found.length > 0) return found[0];
  if (!create) return null;
  Music.make({ new: "playlist", withProperties: { name: QUEUE } });
  return Music.userPlaylists.whose({ name: QUEUE })[0];
}

function playlistById(Music, id) {
  if (id === "library") return Music.libraryPlaylists[0];
  if (id === "queue") return queuePlaylist(Music, true);
  return Music.playlists.whose({ persistentID: id })[0];
}

// Copy library tracks (persistent ids, in order) to the end of the queue.
// One whose() per id (~12 ms). Not a bulk persistentID() read + tracks[i]:
// the bulk read's order doesn't match element indexing, so that copies the
// wrong songs.
function enqueue(Music, ids) {
  const lib = Music.libraryPlaylists[0].tracks;
  const q = queuePlaylist(Music, true);
  const before = q.tracks.length;
  for (const id of ids) {
    const found = lib.whose({ persistentID: id });
    if (found.length > 0) Music.duplicate(found[0], { to: q });
  }
  return { q, before };
}

function run(argv) {
  const cmd = argv[0];
  const Music = Application("Music");
  try {
    if (!Music.running()) return JSON.stringify({ running: false });
    switch (cmd) {
      case "poll":
        break;
      case "playpause":
        Music.playpause();
        break;
      case "next":
        Music.nextTrack();
        break;
      case "prev":
        Music.backTrack(); // restarts the track if past its start, like the media key
        break;
      case "seek":
        Music.playerPosition = Math.max(0, Number(argv[1]));
        break;
      case "volume":
        Music.soundVolume = Math.min(100, Math.max(0, Number(argv[1])));
        break;
      case "shuffle":
        Music.shuffleEnabled = !Music.shuffleEnabled();
        break;
      case "repeat": {
        const next = { off: "all", all: "one", one: "off" };
        Music.songRepeat = next[Music.songRepeat()] || "off";
        break;
      }
      case "playlists": {
        const pls = Music.userPlaylists;
        const names = pls.name(), ids = pls.persistentID(), kinds = pls.specialKind();
        const out = [];
        for (let i = 0; i < names.length; i++) {
          if (kinds[i] === "folder") continue;
          // the first song stands in for a cover (playlists have no art of their own)
          let first = null;
          try {
            const t = pls[i].tracks;
            if (t.length > 0) first = t[0].persistentID();
          } catch (e) {}
          out.push({ id: ids[i], name: names[i], kind: kinds[i], first: first });
        }
        // the special "Music" playlist already is the whole library
        if (!kinds.includes("Music")) out.unshift({ id: "library", name: "Library", kind: "library" });
        return JSON.stringify(out);
      }
      case "tracks": {
        // listing the queue must not create it
        const pl = argv[1] === "queue" ? queuePlaylist(Music, false) : playlistById(Music, argv[1]);
        if (!pl) return "[]";
        // bulk property reads: one Apple Event per field, not per track
        const tr = pl.tracks;
        const ids = tr.persistentID(), names = tr.name(), artists = tr.artist(), albums = tr.album(), durs = tr.duration();
        const out = [];
        for (let i = 0; i < ids.length; i++) {
          out.push({ id: ids[i], name: names[i], artist: artists[i], album: albums[i], duration: durs[i] });
        }
        return JSON.stringify(out);
      }
      case "library": {
        const tr = Music.libraryPlaylists[0].tracks;
        const f = ["persistentID", "name", "artist", "albumArtist", "album", "duration", "trackNumber", "discNumber", "year"]
          .map((k) => tr[k]());
        const out = [];
        for (let i = 0; i < f[0].length; i++) {
          out.push({
            id: f[0][i], name: f[1][i], artist: f[2][i], album_artist: f[3][i], album: f[4][i],
            duration: f[5][i], track: f[6][i], disc: f[7][i], year: f[8][i],
          });
        }
        return JSON.stringify(out);
      }
      // queue_set <start index (1-based, 0 = don't play)> <ids...>: replace the queue
      case "queue_set": {
        const q = queuePlaylist(Music, true);
        if (q.tracks.length > 0) Music.delete(q.tracks);
        enqueue(Music, argv.slice(2));
        const start = Number(argv[1]);
        if (start > 0) Music.play(q.tracks[start - 1]);
        break;
      }
      // queue_add <ids...>: append; starts the queue when nothing is playing
      case "queue_add": {
        const { q, before } = enqueue(Music, argv.slice(1));
        if (Music.playerState() !== "playing" && q.tracks.length > before) Music.play(q.tracks[before]);
        break;
      }
      case "play": {
        // a track referenced through its playlist keeps playing that playlist
        const pl = playlistById(Music, argv[1]);
        if (argv[2]) Music.play(pl.tracks.whose({ persistentID: argv[2] })[0]);
        else Music.play(pl);
        break;
      }
      default:
        return JSON.stringify({ error: "unknown command: " + cmd });
    }
    return JSON.stringify(poll(Music));
  } catch (e) {
    return JSON.stringify({ error: String(e), number: e.errorNumber });
  }
}
