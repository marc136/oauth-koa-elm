const crypto = require('crypto')
const fs = require('fs')
const fetch = require('node-fetch')
const route = require('koa-route')
const Koa = require('koa')
const bodyParser = require('koa-bodyparser')
const logger = require('koa-logger')
const serve = require('koa-static')

// static resources
const github = require('./config')

const db = {}

// behavior functions
function getIndexWithKey (ctx, key) {
  return new Promise((resolve, reject) => {
    fs.readFile('public/index.html', { encoding: 'utf8' }, (err, content) => {
      if (err) {
        ctx.throw(500, err)
        return reject(err)
      }

      const data = db[key]
      console.log(data)
      if (data) {
        content = content.replace(
          '/* INSERT_DATA */',
          `data = JSON.parse('${JSON.stringify(data.sessionState)}');`
        )
      }
      ctx.type = 'html'
      ctx.body = content
      resolve(ctx)
    })
  })
}

function getUrl (ctx, provider) {
  // stat that is needed for session rehydration
  const body = ctx.request.body

  switch (provider) {
    case 'github':
      // csrf token, maybe use https://www.npmjs.com/package/uuid ?
      const key = randomString(24)
      db[key] = {
        provider: 'github',
        ts: Date.now(),
        sessionState: body
      }
      console.log('db', db)

      ctx.body =
        'https://github.com/login/oauth/authorize?' +
        encodeParams({
          client_id: github.client_id,
          scope: 'user:email',
          state: key,
          redirect_uri: `http://localhost:3000/auth/github/${key}`
          // redirect_uri: `localhost:3000/auth/github`//?transaction=${key}`
        })
      break

    default:
      console.log('request body', ctx.request.body)
      ctx.throw(400, 'Unknown OAuth2.0 provider')
  }
}

function getEmail (ctx, key) {
  const code = ctx.request.body.code
  const state = ctx.request.body.state // elm or csrf?
  // TODO use key to retrieve csrf token from db and compare with state

  const prefix = `github:${key}`

  // STEP 1: Retrieve an access token
  console.log(`${prefix} auth`, { code, state })
  let url =
    'https://github.com/login/oauth/access_token?' +
    encodeParams({
      client_id: github.client_id,
      client_secret: github.client_secret,
      code,
      state
    })

  return (
    fetch(url, {
      method: 'POST',
      headers: { Accept: 'application/json' }
    })
      .then(res => res.json())
      .then(json => {
        /* success: {
            access_token: String,
            token_type: 'bearer',
            scope: 'user:email' } // */

        if (json.access_token) {
          console.log(`${prefix} received an access token`)
          return json.access_token
        } else {
          return Promise.reject(json)
        }
      })
      // STEP 2: Query user information
      .then(access_token => {
        let url = 'https://api.github.com/user'
        return fetch(url, {
          headers: {
            Authorization: `token ${access_token}`,
            Accept: 'application/json'
          }
        })
      })
      .then(res => res.json())
      .then(json => {
        /* success: {
            login: String, id: Int, node_id: Base64String,
            avatar_url: String, gravatar_id: '',
            name: String, email: String
            ... } // */

        if (json.email && json.email.trim()) {
          console.log(`${prefix} received a usable email address`)
          const result = copyProperties(json, 'email', 'name')
          result.avatar = json.gravatar_id.trim() || json.avatar_url
          ctx.body = result
        } else {
          return Promise.reject({
            error: 'unusable email address',
            error_description: `Valid email address needed, but it was '${json.email}'`
          })
        }
      })
      .catch(gitHubErrorHandler(prefix, ctx))
  )
}

function gitHubErrorHandler (prefix, ctx) {
  return function _gitHubErrorHandler (reason) {
    switch (reason.error) {
      /* troubleshooting help:
          - https://developer.github.com/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/
          - https://developer.github.com/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/
        // */
      case 'incorrect_client_credentials':
      case 'redirect_uri_mismatch':
      case 'application_suspended':
        console.error(`${prefix} Misconfiguration ${reason.error}`)
        ctx.status = 500
        delete reason.state
        ctx.body = reason
        break

      case 'bad_verification_code':
        ctx.status = 401 // Unauthorized
        delete reason.state
        ctx.body = reason
        break

      case 'access_denied': // User did not give us access
      case 'unusable_email': // own error message
        ctx.status = 401 // Unauthorized
        delete reason.state
        ctx.body = reason
        break

      case undefined:
      case null:
        ctx.throw(500, reason)

      default:
        ctx.throw(500, reason)
    }
  }
}

function copyProperties (obj, ...properties) {
  const result = {}
  properties.forEach(prop => {
    result[prop] = obj[prop]
  })
  return result
}

function encodeParams (params) {
  return Object.keys(params)
    .map(key => `${key}=${encodeURIComponent(params[key])}`)
    .join('&')
}

function randomString (len) {
  if (!Number.isInteger(len)) len = 8

  return crypto.randomBytes(Math.ceil(len / 2)).toString('hex').slice(0, len)
}

/**
 * Program starts below
 */

const port = process.env.PORT || 3000

console.log('Starting server')

const app = new Koa()
app.use(logger())
app.use(
  bodyParser({
    onerror: function _bodyParserOnError (err, ctx) {
      console.error('err', err)
      ctx.throw(422, 'body parse error')
    }
  })
)

app.use(route.post('/auth/:provider/get-url', getUrl))
app.use(route.post('/auth/github/:key', getEmail))
app.use(route.get('/auth/github/:key', getIndexWithKey))
app.use(serve('public'), { defer: true })

app.listen(port)
console.log(`Listening on port ${port}`)
