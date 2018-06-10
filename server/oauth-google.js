const fetch = require('node-fetch')

const redirect_uri = `http://localhost:3000/auth/google` // ${key} is not allowed :(

const config = require('../config').google
const { copyProperties, encodeParams } = require('./common')

function getUrl (key) {
  // scopes: https://developers.google.com/identity/protocols/googlescopes
  return (
    'https://accounts.google.com/o/oauth2/v2/auth?' +
    encodeParams({
      client_id: config.client_id,
      redirect_uri,
      // response_type: 'token',
      response_type: 'code',
      scope: 'email',
      state: key
      // prompt: 'consent select_account' // if omitted, prompt is only shown the first time
    })
  )
}

function asyncGetEmail (ctx, key) {
  const code = ctx.request.body.code

  const prefix = `google:${key}`

  // STEP 1: Retrieve an access token
  // https://developers.google.com/identity/protocols/OAuth2WebServer#exchange-authorization-code
  console.log(`${prefix} auth`, { code })
  let url =
    'https://www.googleapis.com/oauth2/v4/token?' +
    encodeParams({
      client_id: config.client_id,
      client_secret: config.client_secret,
      code,
      grant_type: 'authorization_code',
      redirect_uri
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
        let url = 'https://www.googleapis.com/userinfo/v2/me'
        return fetch(url, {
          headers: {
            Authorization: `Bearer ${access_token}`,
            Accept: 'application/json'
          }
        })
      })
      .then(res => res.json())
      .then(json => {
        /* success: {
            name: String, given_name: String, family_name: String,
            picture: String, gender: String, link: g+ profile,
            email: String, verified_email: Bool
            id: String } // */

        if (json.verified_email && json.email && json.email.trim()) {
          console.log(`${prefix} received a usable email address`)
          const result = copyProperties(json, 'email', 'name')
          result.avatar = json.picture
          ctx.body = result
        } else {
          return Promise.reject({
            error: 'unusable email address',
            error_description: `A verified email address is needed, but it was '${copyProperties(json, 'email', 'verified_email')}'`
          })
        }
      })
      .catch(errorHandler(prefix, ctx))
  )
}

function errorHandler (prefix, ctx) {
  return function _googleErrorHandler (reason) {
    switch (reason.error) {
      case 'invalid_grant':
      case 'invalid_request':
        console.error(`${prefix} Misconfiguration ${reason.error}`)
        ctx.status = 500
        ctx.body = reason
        break

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

module.exports = { getUrl, asyncGetEmail }
