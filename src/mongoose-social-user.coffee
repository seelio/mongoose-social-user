SocialReq = require('social-request')
async = require('async')

module.exports = (schema, options) ->
  throw new Error('No mongoose instance supplied, set options.mongoose in plugin definition') unless options?.mongoose?
  mongoose = options.mongoose
  SocialUserDataSchema = new mongoose.Schema
    _user: 
      type: mongoose.Schema.Types.ObjectId
      ref: options.userModel or 'User'
    facebook: 
      userData: {}
      contacts: Array
    twitter:
      userData: {}
      contacts: Array
    google:
      userData: {}
      contacts: Array
    googleplus:
      userData: {}
      contacts: Array
  if mongoose.models.SocialUserData
    SocialUserData = mongoose.models.SocialUserData
  else
    SocialUserData = mongoose.model('SocialUserData', SocialUserDataSchema)

  socialReq = new SocialReq()
  socialReq
    .use('google', {clientId: options.google.clientId, clientSecret: options.google.clientSecret})
    .use('googleplus', {clientId: options.google.clientId, clientSecret: options.google.clientSecret})
    .use('facebook', {appId: options.facebook.appId, appSecret: options.facebook.appSecret})
  schema.add
    auth:
      facebook:
        id: String
        username: String
        aT: String
        createdAt: Date
      twitter:
        id: String
        username: String
        aT: String
        aTS: String
        createdAt: Date
      google:
        id: String
        username: String
        aT: String
        rT: String
        createdAt: Date
      googleplus:
        id: String
        username: String
        aT: String
        rT: String
        createdAt: Date
  _findOrCreateUser = (params, done) ->
    return done(new Error("couldn't log you in"))  if not params.service or not params.session or not params.data
    self = @
    async.waterfall [ (cb) ->
      userFindParams = {}
      userFindParams['auth.' + params.service + '.id'] = params.data.id
      if params.session?.auth?.userId?
        async.parallel
          user: (cb) -> self.findById params.session.auth.userId, cb
          occupyingUser: (cb) -> self.findOne userFindParams, cb
        , (err, results) ->
          return cb(new Error('No user is linked to the user in the session. How is this person logged in?')) if not results.user?
          return cb(new Error('Another user has already linked this account'))  if (results.occupyingUser and results.occupyingUser.id isnt params.session.auth.userId)
          cb err, results.user, false
      else
        async.waterfall [ (cb) ->
          self.findOne userFindParams, cb
        , (user, cb) ->
          return cb null, user  if user?
          return cb null, null  unless params.data.email?
          self.findOne { 'email': params.data.email }, (err, user) ->
            return cb err, (if user? then user else null)
        , (user, cb) ->
          return cb null, user, false if user?
          self.create {}, (err, user) ->
            cb err, user, true
        ], cb
    , upsertToDatabase = (user, newUser, cb) ->
      async.parallel
        user: (cb) ->
          user.auth[params.service].id = params.data.id
          user.auth[params.service].username = params.data.username
          user.auth[params.service].createdAt = new Date() if newUser
          user.auth[params.service].aT = params.data.aT
          user.auth[params.service].rT = params.data.rT if params.data.rT?
          user.auth[params.service].aTS = params.data.aTS if params.data.aTS?
          user.save cb
        socialUserData: (cb) ->
          async.waterfall [ (cb) ->
            SocialUserData.findOne {_user: user._id}, cb
          , (socialUserData, cb) ->
            return cb null, socialUserData  if socialUserData?
            SocialUserData.create { _user: user._id }, (err, socialUserData) ->
              cb null, socialUserData
          , (socialUserData, cb) ->
            unless socialUserData[params.service]?.userData?
              socialUserData[params.service].userData = params.data
            else 
              for param of params.data
                socialUserData[params.service].userData[param] = params.data[param]
              socialUserData.markModified(params.service + '.userData')
            socialUserData.save cb
          ], cb
      , (err, results) ->
        cb null, user, newUser
    ], done
  schema.statics.findOrCreateUser = (service) ->
    self = @
    switch service
      when 'googlehybrid' then return (session, userAttributes) ->
        promise = @Promise()
        params =
          service: "google"
          session: session
          data: userAttributes
        params.data.id = params.data.claimedIdentifier.split('=')[1]
        params.data.username = params.data.email
        params.data.userData = {
          email: params.data.email,
          firstname: params.data.firstname,
          lastname: params.data.lastname
        }
        params.data.aT = params.data.access_token
        params.data.aTS = params.data.access_token_secret
        _findOrCreateUser.bind(self) params, (err, user, newUser) ->
          return promise.fulfill [err] if err
          session.newUser = newUser
          session.authUserData = params.data
          session.authUserData.service = params.service
          promise.fulfill user
        promise
      when 'google' then return (session, accessToken, accessTokExtra, userAttributes) ->
        promise = @Promise()
        params =
          service: "google"
          session: session
          data: userAttributes
        params.data.username = params.data.email
        params.data.aT = accessToken
        params.data.rT = accessTokExtra.refresh_token if accessTokExtra.refresh_token?
        params.data.aTE = accessTokExtra
        _findOrCreateUser.bind(self) params, (err, user, newUser) ->
          return promise.fulfill [err] if err
          session.newUser = newUser
          session.authUserData = params.data
          session.authUserData.service = params.service
          promise.fulfill user
        promise
      when 'facebook' then return (session, accessToken, accessTokExtra, fbUserMetaData) ->
        promise = @Promise()
        params =
          service: "facebook"
          session: session
          data: fbUserMetaData
        params.data.aT = accessToken
        params.data.aTE = accessTokExtra
        _findOrCreateUser.bind(self) params, (err, user, newUser) ->
          return promise.fulfill [err] if err
          session.newUser = newUser
          session.authUserData = params.data
          session.authUserData.service = params.service
          promise.fulfill user
        promise

  schema.methods._socialReqGet = (params, cb) ->
    self = @
    socialReq.getTokens (id, cb) ->
      cb
        facebook:
          access_token: self.auth.facebook.aT
        google: 
          access_token: self.auth.google.aT
          refresh_token: self.auth.google.rT
        googleplus: 
          access_token: self.auth.google.aT
    socialReq.get @.id, params, cb

  schema.methods.getSocial = (params, done) ->
    self = @
    async.waterfall [ firstTry = (cb) ->
      self._socialReqGet params, cb
    , attemptSecondTriesIfNecessary = (results, cb) ->
      firstTryHasFailures = false
      secondTryServices = []
      socialGetParams = {}
      for requestType of results
        for service of results[requestType]
          if results[requestType][service].error?
            firstTryHasFailures = true
            secondTryServices.push service  if secondTryServices.indexOf(service) is -1
            socialGetParams[requestType] = []  unless socialGetParams[requestType]?
            socialGetParams[requestType].push service
      return cb(null, results) unless firstTryHasFailures

      async.waterfall [ (cb) ->
        removeServiceFromSocialGetParams = (service) ->
          for requestType of socialGetParams
            i = socialGetParams[requestType].indexOf service
            socialGetParams[requestType].splice i, 1  if i isnt -1
            delete socialGetParams[requestType] if socialGetParams[requestType] is 0
        async.forEach secondTryServices, attemptToRefreshAccessToken = (service, cb) ->
          if service is 'google' or service is 'googleplus'
            self._refreshAccessToken 'google', (err, user) ->
              removeServiceFromSocialGetParams service  if err?
              cb()
          else
            removeServiceFromSocialGetParams service
            cb()
        , cb  
      , attemptSocialReq = (cb) ->
        return cb() if Object.keys(socialGetParams).length is 0
        self._socialReqGet socialGetParams, cb
      , mergeResults = (secondResults, cb) ->
        return secondResults null, results  if typeof secondResults is 'function'
        for requestType of secondResults
          for service of secondResults[requestType]
            results[requestType][service] = secondResults[requestType][service]
        cb(null, results)
      ], cb        
    , getSocialUserData = (results, cb) ->
      async.waterfall [ 
        (cb) -> SocialUserData.findOne {_user: self._id}, cb
      , (socialUserData, cb) ->
        return SocialUserData.create {_user: self._id}, cb  unless socialUserData?
        cb null, socialUserData
      ], (err, socialUserData) ->
        cb err, results, socialUserData
    , processResults = (results, socialUserData, cb) ->
      async.parallel
        processContacts: (cb) ->
          return cb()  unless results.contacts?
          processingFunctions = []
          Object.keys(results.contacts).forEach (service, i, keys) ->
            return  if results.contacts[service].error?
            processingFunctions.push (cb) ->
              async.filter results.contacts[service], (contact, cb) ->
                return cb contact.email?  if service is 'google'
                cb true
              , (contacts) ->
                async.sortBy contacts, (contact, cb) ->
                  return cb null, contact.entry.gd$name?.gd$familyName  if service is 'google'
                  return cb null, contact.name  if service is 'facebook'
                  cb null, null
                , (err, contacts) ->
                  done err  if err?
                  socialUserData[service] = {} unless socialUserData[service]
                  socialUserData[service].contacts = results.contacts[service] = contacts
                  cb()
          async.parallel processingFunctions, cb
        processDetails: (cb) ->
          return cb()  unless results.details?
          Object.keys(results.details).forEach (service, i, keys) ->
            return  if results.details[service].error?
            return socialUserData[service].userData = results.details[service]  unless socialUserData[service].userData?
            for param of results.details[service]
              socialUserData[service].userData[param] = results.details[service][param]
            socialUserData.markModified(service + '.userData')
          cb()
      , (err, processingResults) ->
        return cb err, results, socialUserData
    , cacheSocialUserData = (results, socialUserData, cb) ->
      async.parallel
        user: (cb) -> self.save cb
        socialUserData: (cb) -> socialUserData.save cb
      , (err, models) ->
        cb err, results
    ], done
            

  ###
  schema.on 'init', (model) ->
    socialReq.getTokens (id, cb) ->
      model.findById id, (err, user) ->
        return cb(err || new Error 'User does not exist') if err? or not user?
        cb
          facebook:
            access_token: user.auth.facebook.aT
          google: 
            access_token: user.auth.google.aT
            access_token_secret: user.auth.google.aTS###

  schema.methods._invalidateAccessToken = (service, done) ->
    return done null, @ unless @auth[service]?
    @auth[service].aT = undefined
    @auth[service].aTS = undefined
    @save done
  schema.methods._refreshAccessToken = (service, done) ->
    return done null, @ unless @auth[service]?
    unless @auth[service].rT?
      return done
        message: 'No refresh token for service ' + service + ', user needs to reauthenticate'
        code: 400
    self = @
    socialReq.getTokens (id, cb) ->
      cb
        facebook:
          access_token: self.auth.facebook.aT
        google: 
          access_token: self.auth.google.aT
          refresh_token: self.auth.google.rT
        googleplus: 
          access_token: self.auth.google.aT
    socialReq.get @.id, {tokens: [service]}, (err, results) ->
      return done err if err?
      return done results.tokens[service]?.error  if results.tokens[service]?.error
      self.auth.google.aT = results.tokens[service].access_token
      self.save done
  
  return