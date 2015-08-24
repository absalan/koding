querystring = require 'querystring'

{ generateUrl
  deepObjectExtend
  generateRandomEmail
  generateRandomString
  generateRandomUsername
  generateDefaultRequestParams } = require '../index'


generateCheckTokenRequestBody = (opts = {}) ->

  defaultBodyObject =
    token : generateRandomString()

  deepObjectExtend defaultBodyObject, opts

  return defaultBodyObject


generateCheckTokenRequestParams = (opts = {}) ->

  url  = generateUrl
    route : '-/teams/validate-token'

  body = generateCheckTokenRequestBody()

  params               = { url, body }
  defaultRequestParams = generateDefaultRequestParams params
  requestParams        = deepObjectExtend defaultRequestParams, opts
  # after deep extending object, encodes body param to a query string
  requestParams.body   = querystring.stringify requestParams.body

  return requestParams


generateJoinTeamRequestBody = (opts = {}) ->

  username = generateRandomUsername()

  defaultBodyObject =
    slug                : "testcompany#{generateRandomString(10)}"
    email               : generateRandomEmail()
    token               : ''
    allow               : 'true'
    agree               : 'on'
    username            : username
    password            : 'testpass'
    redirect            : ''
    newsletter          : 'true'
    alreadyMember       : 'false'
    passwordConfirm     : 'testpass'

  deepObjectExtend defaultBodyObject, opts

  return defaultBodyObject


generateJoinTeamRequestParams = (opts = {}) ->

  url  = generateUrl
    route : '-/teams/join'

  body = generateJoinTeamRequestBody()

  params               = { url, body }
  defaultRequestParams = generateDefaultRequestParams params
  requestParams        = deepObjectExtend defaultRequestParams, opts
  # after deep extending object, encodes body param to a query string
  requestParams.body   = querystring.stringify requestParams.body

  return requestParams


generateGetTeamRequestParams = (opts = {}) ->

  { groupSlug } = opts
  url  = generateUrl
    route : "-/team/#{groupSlug}"

  params               = { url }
  defaultRequestParams = generateDefaultRequestParams params
  requestParams        = deepObjectExtend defaultRequestParams, opts
  # after deep extending object, encodes body param to a query string
  requestParams.body   = querystring.stringify requestParams.body

  return requestParams


generateGetTeamMembersRequestBody = (opts = {}) ->

  defaultBodyObject =
    limit : '10'
    token : ''

  deepObjectExtend defaultBodyObject, opts

  return defaultBodyObject


generateGetTeamMembersRequestParams = (opts = {}) ->

  { groupSlug } = opts
  delete opts.groupSlug

  url  = generateUrl
    route : "-/team/#{groupSlug}/members"

  body = generateGetTeamMembersRequestBody()

  params               = { url, body }
  defaultRequestParams = generateDefaultRequestParams params
  requestParams        = deepObjectExtend defaultRequestParams, opts
  # after deep extending object, encodes body param to a query string
  requestParams.body   = querystring.stringify requestParams.body

  return requestParams


generateCreateTeamRequestBody = (opts = {}) ->

  username    = generateRandomUsername()
  invitees    = "#{generateRandomEmail('koding.com')},#{generateRandomEmail('gmail.com')}"
  companyName = "testcompany#{generateRandomString(10)}"

  defaultBodyObject =
    slug           :  companyName
    email          :  generateRandomEmail()
    agree          :  'on'
    allow          :  'true'
    domains        :  'koding.com, gmail.com'
    invitees       :  invitees
    redirect       :  ''
    username       :  username
    password       :  'testpass'
    newsletter     :  'true'
    companyName    :  companyName
    alreadyMember  :  'false'
    passwordConfirm:  'testpass'

  deepObjectExtend defaultBodyObject, opts

  return defaultBodyObject


# overwrites given options in the default params
generateCreateTeamRequestParams = (opts = {}) ->

  url  = generateUrl
    route : '-/teams/create'

  body = generateCreateTeamRequestBody()

  params               = { url, body }
  defaultRequestParams = generateDefaultRequestParams params
  requestParams        = deepObjectExtend defaultRequestParams, opts
  # after deep extending object, encodes body param to a query string
  requestParams.body   = querystring.stringify requestParams.body

  return requestParams


module.exports = {
  generateGetTeamRequestParams
  generateJoinTeamRequestParams
  generateCreateTeamRequestParams
  generateCheckTokenRequestParams
  generateGetTeamMembersRequestParams
}

