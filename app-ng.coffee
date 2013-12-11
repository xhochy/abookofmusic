_ = require 'underscore'
async = require 'async'
conf = require './conf'
express = require 'express'
glob = require 'glob'
path = require 'path'
passport = require 'passport'
spawn = require('child_process').spawn
temp = require 'temp'
crypto = require 'crypto'
PullStream = require('pullstream')
unzip = require('unzip')
cheerio = require('cheerio')
fs = require('fs')
archiver = require('archiver')
TwitterStrategy = require('passport-twitter').Strategy
StringReader = require './stringreader.js'
passportSocketIo = require("passport.socketio")
MongoClient = require('mongodb').MongoClient

# Automatically track and cleanup files at exit
temp.track()

# ** PASSPORT **
# production callbackURL: http://tomawall.herokuapp.com/auth/twitter/callback
twitterStrategy = new TwitterStrategy conf.twitter, (token, tokenSecret, profile, done) ->
    user = {token: token, tokenSecret: tokenSecret, profile: profile}
    done null, user

passport.use twitterStrategy

passport.serializeUser (user, done) ->
    done null, JSON.stringify(user)

passport.deserializeUser (json, done) ->
    done null, JSON.parse(json)


# ** EXPRESS **
app = express()
server = require('http').createServer(app)
io = require('socket.io').listen(server)
app.use express.cookieParser(conf.sessionSecret)
app.use express.bodyParser()
app.use express.session({ secret: conf.sessionSecret })
app.use passport.initialize()
app.use passport.session()
app.use express.logger()
app.set 'views', __dirname + '/views'
app.set 'view engine', 'jade'
app.use express.static(path.join(__dirname, 'public'))

# ** LOGIN **

# Redirect the user to Twitter for authentication.  When complete, Twitter
# will redirect the user back to the application at
#   /auth/twitter/callback
app.get '/auth/twitter', passport.authenticate('twitter')

# Twitter will redirect the user to this URL after approval.  Finish the
# authentication process by attempting to obtain an access token.  If
# access was granted, the user will be logged in.  Otherwise,
# authentication has failed.
app.get '/auth/twitter/callback', passport.authenticate('twitter', { successRedirect: '/front', failureRedirect: '/login' })
app.get '/', (req, res) ->
    res.render 'index'

ensureAuth = (req, res, next) ->
    if req.isAuthenticated()
        next()
    else
        res.redirect '/auth/twitter'

app.get '/front', ensureAuth, (req, res) ->
    username = req.user.profile.username
    shasum = crypto.createHash('sha1')
    shasum.update(username)
    shasum.update(conf.sessionSecret)
    userkey = username + '%20' + shasum.digest('hex')
    res.render 'front', username: username, userkey: userkey, playhost: conf.playhost

app.post '/renderbook', ensureAuth, (req, res) ->
    page = req.body.pagetitle
    username = req.user.profile.username
    shasum = crypto.createHash('sha1')
    shasum.update(username)
    shasum.update(conf.sessionSecret)
    userkey = username + '%20' + shasum.digest('hex')
    console.log("Rendering " + page)
    temp.mkdir 'abookofmusic-', (err, dirpath) ->
        bookpath = path.join(dirpath, 'book.epub')
        fs.mkdirSync(path.join(dirpath, 'book'))
        fs.mkdirSync(path.join(dirpath, 'book', 'META-INF'))
        fs.mkdirSync(path.join(dirpath, 'book', 'OPS'))
        fs.mkdirSync(path.join(dirpath, 'book', 'OPS', 'images'))
        renderer = spawn('mw-render', ['--conf', ':en', '--output', bookpath, '--writer', 'epub', page])
        renderer.stdout.pipe(process.stdout)

        newfiles = {}
        renderer.on 'close', (code) ->
            if code != 0
                res.send 500, 'An error occurred during book retrieval'
            else
                # The epub is created, now read it and add the links
                console.log(bookpath)
                setTimeout( ->
                    console.log("Compressing")
                    proc = spawn('zip', ['-r', 'book.epub', '.'], cwd: path.join(dirpath, 'book'))
                    proc.on 'close', (code) ->
                        res.download( path.join(dirpath, 'book', 'book.epub'), 'book.epub')
                , 20000)
                fs.createReadStream(bookpath).pipe(unzip.Parse()).on('entry', (entry) ->
                    console.log("next entry")
                    console.log(entry.path)
                    ps = new PullStream()
                    entry.pipe(ps)
                    ps.pull (err, data) ->
                        output = data
                        if entry.path.match(/\.xhtml/)
                            entry.autodrain()
                            output = updateSongLinks output.toString(), userkey, (out) ->
                                fs.writeFile path.join(dirpath, 'book', entry.path), out, (err) ->
                                    if err?
                                        console.log(err)
                        else
                            entry.autodrain()
                            fs.writeFile path.join(dirpath, 'book', entry.path), output, (err) ->
                                if err?
                                    console.log(err)
                ).on 'close', ->
                    console.log("closing..")
## **socket.io**

sockets = {}
io.set('log level', 1)
io.sockets.on 'connection', (socket) ->
    socket.on 'register', (data) ->
        sockets[decodeURIComponent(data.key)] = socket
    socket.on 'disconnect', ->
        toDelete = []
        for k,v of sockets
            if v == socket
                toDelete.push(k)
        toDelete.forEach (k) ->
            delete sockets[k]

getSocketForReq = (req) ->
    if sockets[req.query.key]?
        return sockets[req.query.key]
    else if sockets[decodeURIComponent(req.query.key)]?
        return sockets[decodeURIComponent(req.query.key)]
    else
        return null

app.get '/playsong', (req, res) ->
    socket = getSocketForReq(req)
    if socket?
        socket.emit('playsong', title: req.query.title, artist: req.query.artist)
    res.render 'playsong', userkey: decodeURIComponent(decodeURIComponent(req.query.key))

app.get '/stop', (req, res) ->
    socket = getSocketForReq(req)
    if socket?
        socket.emit('stop')
    res.render 'playsong'

## **MongoDB**

mongodb = {}
song_coll = {}
MongoClient.connect 'mongodb://127.0.0.1:27017/abookofmusic', (err, db) ->
    if err?
        console.log(err)
    else
        mongodb = db
        song_coll = db.collection('songs')

updateSongElem = (userkey, doc, elem, cb) ->
    song_coll.findOne title: elem.attribs.title.toString(), (err, result) ->
        if err?
            console.log(err)
        if result?
            doc(elem).html('<a href="' + conf.playhost + 'playsong?key=' + encodeURIComponent(userkey) + '&title=' + encodeURIComponent(result.real_title) + '&artist=' + encodeURIComponent(result.artist) + '">' +  doc(elem).text() + ' (&#9654;)</a>')
        cb(null, doc)

updateSongLinks = (output, userkey, cb) ->
    # Parse data with cheerio
    doc = cheerio.load(output)
    elems = []
    doc("span").each (i, elem) ->
        if elem.attribs? && elem.attribs.title?
            console.log(elem.attribs.title)
            elems.push(elem)
    iter = _.partial(updateSongElem, userkey)
    async.reduce elems, doc, iter, (err, doc) ->
        console.log("book rendered")
        cb(doc.html())

port = process.env.PORT || 5000
server.listen port, ->
    console.log "Listening on " + port

