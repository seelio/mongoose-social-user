expect = require 'expect.js'
sinon = require 'sinon'
mongoose = require 'mongoose'
testConfig = require '../testconfig.coffee'
SocialReq = require('social-request')

describe 'Mongoose Social Plugin', () ->
  UserSchema = {}; User = {}; user = {}; socialGetSpy = {};
  before (done) ->
    mongoose.connect('mongodb://localhost/mongoose-social-user-testing')
    socialReq = new SocialReq();
    socialGetSpy = sinon.spy SocialReq.prototype, 'get', (params, cb) ->
    #   cb(null, 'results')
    UserSchema = new mongoose.Schema 
      name: String
    UserSchema.plugin require('../index.js'), 
      google: 
        clientId: testConfig.google.clientId
        clientSecret: testConfig.google.clientSecret
      facebook: 
        appId: testConfig.facebook.appId
        appSecret: testConfig.facebook.appSecret
      twitter: 
        consumerKey: testConfig.twitter.consumerKey
        consumerSecret: testConfig.twitter.consumerSecret
      linkedin: 
        apiKey: testConfig.linkedin.apiKey
        secretKey: testConfig.linkedin.secretKey
    User = mongoose.model('User', UserSchema)
    done()

  beforeEach (done) ->
    User.remove {}, () ->
      User.create [
          _id: '000000000000000000000004'
        ,
          _id: '000000000000000000000003'
          auth:
            google:
              id: '114277323590337190780'
              aT: 'iamanaccesstoken'
              rT: 'iamarefreshtoken'
        ,
          _id: '000000000000000000000005'
          auth:
            facebook:
              id: '198437102109342'
              username: 'fbusername'
              aT: 'iamasweetaccesstoken'
              userData:
                first_name: 'Will'
                last_name: 'NotStone'
      ], done

  after (done) ->
    # socialGetSpy.restore()
    User.remove {}, () ->
      done()

  describe 'installed', () ->
    it 'should add keys to user', (done) ->
      User = mongoose.model('User', UserSchema)
      user = new User()
      user.auth.facebook.id = 'abcd'
      user.auth.google.id = 'defg'
      user.auth.twitter.id = 'ghik'
      expect(user.auth.facebook.id).to.be 'abcd'
      expect(user.auth.google.id).to.be 'defg'
      expect(user.auth.twitter.id).to.be 'ghik'
      done()

  describe '#_invalidateAccessToken', () ->
    it 'should invalidate an access token for oauth2 for a given service', (done) ->
      User.findById '000000000000000000000003', (err, user) ->
        throw err if err
        expect(user.auth.google.aT).to.be.ok()
        expect(user.auth.google.rT).to.be.ok()
        user._invalidateAccessToken 'google', (err, user) ->
          expect(user.auth.google.aT).not.to.be.ok()
          expect(user.auth.google.rT).to.be.ok()
          done()

    it 'should invalidate an access token for oauth for a given service'

  describe '#_refreshAccessToken', () ->
    describe 'for oauth2', () ->
      describe 'for google', () ->
        it 'should refresh an access token', (done) ->
          User.findById '000000000000000000000003', (err, user) ->
            throw err if err
            oldAccessToken = user.auth.google.aT
            oldRefreshToken = user.auth.google.rT = testConfig.google.refresh_token
            expect(user.auth.google.aT).to.be.ok()
            expect(user.auth.google.rT).to.be.ok()
            user._refreshAccessToken 'google', (err, user) ->
              throw err if err
              expect(user.auth.google.aT).to.be.ok()
              expect(user.auth.google.aT).not.to.be oldAccessToken
              expect(user.auth.google.rT).to.be.ok()
              expect(user.auth.google.rT).to.be oldRefreshToken
              done()
        it 'should fail correctly if there is no access token', (done) ->
          User.findById '000000000000000000000003', (err, user) ->
            throw err if err
            user.auth.google.rT = null
            user._refreshAccessToken 'google', (err, user) ->
              expect(err.message).to.be 'No refresh token for service google, user needs to be redirected to authentication screen'
              done()
    it 'should refresh an access token for oauth for a given service'

  describe '#getSocial', () ->
    it 'should get and cache the requested social data', (done) ->
      @timeout(10000);
      User.findById '000000000000000000000005', (err, user) ->
        throw err  if err
        user.auth.google.aT = testConfig.google.access_token
        user.auth.google.rT = null
        user.getSocial {contacts: ['google'], details: ['google', 'googleplus']}, (err, results) ->
          throw err  if err
          expect(results.contacts.google.length).to.be.greaterThan(0)
          expect(socialGetSpy.calledWith '000000000000000000000005', {contacts: ['google'], details: ['google', 'googleplus']}).to.be.ok();
          expect(results.contacts.google.error).to.not.be.ok();
          expect(user.auth.google.contacts.length).to.be.greaterThan(0)
          expect(user.auth.google.userData.name).to.be.ok()
          expect(user.auth.google.userData.given_name).to.be.ok()
          expect(user.auth.googleplus.userData.name.givenName).to.be.ok()
          done();

    describe 'with incorrect access token', () ->
      userWithABadAccessToken = null
      beforeEach (done) ->
        User.findById '000000000000000000000005', (err, user) ->
          throw err  if err
          user.auth.google.aT = 'asdfasdfasdf'
          userWithABadAccessToken = user;
          done();
      it 'should try to refresh the access token with refresh token and refresh again', (done) ->
        @timeout(10000);
        userWithABadAccessToken.auth.google.rT = testConfig.google.refresh_token
        userWithABadAccessToken.getSocial {contacts: ['google'], details: ['google', 'googleplus']}, (err, results) ->
          throw err  if err
          expect(results.contacts.google.length).to.be.greaterThan(0)
          expect(socialGetSpy.calledWith '000000000000000000000005', {contacts: ['google'], details: ['google', 'googleplus']}).to.be.ok();
          expect(results.contacts.google.error).to.not.be.ok();
          expect(userWithABadAccessToken.auth.google.contacts.length).to.be.greaterThan(0)
          expect(userWithABadAccessToken.auth.google.userData.name).to.be.ok()
          expect(userWithABadAccessToken.auth.google.userData.given_name).to.be.ok()
          expect(userWithABadAccessToken.auth.googleplus.userData.name.givenName).to.be.ok()
          done();
      it 'should pass an error without a refresh token', (done) ->
        @timeout(10000);
        userWithABadAccessToken.auth.google.rT = null
        userWithABadAccessToken.getSocial {contacts: ['google'], details: ['google']}, (err, results) ->
          expect(err.message).to.be 'No refresh token for service google, user needs to be redirected to authentication screen'
          done();

  describe '.findOrCreateUser', () ->
    promiseScope =
      Promise: () ->
        promise =
          next: {}
          fulfill: (result) ->
            @next(result)
          then: (fn) ->
            @next = fn
        return promise
    describe 'for google', () ->
      session = {}
      userAttributes = {}
      accessToken = {}
      accessTokExtra = {}
      beforeEach (done) ->
        userAttributes =
          authenticated: true,
          id: '111111111111111111',
          name: 'David Jsa'
          given_name: 'David',
          email: 'kiesent@gmail.com',
          family_name: 'Jsa',
        accessToken = 'ya29.AHES6ZTbGtzk9pWGtw33ypFcf7B7RYn6zowhe1htQ9pFwnA'
        accessTokExtra = 
          token_type: 'Bearer',
          expires_in: 3600,
          id_token: 'eyJhbGciOiJSUzI1NiIsImtpZCI6ImNlMjNjZTgzOWE2YmU5ODdkMzhmNGM0YjU2NjQ1MDQyZjAxNThiYjYifQ.eyJpc3MiOiJhY2NvdW50cy5nb29nbGUuY29tIiwidmVyaWZpZWRfZW1haWwiOiJ0cnVlIiwiaWQiOiIxMTQyNzczMjM1OTAzMzcxOTA3ODAiLCJhdWQiOiI1ODIzNjEwMDE5NjUuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJjaWQiOiI1ODIzNjEwMDE5NjUuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJlbWFpbCI6ImtpZXNlbnRAZ21haWwuY29tIiwidG9rZW5faGFzaCI6Im5wRklsU0d2Z0ZjSGpLSl9maHdCaHciLCJpYXQiOjEzNTMzNTg3ODAsImV4cCI6MTM1MzM2MjY4MH0.VKWx2FSVMtpozX3-ahd2vAIcAH-f2e8XUzdWJWp-nJQL6OlU0y2H031l42XY97e5juSuwhSpGMs_8y-ZAE8hecDAK4kaRJiHNCHW_G8qNzP3LSUPPVIRzaDTX0ZItQBGr8ddM0_taYuRo7eZk-duPZpIrgC4pk1oQUbesEHulDQ',
          refresh_token: '1/vioj8dHiZzxz7oK8wlEoIErBow0uno8-M4ky-ShwHhc'
        session = {}
        done()
      describe 'if there is no user in the session', () ->
        it 'should create a user from everyAuth and add the access tokens', (done) ->
          User.findOrCreateUser('google').bind(promiseScope)(session, accessToken, accessTokExtra, userAttributes)
            .then (user) ->
              expect(session.newUser).to.be.ok()
              expect(session.authUserData.given_name).to.be.ok()
              expect(user.auth.google.id).to.be '111111111111111111'
              expect(user.auth.google.aT).to.be 'ya29.AHES6ZTbGtzk9pWGtw33ypFcf7B7RYn6zowhe1htQ9pFwnA'
              expect(user.auth.google.rT).to.be '1/vioj8dHiZzxz7oK8wlEoIErBow0uno8-M4ky-ShwHhc'
              expect(user.auth.google.userData.aTE.refresh_token).to.be '1/vioj8dHiZzxz7oK8wlEoIErBow0uno8-M4ky-ShwHhc'
              expect(user.auth.google.userData.email).to.be 'kiesent@gmail.com'
              expect(user.auth.google.userData.given_name).to.be 'David'
              expect(user.auth.google.userData.family_name).to.be 'Jsa'
              expect(user.auth.google.createdAt).to.be.ok()
              done()
        it 'should find an existing user from everyAuth if there is no user in the session, and update access tokens', (done) ->
          userAttributes.id = '114277323590337190780'
          accessTokExtra.refresh_token = null
          User.findOrCreateUser('google').bind(promiseScope)(session, accessToken, accessTokExtra, userAttributes)
            .then (user) ->
              expect(session.newUser).not.to.be.ok()
              expect(user.auth.google.id).to.be '114277323590337190780'
              expect(user.auth.google.aT).to.be 'ya29.AHES6ZTbGtzk9pWGtw33ypFcf7B7RYn6zowhe1htQ9pFwnA'
              expect(user.auth.google.rT).to.be 'iamarefreshtoken'
              done()
      describe 'if there is a user in the session', () ->
        beforeEach () ->
          session =
              auth:
                userId: '000000000000000000000004'
        it 'should link a google id', (done) ->
          userAttributes.id = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          User.findOrCreateUser('google').bind(promiseScope)(session, accessToken, accessTokExtra, userAttributes)
            .then (user) ->
              expect(session.newUser).not.to.be.ok()
              expect(user.id).to.be '000000000000000000000004'
              expect(user.auth.google.username).to.be('kiesent@gmail.com')
              expect(user.auth.google.id).to.be('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
              User.findById '000000000000000000000004', (err, user) ->
                expect(user.id).to.be '000000000000000000000004'
                expect(user.auth.google.username).to.be('kiesent@gmail.com')
                expect(user.auth.google.id).to.be('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
              done()
        it 'should not link a currently used google id', (done) ->
          userAttributes.id = '114277323590337190780'
          User.findOrCreateUser('google').bind(promiseScope)(session, accessToken, accessTokExtra, userAttributes)
            .then (err) ->
              expect(err).to.be.ok()
              expect(err.length).to.be(1)
              done()

    describe 'for facebook', () ->
      session = {}
      accessToken = {}
      accessTokExtra = {}
      fbUserMetaData = {}
      beforeEach (done) ->
        accessToken = 'AAAHOA4xnZBxMBAK4ZCI2PjnhqlMLhMd0aZA9lHpgPMwFN7rw6lOV5HBditZB5Hch2rFIdsNrQOR08qcR2ZAeZA5uAVzK2NNgQZD'
        accessTokExtra = 
          expires: '5183854'
        fbUserMetaData = 
          id: '2209612'
          name: 'David Jsa'
          first_name: 'David'
          last_name: 'Jsa'
          link: 'http://www.facebook.com/daviddjsa'
          username: 'daviddjsa'
          location: 
            id: '105479049486624'
            name: 'Ann Arbor Michigan'
          quotes: '"But Father not my will but yours be done." Jesus Christ'
          gender: 'male'
          timezone: -4
          locale: 'en_US'
          verified: true
          updated_time: '2012-10-16T01:30:42+0000'
        session = {}
        done()
      describe 'if there is no user in the session', () ->
        it 'should create a user from everyAuth', (done) ->
          User.findOrCreateUser('facebook').bind(promiseScope)(session, accessToken, accessTokExtra, fbUserMetaData)
            .then (user) ->
              expect(session.authUserData.first_name).to.be.ok()
              expect(session.newUser).to.be.ok()
              expect(user.auth.facebook.id).to.be '2209612'
              expect(user.auth.facebook.username).to.be('daviddjsa')
              expect(user.auth.facebook.userData.first_name).to.be('David')
              expect(user.auth.facebook.aT).to.be 'AAAHOA4xnZBxMBAK4ZCI2PjnhqlMLhMd0aZA9lHpgPMwFN7rw6lOV5HBditZB5Hch2rFIdsNrQOR08qcR2ZAeZA5uAVzK2NNgQZD'
              expect(user.auth.facebook.createdAt).to.be.ok()
              fbUserMetaData.email = 'ddjsa@umich.edu'
              delete fbUserMetaData.gender
              User.findOrCreateUser('facebook').bind(promiseScope)(session, accessToken, accessTokExtra, fbUserMetaData)
                .then (user) ->
                  expect(user.auth.facebook.userData.gender).to.be('male')
                  expect(user.auth.facebook.userData.email).to.be('ddjsa@umich.edu')
                  done()
        it 'should find an existing user from everyAuth if there is no user in the session and update access tokens', (done) ->
          fbUserMetaData.id = '198437102109342'
          User.findOrCreateUser('facebook').bind(promiseScope)(session, accessToken, accessTokExtra, fbUserMetaData)
            .then (user) ->
              expect(session.newUser).not.to.be.ok()
              expect(user.auth.facebook.id).to.be '198437102109342'
              expect(user.auth.facebook.aT).to.be 'AAAHOA4xnZBxMBAK4ZCI2PjnhqlMLhMd0aZA9lHpgPMwFN7rw6lOV5HBditZB5Hch2rFIdsNrQOR08qcR2ZAeZA5uAVzK2NNgQZD'
              done()
        it 'should find an existing user from everyAuth if there is no user in the session, and update cached data', (done) ->
          fbUserMetaData.id = '198437102109342'
          delete fbUserMetaData.first_name
          fbUserMetaData.last_name = 'Stone'
          User.findOrCreateUser('facebook').bind(promiseScope)(session, accessToken, accessTokExtra, fbUserMetaData)
            .then (user) ->
              expect(session.newUser).not.to.be.ok()
              expect(user.auth.facebook.userData.first_name).to.be 'Will'
              expect(user.auth.facebook.userData.last_name).to.be 'Stone'
              User.findOne {'auth.facebook.id': '198437102109342'}, (err, user) ->
                expect(user.auth.facebook.userData.first_name).to.be 'Will'
                expect(user.auth.facebook.userData.last_name).to.be 'Stone'
                expect(user.auth.facebook.userData.gender).to.be 'male'
                done()
      describe 'if there is a user in the session', () ->
        beforeEach () ->
          session =
              auth:
                userId: '000000000000000000000004'
        it 'should link a facebook id', (done) ->
          User.findOrCreateUser('facebook').bind(promiseScope)(session, accessToken, accessTokExtra, fbUserMetaData)
            .then (user) ->
              expect(session.newUser).not.to.be.ok()
              expect(user.id).to.be '000000000000000000000004'
              expect(user.auth.facebook.username).to.be('daviddjsa')
              expect(user.auth.facebook.id).to.be('2209612')
              User.findById '000000000000000000000004', (err, user) ->
                expect(user.id).to.be '000000000000000000000004'
                expect(user.auth.facebook.username).to.be('daviddjsa')
                expect(user.auth.facebook.id).to.be('2209612')
              done()
        it 'should not link a currently used facebook id', (done) ->
          fbUserMetaData.id = '198437102109342'
          User.findOrCreateUser('facebook').bind(promiseScope)(session, accessToken, accessTokExtra, fbUserMetaData)
            .then (err) ->
              expect(err).to.be.ok()
              expect(err.length).to.be(1)
              done()