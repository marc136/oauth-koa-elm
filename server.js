const crypto = require('crypto')
const fs = require('fs')
const fetch = require('node-fetch')
const route = require('koa-route')
const Koa = require('koa')
const bodyParser = require('koa-bodyparser')
const logger = require('koa-logger')
const serve = require('koa-static')

// static resources
const config = require('./config')

// authentication providers
const auth = {
  github: require('./server/oauth-github'),
  google: require('./server/oauth-google')
}

// "database"
const db = {}

/**
 * behavior functions
 */

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

function getIndexWithKeyFromQueryParamsGoogle (ctx) {
  const key = ctx.query.state
  if (!key) {
    ctx.throw(400, 'Query state should contain a key')
    return
  }

  return getIndexWithKey(ctx, key)
}

function getUrl (ctx, provider) {
  // stat that is needed for session rehydration
  const body = ctx.request.body

  const key = randomString(24)
  const data = {
    provider,
    ts: Date.now(),
    sessionState: body
  }

  console.log(`${provider}:${key} getUrl`)
  switch (provider) {
    case 'github':
      ctx.body = auth.github.getUrl(key)
      break

    case 'google':
      console.log(auth.google.getUrl(key))
      ctx.body = auth.google.getUrl(key)
      break

    default:
      console.log('request body', ctx.request.body)
      ctx.throw(400, `Unknown OAuth2.0 provider '${provider}'`)
      return
  }

  db[key] = data
  console.log('db', db)
}

function getEmail (ctx, provider, key) {
  const code = ctx.request.body.code
  if (!code) {
    console.log('request body', ctx.request.body)
    ctx.throw(400, 'Body did not contain a code')
    return
  }

  switch (provider) {
    case 'github':
      return auth.github.asyncGetEmail(ctx, key)

    case 'google':
      return auth.google.asyncGetEmail(ctx, key)

    default:
      ctx.throw(400, `Unknown OAuth2.0 provider '${provider}'`)
  }
}

/**
 * Helper functions
 */

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
app.use(route.get('/auth/github/:key', getIndexWithKey))
app.use(route.get('/auth/google', getIndexWithKeyFromQueryParamsGoogle))
app.use(route.post('/auth/:provider/:key', getEmail))
app.use(serve('public'), { defer: true })

app.listen(port)
console.log(`Listening on port ${port}`)
