(function() {
  var CaseLogic, S, TaskLogic, Uri, app, bodyParser, compression, cookieParser, env, express, favicon, http, ipAddress, logger, morgan, oneDay, path, port, request, server, serverStartTime, settings, url, _;

  express = require('express');

  app = express();

  http = require('http');

  url = require('url');

  path = require('path');

  favicon = require('serve-favicon');

  logger = require('tracer').colorConsole();

  morgan = require('morgan');

  cookieParser = require('cookie-parser');

  bodyParser = require('body-parser');

  compression = require('compression');

  request = require('request');

  settings = require('./src/com/redhat/ascension/settings/settings');

  Uri = require('jsuri');

  _ = require('lodash');

  S = require('string');

  TaskLogic = require('./src/com/redhat/ascension/rest/taskLogic');

  CaseLogic = require('./src/com/redhat/ascension/rest/caseLogic');

  env = 'development';

  serverStartTime = (new Date()).getTime();

  port = settings.getEnvVar('OPENSHIFT_INTERNAL_PORT') || settings.getEnvVar('OPENSHIFT_NODEDIY_PORT') || settings.getEnvVar('OPENSHIFT_NODEJS_PORT') || 3000;

  ipAddress = settings.getEnvVar('OPENSHIFT_NODEJS_IP') || settings.getEnvVar('OPENSHIFT_NODEDIY_IP') || '127.0.0.1';

  if (process.env['OPENSHIFT_DATA_DIR'] != null) {
    env = 'production';
    logger.info("Env is Openshift/" + env + ", ip: " + ipAddress + " port: " + port);
  } else {
    logger.info("Env is " + env + ", ip: " + ipAddress + " port: " + port);
  }

  app = express();

  oneDay = 86400000;

  app.set('views', path.join(__dirname, 'public'));

  app.set('view engine', 'jade');

  app.set('ipAddress', ipAddress);

  app.set('port', port);

  app.use(morgan('dev'));

  app.use(bodyParser.json({
    strict: false
  }));

  app.use(bodyParser.urlencoded({
    extended: false
  }));

  app.use(cookieParser());

  app.use(express["static"](path.join(__dirname, 'public')));

  if (app.get("env") === "dev") {
    app.use(function(err, req, res, next) {
      logger.error(err.stack || err);
      res.status(err.status || 500);
      return res.render("error", {
        message: err.message,
        error: err
      });
    });
  }

  app.use(function(err, req, res, next) {
    logger.error(err.stack || err);
    res.status(err.status || 500);
    return res.render("error", {
      message: err.message,
      error: {}
    });
  });

  app.get("/", function(req, res) {
    return res.render('index.jade', {
      env: env,
      uid: serverStartTime
    });
  });

  app.get("/maketasks", function(req, res) {
    var opts;
    opts = {};
    return CaseRules.reset().then(function(data) {
      return res.send(data);
    }, function(err) {
      return res.send(err);
    });
  });

  app.get("/tasks", function(req, res) {
    var opts;
    opts = {
      ssoUsername: req.query['ssoUsername'],
      limit: _.parseInt(req.query['limit']) || 100
    };
    return TaskLogic.fetchTasks(opts).then(function(data) {
      return res.send(data);
    }, function(err) {
      return res.send(err);
    });
  });

  app.get("/cases", function(req, res) {
    var opts, roles;
    roles = req.query['roles'];
    if (roles !== '' && roles !== null) {
      roles = _.map(req.query['roles'].split(','), function(r) {
        return r.toUpperCase();
      }) || [];
    }
    opts = {
      ssoUsername: req.query['ssoUsername'],
      limit: _.parseInt(req.query['limit']) || 100,
      roles: roles
    };
    return CaseLogic.fetchCases(opts).then(function(data) {
      return res.send(data);
    })["catch"](function(err) {
      res.status(500);
      return res.send({
        error: err.message
      });
    }).done();
  });

  app.get("/task/:_id", function(req, res) {
    var opts;
    opts = {
      _id: req.params['_id']
    };
    return TaskLogic.fetchTask(opts).then(function(data) {
      return res.send(data);
    }, function(err) {
      return res.send(err);
    });
  });

  app.post("/task/:_id", function(req, res) {
    var opts;
    opts = {
      _id: req.params['_id'],
      action: req.query['action'],
      userInput: req.query['userInput']
    };
    logger.debug("Attempting to post to task: " + opts._id + " with user: " + opts.userInput);
    return TaskLogic.updateTask(opts).then(function(data) {
      return res.send(data);
    })["catch"](function(err) {
      return res.send(err);
    }).done();
  });

  app.get("/case/:caseNumber/comments", function(req, res) {
    return req.pipe(request("" + settings.UDS_URL + "/case/" + req.params.caseNumber + "/comments")).pipe(res);
  });

  app.post("/case/:caseNumber/comments/:commentType", function(req, res) {
    var opts, theUrl;
    opts = {
      uri: "" + settings.UDS_URL + "/case/" + req.params.caseNumber + "/comments/" + req.params.commentType,
      method: "POST",
      headers: req.headers
    };
    theUrl = url.parse(opts.uri);
    logger.debug("Posting to: " + opts.uri);
    logger.debug("with form data: " + (JSON.stringify(req.body)));
    logger.debug("with headers: " + (JSON.stringify(opts.headers)));
    return req.pipe(request.post({
      url: opts.uri,
      headers: opts.headers,
      json: req.body
    })).pipe(res);
  });

  app.get("/case/:caseNumber", function(req, res) {
    return req.pipe(request("" + settings.UDS_URL + "/case/" + req.params.caseNumber)).pipe(res);
  });

  app.get("/user/metadata/:type", function(req, res) {
    var uri;
    logger.debug("type: " + req.params.type + ", query: " + (unescape(req.query.where)));
    uri = settings.UDS_URL + ("/user/metadata/" + req.params.type) + "?where=" + escape(req.query.where) + "&resourceProjection=Minimal";
    logger.debug("Proxying to: " + uri);
    return req.pipe(request(uri)).pipe(res);
  });

  app.get("/user/:input", function(req, res) {
    return req.pipe(request("" + settings.UDS_URL + "/user/" + req.params.input)).pipe(res);
  });

  app.get("/user", function(req, res) {
    var uri;
    uri = new Uri(settings.UDS_URL);
    uri.setPath("/user");
    _.each(req.query, function(value, key) {
      return uri.addQueryParam(key, unescape(value));
    });
    logger.debug("Proxying to: " + uri.toString());
    return req.pipe(request(uri.toString())).pipe(res);
  });

  process.on('SIGTERM', function() {
    logger.info("SIGTERM, exiting.");
    return server.close();
  });

  server = void 0;

  server = app.listen(app.get('port'), app.get('ipAddress'), function() {
    return console.log("Started Express on port: " + (server.address().port));
  });

}).call(this);
