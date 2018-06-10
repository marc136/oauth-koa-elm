const fetch = require('node-fetch')

const config = require('../config').github
const { copyProperties, encodeParams } = require('./common')


function getUrl (key) {
  return (
    'https://github.com/login/oauth/authorize?' +
    encodeParams({
      client_id: config.client_id,
      scope: 'user:email',
      state: key,
      redirect_uri: `http://localhost:3000/auth/github/${key}`
    })
  )
}

function asyncGetEmail (ctx, key) {
  const code = ctx.request.body.code
  const state = ctx.request.body.state // elm or csrf?
  // TODO use key to retrieve csrf token from db and compare with state

  const prefix = `github:${key}`

  // STEP 1: Retrieve an access token
  console.log(`${prefix} auth`, { code, state })
  let url =
    'https://github.com/login/oauth/access_token?' +
    encodeParams({
      client_id: config.client_id,
      client_secret: config.client_secret,
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
          result.avatar = json.gravatar_id || json.avatar_url
          ctx.body = result
        } else {
          return Promise.reject({
            error: 'unusable email address',
            error_description: `Valid email address needed, but it was '${json.email}'`
          })
        }
      })
      .catch(errorHandler(prefix, ctx))
  )
}

function errorHandler (prefix, ctx) {
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

module.exports = { getUrl, asyncGetEmail }
