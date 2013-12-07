_ = require 'underscore'
async = require 'async'
conf = require './conf'
express = require 'express'
glob = require 'glob'
path = require 'path'
passport = require 'passport'
Twit = require 'twit'
TwitterStrategy = require('passport-twitter').Strategy

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
    res.send 200, req.user.profile.username

port = process.env.PORT || 5000
app.listen port, ->
    console.log "Listening on " + port

