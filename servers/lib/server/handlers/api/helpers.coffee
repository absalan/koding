errors   = require './errors'
koding   = require '../../bongo'

KONFIG   = require 'koding-config-manager'
Jwt      = require 'jsonwebtoken'

SUGGESTED_USERNAME_MIN_LENGTH = 4
SUGGESTED_USERNAME_MAX_LENGTH = 15

sendApiError = (res, error) ->

  response  = { error }
  response ?= 'API Error'
  return res.status(error.status ? 403).send response


sendApiResponse = (res, data) ->

  response = { data }
  return res.status(200).send response


fetchAccount = (username, callback) ->

  koding.models.JAccount.one { 'profile.nickname': username }, (err, account) ->

    if err or not account
      return callback errors.internalError

    callback null, account


fetchGroup = (slug, callback) ->

  koding.models.JGroup.one { slug }, (err, group) ->

    if err
      return callback errors.internalError

    unless group
      return callback errors.groupNotFound

    callback null, group


fetchUserRolesFromSession = (session, callback) ->

  { groupName, username } = session

  fetchGroup groupName, (err, group) ->
    return callback err  if err

    fetchAccount username, (err, account) ->
      return callback err  if err

      group.fetchRolesByAccount account, (err, roles) ->
        return callback errors.internalError  if err

        callback null, roles ? []


checkApiAvailability = (options, callback) ->

  { JGroup }   = koding.models
  { apiToken } = options

  fetchGroup apiToken.group, (err, group) ->
    return callback err  if err

    unless group.isApiEnabled is true
      return callback errors.apiIsDisabled

    return callback null


isSuggestedUsernameLengthValid = (suggestedUsername) ->

  return SUGGESTED_USERNAME_MIN_LENGTH <= suggestedUsername?.length <= SUGGESTED_USERNAME_MAX_LENGTH


isUsernameLengthValid = (username) ->

  { JUser } = koding.models
  { minLength, maxLength } = JUser.getValidUsernameLengthRange()

  return minLength <= username?.length <= maxLength


validateJWTToken = (token, callback) ->

  { secret } = KONFIG.jwt

  Jwt.verify token, secret, { algorithms: ['HS256'] }, (err, decoded) ->

    { username, group } = decoded

    return callback errors.ssoTokenFailedToParse   if err
    return callback errors.invalidSSOTokenPayload  unless username
    return callback errors.invalidSSOTokenPayload  unless group
    return callback null, { username, group }


verifyApiToken = (token, callback) ->

  { JApiToken } = koding.models

  # checking if token is valid
  JApiToken.one { code: token }, (err, apiToken) ->

    return callback errors.internalError    if err
    return callback errors.invalidApiToken  unless apiToken

    checkApiAvailability { apiToken }, (err) ->
      return callback err  if err

      callback null, apiToken


verifySessionOrApiToken = (req, res, callback) ->

  { checkAuthorizationBearerHeader
    fetchSession } = require '../../helpers'

  token = checkAuthorizationBearerHeader req

  if token

    verifyApiToken token, (err, apiToken) ->
      return sendApiError res, err  if err

      # making sure subdomain is same with group slug
      unless apiToken.group in req.subdomains
        return sendApiError res, errors.invalidRequestDomain

      callback { apiToken }

  else

    fetchSession req, res, (err, session) ->

      if err or not session or not session.groupName?
        return sendApiError res, errors.unauthorizedRequest

      fetchUserRolesFromSession session, (err, roles) ->
        if err or 'admin' not in roles
          return sendApiError res, errors.unauthorizedRequest

        callback { session }


module.exports = {
  sendApiError
  verifyApiToken
  validateJWTToken
  sendApiResponse
  checkApiAvailability
  isUsernameLengthValid
  verifySessionOrApiToken
  isSuggestedUsernameLengthValid

  SUGGESTED_USERNAME_MIN_LENGTH
  SUGGESTED_USERNAME_MAX_LENGTH
}
