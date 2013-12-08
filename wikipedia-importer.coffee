fs = require 'fs'
lazy = require 'lazy'

MongoClient = require('mongodb').MongoClient

from64 = (data) ->
    return new Buffer(data, 'base64').toString('utf8')

MongoClient.connect 'mongodb://127.0.0.1:27017/abookofmusic', (err, db) ->
    if err?
        console.log(err)
    else
        artists = db.collection('artists')
        albums = db.collection('albums')
        songs = db.collection('songs')
        new lazy(fs.createReadStream('./wikipedia-parse.txt')).lines.forEach (_line) ->
            line = _line.toString().replace(/\n$/, '')
            if line.match(/ARTIST-([^-]*)/)
                artist = line.match(/ARTIST-([^-]*)/)[1]
                artists.insert {artist: from64(artist)}, (err, docs) ->
                    if err?
                        console.log(err)
            else if line.match(/ALBUM-([^-]+)-([^-]+)/)
                matches = line.match(/ALBUM-([^-]+)-([^-]+)/)
                title = from64(matches[1])
                artist = from64(matches[2])
                albums.insert {title: title, artist: artist}, (err, docs) ->
                    if err?
                        console.log(err)
            else if line.match(/SONG-([^-]+)-([^-]+)/)
                matches = line.match(/SONG-([^-]+)-([^-]+)/)
                title = from64(matches[1])
                artist = from64(matches[2])
                real_title = title.replace(/\s*\(.*song\)/i, "")
                songs.insert {title: title, real_title: real_title, artist: artist}, (err, docs) ->
                    if err?
                        console.log(err)

