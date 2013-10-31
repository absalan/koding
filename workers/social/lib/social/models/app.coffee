jraphical   = require 'jraphical'
KodingError = require '../error'

class JAppScriptAttachment extends jraphical.Attachment
  @setSchema
    as          : String
    description : String
    content     : String
    syntax      : String

module.exports = class JApp extends jraphical.Module

  CActivity = require './activity'
  JAccount  = require './account'
  CBucket   = require './bucket'
  JReview   = require './messages/review'
  JTag      = require './tag'


  @trait __dirname, '../traits/filterable'       # brings only static methods
  @trait __dirname, '../traits/followable'
  @trait __dirname, '../traits/taggable'
  @trait __dirname, '../traits/likeable'
  @trait __dirname, '../traits/slugifiable'
  #
  {Inflector,JsPath,secure,daisy,ObjectId,ObjectRef} = require 'bongo'
  {Relationship} = jraphical

  @share()

  @set

    softDelete      : yes
    slugifyFrom     : 'title'
    slugTemplate    : 'Apps/#{slug}'

    indexes         :
      title         : 'ascending'
      slug          : 'unique'

    sharedEvents    :
      instance      : [
        { name: 'ReviewIsAdded' }
      ]
    sharedMethods   :
      instance      : [
        'follow', 'unfollow', 'delete', 'review',
        'like', 'checkIfLikedBefore', 'fetchLikedByes',
        'fetchFollowersWithRelationship', 'install',
        'fetchFollowingWithRelationship', 'fetchCreator',
        'fetchRelativeReviews', 'approve'
      ]
      static        : [
        'one', 'create', 'someWithRelationship', 'updateAllSlugs'
        'some', 'each', 'fetchAllAppsData'
      ]

    schema          :
      identifier    :
        type        : String
        set         : (value)-> value?.trim()
        required    : yes
      title         :
        type        : String
        set         : (value)-> value?.trim()
        required    : yes
      body          : String
      attachments   : [JAppScriptAttachment]
      counts        :
        followers   :
          type      : Number
          default   : 0
        installed   :
          type      : Number
          default   : 0
      thumbnails    : [Object]
      screenshots   : [Object]
      versions      : [String]
      meta          : require "bongo/bundles/meta"
      manifest      : Object
      type          :
        type        : String
        enum        : ["Wrong type specified!",["web-app", "add-on", "server-stack", "framework"]]
        default     : "web-app"
      originId      : ObjectId
      originType    : String
      approved      :
        type        : Boolean
        default     : false
      repliesCount  :
        type        : Number
        default     : 0
      slug          : String
      slug_         : String

    relationships   :
      creator       :
        targetType  : JAccount
        as          : "related"
      review        :
        targetType  : JReview
        as          : "review"
      activity      :
        targetType  : CActivity
        as          : 'activity'
      follower      :
        targetType  : JAccount
        as          : 'follower'
      likedBy       :
        targetType  : JAccount
        as          : 'like'
      participant   :
        targetType  : JAccount
        as          : ['author','reviewer','user']
      tag           :
        targetType  : JTag
        as          : 'tag'

  @getAuthorType =-> JAccount

  @create = secure (client, data, callback)->

    console.log "creating the JApp"

    {connection:{delegate}} = client

    if not (delegate.checkFlag('app-publisher') or delegate.checkFlag('super-admin'))
      callback new KodingError 'You are not authorized to publish apps.'
      return no

    if data.identifier.indexOf('com.koding.apps.') isnt 0
      callback new KodingError 'Invalid identifier provided.'
      return no

    JApp.one
      identifier : data.identifier
    , (err, app)=>
      if err
        callback err
      else
        # Override author info with delegate
        data.manifest.authorNick = delegate.getAt 'profile.nickname'
        data.manifest.author = "#{delegate.getAt 'profile.firstName'} #{delegate.getAt 'profile.lastName'}"

        if app
          if String(app.originId) isnt String(delegate.getId()) and not delegate.can('approve', this)
            callback new KodingError 'Identifier belongs to different user.'
          else
            console.log "alreadyPublished trying to update fields"

            if app.approved # So, this is just a new update
              # Lets look if already waiting for approve
              JApp.one
                identifier : "waits.for.approve:#{data.identifier}"
              , (err, approval_app)=>
                if approval_app
                  # means no one approved the update before this update
                  approval_app.update
                    $set:
                      title     : data.title
                      body      : data.body
                      manifest  : data.manifest
                      approved  : no
                  , (err)->
                    if err then callback err
                    else callback null, approval_app

                else
                  approval_slug = "#{app.slug}-#{data.manifest.version}-waits-for-approve"
                  approval_app = new JApp
                    title       : data.title
                    body        : data.body
                    manifest    : data.manifest
                    originId    : delegate.getId()
                    slug        : approval_slug
                    slug_       : approval_slug
                    originType  : delegate.constructor.name
                    identifier  : "waits.for.approve:#{data.identifier}"

                  approval_app.save (err)->
                    if err
                      callback err
                    else
                      callback null, app

            else
              if not data.manifest.version
                callback new KodingError 'Version is not provided.'
              else
                curVersions = app.data.versions
                versionExists = (curVersions[i] for i in [0..curVersions.length] when curVersions[i] is data.manifest.version).length

              if versionExists
                callback new KodingError 'Version already exists, update version to publish.'
              else
                app.update
                  $set:
                    title     : data.title
                    body      : data.body
                    manifest  : data.manifest
                    approved  : no # After each update on an app we need to reapprove it
                  $addToSet   :
                    versions  : data.manifest.version
                , (err)->
                  if err then callback err
                  else callback null, app

        else
          app = new JApp
            title       : data.title
            body        : data.body
            manifest    : data.manifest
            originId    : delegate.getId()
            originType  : delegate.constructor.name
            identifier  : data.identifier
            versions    : [data.manifest.version]

          app.createSlug (err, slug)->
            if err
              callback err
            else
              app.slug   = slug.slug
              app.slug_  = slug.slug
              app.save (err)->
                if err
                  callback err
                else
                  app.addCreator delegate, (err)->
                    if err
                      callback err
                    else
                      callback null, app

  install: secure ({connection}, callback)->
    {delegate} = connection
    {constructor} = @
    unless delegate instanceof constructor.getAuthorType()
      callback new Error 'Only instances of JAccount can install apps.'
    else
      Relationship.one
        sourceId: @getId()
        targetId: delegate.getId()
        as: 'user'
      , (err, installedBefore)=>
        if err
          callback err
        else
          unless installedBefore
            # If itsn't an approved app so we dont need to create activity
            if @getAt 'approved'
              @addParticipant delegate, {as:'user', respondWithCount: yes}, (err, docs, count)=>
                if err
                  callback err
                else
                  @update ($set: 'counts.installed': count), (err)=>
                    if err then callback err
                    else
                      Relationship.one
                        sourceId: @getId()
                        targetId: delegate.getId()
                        as: 'user'
                      , (err, relation)=>
                        if err then callback err
                        else
                          CBucket.addActivities relation, @, delegate, null, (err)=>
                            if err
                              callback err
                            else
                              callback null
            else
              callback new KodingError 'App is not approved so activity is not created.'
          else
            callback null

  approve: secure ({connection}, state = yes, callback)->

    {delegate} = connection
    {constructor} = @
    unless delegate instanceof constructor.getAuthorType()
      callback new KodingError 'Only instances of JAccount can approve apps.'
    else
      unless delegate.checkFlag 'super-admin'
        callback new KodingError 'Only Koding Application Admins can approve apps.'
      else
        if @getAt('identifier').indexOf('waits.for.approve:') is 0
          identifier = @getAt('identifier').replace 'waits.for.approve:', ''

          JApp.one
            identifier:identifier
          , (err, target)=>
            if err
              callback err
            else

              if target
                newVersion = @getAt 'manifest.version'

                if not newVersion
                  callback new KodingError 'Version is not provided.'
                else
                  curVersions = target.data.versions
                  versionExists = (curVersions[i] for i in [0..curVersions.length] when curVersions[i] is newVersion).length

                  if versionExists
                    callback new KodingError 'Version already approved, update version to reapprove.'
                  else
                    target.update
                      $set:
                        title     : @getAt 'title'
                        body      : @getAt 'body'
                        manifest  : @getAt 'manifest'
                        meta      : createdAt: new Date()
                        approved  : yes
                      $addToSet   :
                        versions  : @getAt 'manifest.version'
                    , (err)->
                      if err
                        console.log err
                        callback err
                      else
                        # @delete We can delete the temporary JApp (@) here.
                        callback null, target

              else
                callback new KodingError "Target (already approved application) not found!"

        else
          @update ($set: approved: state), (err)=>
            callback err

  # Do not return not approved apps
  @one$ = secure (client, selector, options, callback)->
    {delegate} = client.connection
    [options, callback] = [callback, options] unless callback
    @one selector, options, (err, app)->
      if err or not app
        return callback err
      else unless app.approved
        if (delegate.checkFlag 'super-admin') or   \
           (delegate.checkFlag 'app-publisher' and \
            delegate.getId().equals app.originId)
          return callback null, app
        return callback new KodingError 'No such application.'
      callback null, app

  getDefaultSelector = (client, selector)->
    {delegate} = client.connection
    selector or= {}

    # Just show approved apps to regular users
    unless delegate.checkFlag 'super-admin'
      selector.approved = yes

    # If delegate is a publisher one can see its apps
    # even they are not approved yet.
    if not (delegate.checkFlag 'super-admin') \
       and (delegate.checkFlag 'app-publisher')
      selector.$or = [
        {approved: yes}
        {originId: delegate.getId()}
      ]
      delete selector.approved
    return selector

  @some$: @someWithRelationship
  @someWithRelationship: secure (client, selector, options, callback)->
    selector = getDefaultSelector client, selector
    options  or= {}
    options.limit = Math.min(options.limit or 0, 10)

    @some selector, options, (err, apps)=>
      @markInstalled client, apps, (err, apps)=>
        @markFollowing client, apps, callback

  @each$: secure (client, selector, fields, options, callback)->
    selector = getDefaultSelector client, selector
    @each selector, fields, options, callback

  @fetchAllAppsData: secure (client, selector, callback)->
    selector = getDefaultSelector client, selector
    apps     = []
    @each selector, {}, {}, (err, app)=>
      return callback err  if err
      if app then apps.push app
      else callback err, apps

  @markInstalled = secure (client, apps, callback)->
    Relationship.all
      targetId  : client.connection.delegate.getId()
      as        : 'user'
      sourceType: 'JApp'
    , (err, relationships)->
      apps.forEach (app)->
        app.installed = no
        for relationship, index in relationships
          if app._id is relationship.sourceId
            app.installed = yes
            relationships.splice index,1
            break
      callback err, apps

  delete: secure ({connection:{delegate}}, callback)->

    if delegate.can 'delete', this
      @remove callback

  review: secure (client, reviewData, callback)->
    {delegate} = client.connection
    unless delegate instanceof JAccount
      callback new Error 'Log in required!'
    else
      review = new JReview body: reviewData
      exempt = delegate.checkFlag('exempt')
      if exempt
        review.isLowQuality = yes
      review
        .sign(delegate)
        .save (err)=>
          if err
            callback err
          else
            delegate.addContent review, (err)->
              if err then console.log 'error adding content', err
            @addReview review,
              flags:
                isLowQuality : exempt
            , (err, docs)=>
              if err
                callback err
              else
                if exempt
                  callback null, comment
                else
                  Relationship.count
                    sourceId                  : @getId()
                    as                        : 'review'
                    'data.flags.isLowQuality' : $ne: yes
                  , (err, count)=>
                    if err
                      callback err
                    else
                      @update $set: repliesCount: count, (err)=>
                        if err
                          callback err
                        else
                          callback null, review
                          @fetchCreator (err, origin)=>
                            if err
                              console.log "Couldn't fetch the origin for app."
                            else
                              @emit 'ReviewIsAdded', {
                                origin
                                subject       : ObjectRef(@).data
                                actorType     : 'reviewer'
                                actionType    : 'review'
                                replier       : ObjectRef(delegate).data
                                reply         : ObjectRef(review).data
                                repliesCount  : count
                                relationship  : docs[0]
                              }
                              @follow client, emitActivity: no, (err)->
                              @addParticipant delegate, 'reviewer', (err)-> #TODO: what should we do with this error?

  fetchRelativeReviews:({offset, limit, before, after}, callback)->
    limit  ?= 10
    offset ?= 0
    if before? and after?
      callback new KodingError "Don't use before and after together."
    selector = timestamp:
      if before? then  $lt: before
      else if after? then $gt: after
    options = {sort: timestamp: -1}
    if limit > 0
      options.limit = limit
    if offset > 0
      options.skip = offset
    @fetchReviews selector, options, callback
