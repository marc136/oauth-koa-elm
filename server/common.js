/**
 * Common helper functions
 */

function encodeParams (params) {
  return Object.keys(params)
    .map(key => `${key}=${encodeURIComponent(params[key])}`)
    .join('&')
}

function copyProperties (obj, ...properties) {
  const result = {}
  properties.forEach(prop => {
    result[prop] = obj[prop]
  })
  return result
}

module.exports = { copyProperties, encodeParams }
