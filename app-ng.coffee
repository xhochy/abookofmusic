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
app.use express.cookieParser()
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
    res.render 'front', username: username

app.post '/renderbook', ensureAuth, (req, res) ->
    page = req.body.name
    username = req.user.profile.username
    shasum = crypto.createHash('sha1')
    shasum.update(username)
    shasum.update('boohbooh')
    userkey = username + '##' + shasum.digest('hex')
    temp.mkdir 'abookofmusic-', (err, dirpath) ->
        bookpath = path.join(dirpath, 'book.epub')
        fs.mkdirSync(path.join(dirpath, 'book'))
        fs.mkdirSync(path.join(dirpath, 'book', 'META-INF'))
        fs.mkdirSync(path.join(dirpath, 'book', 'OPS'))
        fs.mkdirSync(path.join(dirpath, 'book', 'OPS', 'images'))
        renderer = spawn('mw-render', ['--conf', ':en', '--output', bookpath, '--writer', 'epub', 'Spice Girls'])
        newfiles = {}
        renderer.on 'close', (code) ->
            if code != 0
                res.send 500, 'An error occurred during book retrieval'
            else
                # The epub is created, now read it and add the links
                console.log(bookpath)
                fs.createReadStream(bookpath).pipe(unzip.Parse()).on('entry', (entry) ->
                    console.log("next entry")
                    console.log(entry.path)
                    ps = new PullStream()
                    entry.pipe(ps)
                    ps.pull (err, data) ->
                        output = data
                        if entry.path.match(/\.xhtml/)
                            # Parse data with cheerio
                            doc = cheerio.load(output)
                            doc("span").each (i, elem) ->
                                # console.log(elem)
                                if elem.attribs? && elem.attribs.title == 'Wannabe (song)'
                                    console.log('WannaYeah')
                                    doc(elem).html('<a href="http://xhochy.com:5000/playsong?key=' + userkey + 'title=Wannabe&artist=Spice%20Girls">' +  doc(elem).text() + ' (&#9654;)</a>')
                                    console.log(doc(elem).html())
                            output = doc.html()
                        fs.writeFile path.join(dirpath, 'book', entry.path), output, (err) ->
                            console.log(err)
                            entry.autodrain()
                ).on 'close', ->
                    console.log("closing..")
                    proc = spawn('zip', ['-r', 'book.epub', '.'], cwd: path.join(dirpath, 'book'))
                    proc.on 'close', (code) ->
                        res.download( path.join(dirpath, 'book', 'book.epub'), 'book.epub')


port = process.env.PORT || 5000
app.listen port, ->
    console.log "Listening on " + port

