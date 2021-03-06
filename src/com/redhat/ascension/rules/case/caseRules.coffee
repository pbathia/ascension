nools             = require 'nools'
logger            = require('tracer').colorConsole()
prettyjson        = require 'prettyjson'
salesforce        = require '../../db/salesforce'
settings          = require '../../settings/settings'
Q                 = require 'q'
#DbOperations    = require '../db/dbOperations'
MongoOperations   = require '../../db/MongoOperations'
TaskUtils         = require '../../utils/taskUtils'
TaskStateEnum     = require '../enums/TaskStateEnum'
TaskTypeEnum      = require '../enums/TaskTypeEnum'
TaskOpEnum        = require '../enums/TaskOpEnum'
EntityOpEnum        = require '../enums/ResourceOpEnum'
_                 = require 'lodash'
moment            = require 'moment'
MongoOps          = require '../../db/MongoOperations'
mongoose          = require 'mongoose'
mongooseQ         = require('mongoose-q')(mongoose)
ObjectId          = mongoose.Types.ObjectId
request           = require 'request'
S                 = require 'string'
#MongoClient   = require('mongodb').MongoClient
#Server        = require('mongodb').Server

KcsRules          = require './kcsRules'
UserLogic         = require '../../rest/userLogic'
TaskCounts        = require '../../db/taskCounts'
ScoringLogic      = require '../../rules/scoring/scoringLogic'
TaskLogic         = require '../../rest/taskLogic'

CaseRules = {}

CaseRules.caseFields = """
  AccountId,
  Account_Number__c,
  CaseNumber,
  Collaboration_Score__c,
  Comment_Count__c,
  CreatedDate,
  Created_By__c,
  FTS_Role__c,
  FTS__c,
  Last_Breach__c,
  PrivateCommentCount__c,
  PublicCommentCount__c,
  SBT__c,
  SBR_Group__c,
  Severity__c,
  Status,
  Subject,
  Internal_Status__c,
  Strategic__c,
  Tags__c,
  (SELECT
    Id,
    Linking_Mechanism__c,
    Type__c,
    Resource_Type__c
  FROM
    Case_Resource_Relationships__r)
"""

CaseRules.fetchCaseSoql = """
SELECT
  #caseFields#
FROM
  Case
WHERE
  CaseNumber = #caseNumber#
"""
CaseRules.fetchCasesSoql = """
SELECT
  #caseFields#
FROM
  Case
WHERE
  OwnerId != '00GA0000000XxxNMAS'
  #andStatusCondition#
  AND Internal_Status__c != 'Waiting on Engineering'
  AND Internal_Status__c != 'Waiting on PM'
LIMIT 1000
"""

CaseRules.fetchCase = (opts) ->
  soql = @fetchCaseSoql.replace /#caseFields#/, @caseFields
  soql = soql.replace /#caseNumber#/, "'#{opts.caseNumber}'"
  Q.nfcall(salesforce.querySf, {'soql': soql, single: true})

CaseRules.fetchCases = () ->
  soql = @fetchCasesSoql.replace /#caseFields#/, @caseFields
  soql = soql.replace /#andStatusCondition#/, " AND Status = 'Waiting on Red Hat'"
  Q.nfcall(salesforce.querySf, {'soql': soql})

# Uses UDS UQL
#CaseRules.fetchCases = () ->
#  deferred = Q.defer()
#  opts =
#    url: "#{settings.UDS_URL}/case"
#    json: true
#    qs:
#      #where: 'ownerId ne "00GA0000000XxxNMAS" and (status is "Waiting on Red Hat" and isFTS is true)'
#      where: 'ownerId ne "00GA0000000XxxNMAS" and (status is "Waiting on Red Hat") and (internalStatus ne "Waiting on Engineer" and internalStatus ne "Waiting on PM")'
#      limit: 500
#  request opts, (err, incMess, body) ->
#    if err
#      deferred.reject err
#    else
#      # UDS responses will be an array of 'resource' objects containing the case itself
#      deferred.resolve _.chain(body).pluck('resource').value()
#  deferred.promise

#CaseRules.unassignedCase = (c) -> c['internalStatus '] is 'Unassigned'
CaseRules.intStatus = (c, intStatus) -> c['internalStatus'] is intStatus

CaseRules.taskExistsWithEntityOp = (tasks, intStatus) ->
  _.find(tasks, (t) -> t['resourceOp'] is intStatus) isnt false

CaseRules.findTask = (c, tasks, resourceOp) ->
  _.find(tasks, (t) -> t['resourceOp'] is resourceOp)

# Given an existing task, updates the metadata of the task given the case and returns a promise
CaseRules.updateTaskFromCase = (c, t) ->
  logger.warn("Existing #{c['internalStatus']} Task: #{c['caseNumber']}, updating metadata")
  updateHash = TaskUtils.taskFromCaseUpdateHash(t, c)
  _.assign t, updateHash
  TaskUtils.updateTaskFromCase(t, c)

CaseRules.normalizeCase = (c) ->
  status: c['status'] || c['Status']
  internalStatus: c['internalStatus'] || c['Internal_Status__c']
  severity: c['severity'] || c['Severity__c']
  sbrs: c['sbrs'] || TaskUtils.parseSfArray(c['SBR_Group__c'])
  tags: c['tags'] || TaskUtils.parseSfArray(c['Tags__c'])
  sbt: c['sbt'] || c['SBT__c'] || null
  created: c['created'] || c['CreatedDate']
  collaborationScore: c['collaborationScore'] || c['Collaboration_Score__c']
  caseNumber: c['caseNumber'] || c['CaseNumber']
  subject: c['subject'] || c['Subject']
  linkedSolutionCount: _.filter(c['Case_Resource_Relationships__r']?['records'] || [], (r) -> r['Resource_Type__c'] is 'Solution' and _.contains(['Link', 'Link;Pin'], r['Type__c']))

CaseRules.match = (opts) ->
  self = CaseRules
  deferred = Q.defer()
  cases = opts['cases'] || []
  existingTasks = opts['existingTasks'] || []

  # Resulting promises from this iteration
  promises = []

  # Hash by Case Number
#  casesBycaseNumber = _.object(_.map(cases, (c) -> [c['caseNumber'], c]))

  # There may be more than one result per bid, so can't do a straight hash
  existingTasksByBid = _.groupBy existingTasks, (t) -> t['bid']

  logger.debug "Matching #{cases.length} cases"
  _.each cases, (c) ->
    #c = self.normalizeCase(x)

    logger.debug "Attempting to match case: #{c['caseNumber'] || c['CaseNumber']}, intStatus: #{c['internalStatus']}"

    #######################################################################################################
    # Where there is an unassigned case and no associated task
    # Narrow the search space by only passing tasks matching this case
    #######################################################################################################
    if self.intStatus(c, 'Unassigned')
      resourceOp = EntityOpEnum.OWN
      # Represents the task to test the logic against existing unassigned Cases/tasks
      existingTask = self.findTask c, existingTasksByBid[c['caseNumber']], resourceOp.name

      if existingTask?
        promises.push self.updateTaskFromCase(c, existingTask)
      else
        t = TaskUtils.makeTaskFromCase(c)
        logger.debug("Discovered new Unassigned case: #{t['bid']} setting the task to #{resourceOp.display}.")
        t.taskOp = TaskOpEnum.OWN_TASK.name
        t.resourceOp = resourceOp.name
        promises.push TaskUtils.saveRuleTask(t)

    #######################################################################################################
    # Waiting on Owner tasks
    #######################################################################################################
    else if self.intStatus(c, 'Waiting on Owner')
      resourceOp = EntityOpEnum.UPDATE
      # Represents the task to test the logic against existing unassigned Cases/tasks
      existingTask = self.findTask c, existingTasksByBid[c['caseNumber']], resourceOp.name

      if existingTask?
        promises.push self.updateTaskFromCase(c, existingTask)
      else
        t = TaskUtils.makeTaskFromCase(c)
        logger.debug("Discovered new Waiting on Owner case: #{t['bid']} setting the task to #{resourceOp.display}.")
        t.taskOp = TaskOpEnum.OWN_TASK.name
        t.resourceOp = resourceOp.name
        promises.push TaskUtils.saveRuleTask(t)

    #######################################################################################################
    # Waiting on Contributor tasks
    #######################################################################################################
    else if self.intStatus(c, 'Waiting on Contributor')
      resourceOp = EntityOpEnum.CONTRIBUTE
      # Represents the task to test the logic against existing unassigned Cases/tasks
      existingTask = self.findTask c, existingTasksByBid[c['caseNumber']], resourceOp.name

      if existingTask?
        promises.push self.updateTaskFromCase(c, existingTask)
      else
        t = TaskUtils.makeTaskFromCase(c)
        logger.debug("Discovered new Waiting on Contributor case: #{t['bid']} setting the task to #{resourceOp.display}.")
        t.taskOp = TaskOpEnum.OWN_TASK.name
        t.resourceOp = resourceOp.name
        promises.push TaskUtils.saveRuleTask(t)

    #######################################################################################################
    # Waiting on Collaboration tasks
    #######################################################################################################
    else if self.intStatus(c, 'Waiting on Collaboration')
      resourceOp = EntityOpEnum.COLLABORATE
      # Represents the task to test the logic against existing unassigned Cases/tasks
      existingTask = self.findTask c, existingTasksByBid[c['caseNumber']], resourceOp.name

      if existingTask?
        promises.push self.updateTaskFromCase(c, existingTask)
      else
        t = TaskUtils.makeTaskFromCase(c)
        logger.debug("Discovered new Waiting on Collaboration case: #{t['bid']} setting the task to #{resourceOp.display}.")
        t.taskOp = TaskOpEnum.OWN_TASK.name
        t.resourceOp = resourceOp.name
        promises.push TaskUtils.saveRuleTask(t)

    #######################################################################################################
    # Tasks for this case relating to Waiting on Engineering
    #######################################################################################################
    else if self.intStatus(c, 'Waiting on Engineering')
      resourceOp = EntityOpEnum.FOLLOW_UP_WITH_ENGINEERING
      existingTask = self.findTask c, existingTasksByBid[c['caseNumber']], resourceOp.name
      if existingTask?
        promises.push self.updateTaskFromCase(c, existingTask)
      else
        logger.debug("Discovered new Waiting on Engineering case: #{t['bid']} setting the task to #{resourceOp.display}.")
        t = TaskUtils.makeTaskFromCase(c)
        t.taskOp = TaskOpEnum.OWN_TASK.name
        t.resourceOp = resourceOp.name
        promises.push TaskUtils.saveRuleTask(t)

    #######################################################################################################
    # Tasks for this case relating to Waiting on Sales
    #######################################################################################################
    else if self.intStatus(c, 'Waiting on Sales')
      resourceOp = EntityOpEnum.FOLLOW_UP_WITH_SALES
      existingTask = self.findTask c, existingTasksByBid[c['caseNumber']], resourceOp.name

      if existingTask?
        promises.push self.updateTaskFromCase(c, existingTask)
      else
        t = TaskUtils.makeTaskFromCase(c)
        logger.debug("Discovered new Waiting on Engineering case: #{t['bid']} setting the task to #{resourceOp.display}.")
        t.taskOp = TaskOpEnum.OWN_TASK.name
        t.resourceOp = resourceOp.name
        promises.push TaskUtils.saveRuleTask(t)
    else
      logger.warn "Did not create task from case: #{prettyjson.render c}"

  logger.debug "CaseRules.match resolving #{promises.length} promises"
  deferred.resolve promises
  deferred.promise

CaseRules.reset = () ->
  deferred = Q.defer()

  MongoOperations.reset()
  .then(->
    CaseRules.fetchCases()
  )
  .then((cases) ->

    # Normalize all cases before passing them to the respective rules
    normalizedCases = _.map cases, (c) -> CaseRules.normalizeCase(c)

    [CaseRules.match({cases: normalizedCases}), KcsRules.match({cases: normalizedCases})]
  )
  .spread((casePromises, kcsPromises) ->
    logger.debug "Received #{casePromises.length} caseResults and #{kcsPromises} kcs results"
    Q.allSettled(_.flatten([casePromises, kcsPromises]))
  )
  .then((results) ->
    logger.debug "Completed manipulating #{results.length} tasks"

    # Fetch all open tasks to score them
    TaskLogic.fetchTasks({})
  )
  .then((tasks) ->

    # TODO, remove the & filter in the future when UDS is fixed
    # Get a unique list of SBRs and grab the users in those SBRs.  For now filter out all sbrs containing & since UDS can't handle
    #.filter((x) -> not S(x).contains('&'))
    sbrs = _.chain(tasks).pluck('sbrs').flatten().unique().value()

    uqlParts = []
    _.each sbrs, (sbr) -> uqlParts.push "(sbrName is \"#{sbr}\")"
    uql = uqlParts.join(' OR ')
    logger.debug "Generated uql: #{uql}"

    [tasks, UserLogic.fetchUsersUql({where: uql})]
  )
  .spread((tasks, users) ->

    userIds = _.chain(users).pluck('id').unique().value()
    logger.debug "Discovered #{userIds} userIds"

    [tasks, users, TaskCounts.getTaskCounts(userIds)]
  )
  .spread((tasks, users, userTaskCounts) ->

    logger.debug "Determining potential owners"

    # TODO -- the scoreTask should return a promise
    # Create a convenience method to score tasks which will return an array of promises which will be updates
    # to mongoose
    updatePromises = []
    # Remember t here is the mongoose representation, the actual object is t._doc
    _.each tasks, (t) ->
      #logger.debug prettyjson.render t._doc
      ScoringLogic.determinePotentialOwners
        task: t
        users: users
        userTaskCounts: userTaskCounts
      potentialOwners = t.potentialOwners
      $update =
        $set:
          potentialOwners: potentialOwners

      updatePromises.push MongoOps['models']['task'].findOneAndUpdate({_id: new ObjectId(t._id)}, $update).execQ()

    logger.debug "Generated #{updatePromises.length} update promises"

    Q.allSettled(updatePromises)
  )
  .then((results) ->
    logger.debug "Completed setting potential owners on #{results.length} tasks"
  )
  .catch((err) ->
    logger.error err.stack
    deferred.reject err
  )
  .done(->
    deferred.resolve()
  )

  deferred.promise

module.exports = CaseRules

if require.main is module
  MongoOperations.init({mongoDebug: true})
  db = mongoose['connection']
  db.on 'error', logger.error.bind(logger, 'connection error:')
  dbPromise = Q.defer()
  db.once 'open', () ->
    dbPromise.resolve()

  dbPromise.promise
  .then(->
    MongoOperations.defineCollections()
    MongoOperations.reset()
  )
  .then(->
    CaseRules.fetchCases()
  )
  .then((cases) ->

    # Normalize all cases before passing them to the respective rules
    normalizedCases = _.map cases, (c) -> CaseRules.normalizeCase(c)

    [CaseRules.match({cases: normalizedCases}), KcsRules.match({cases:  normalizedCases})]
  )
#  .spread((cases, users, taskCounts) ->
#    logger.debug "taskCounts: #{prettyjson.render taskCounts}"
#
#    [CaseRules.match({cases: cases}), KcsRules.match({cases: cases})]
#  )
  .spread((casePromises, kcsPromises) ->
    logger.debug "Received #{casePromises.length} caseResults and #{kcsPromises} kcs results"
    Q.allSettled(_.flatten([casePromises, kcsPromises]))
  )
  #.then((promises) ->
  #  logger.debug "Received #{promises.length} promises"
  #  Q.allSettled(promises)
  #)
  .then((results) ->
    logger.debug "Completed manipulating #{results.length} tasks"

    # Fetch all open tasks to score them
    TaskLogic.fetchTasks({})
  )
  .then((tasks) ->

    # Get a unique list of SBRs and grab the users in those SBRs
    sbrs = _.chain(tasks).pluck('sbrs').flatten().unique().value()

    uqlParts = []
    _.each sbrs, (sbr) -> uqlParts.push "(sbrName is \"#{sbr}\")"
    uql = uqlParts.join(' OR ')
    logger.debug "Generated uql: #{uql}"

    [tasks, UserLogic.fetchUsersUql({where: uql})]
  )
  .spread((tasks, users) ->

    userIds = _.chain(users).pluck('id').unique().value()
    logger.debug "Discovered #{userIds} userIds"

    [tasks, users, TaskCounts.getTaskCounts(userIds)]
  )
  .spread((tasks, users, userTaskCounts) ->

    logger.debug "Determining potential owners"

    # TODO -- the scoreTask should return a promise
    # Create a convenience method to score tasks which will return an array of promises which will be updates
    # to mongoose
    updatePromises = []
    # Remember t here is the mongoose representation, the actual object is t._doc
    _.each tasks, (t) ->
      #logger.debug prettyjson.render t._doc
      ScoringLogic.determinePotentialOwners
        task: t
        users: users
        userTaskCounts: userTaskCounts
      potentialOwners = t.potentialOwners
      $update =
        $set:
          potentialOwners: potentialOwners

      updatePromises.push MongoOps['models']['task'].findOneAndUpdate({_id: new ObjectId(t._id)}, $update).execQ()

    logger.debug "Generated #{updatePromises.length} update promises"

    Q.allSettled(updatePromises)
  )
  .then((results) ->
    logger.debug "Completed setting potential owners on #{results.length} tasks"
  )
  .catch((err) ->
    logger.error err.stack
  )
  .done(->
    process.exit()
  )
