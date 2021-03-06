var Marty   = require('marty');
var Router  = require('../../react_components/router.jsx');
var _       = require('lodash');

var NavigationActions = Marty.createActionCreators({
    navigateToTasks: function (user, params, query) {
        //console.debug(JSON.stringify(require('../router.jsx').getParams()));
        var sso = (user.resource.sso && user.resource.sso[0]) || "rhn-support-" + user.resource.kerberos;
        var newQuery = _.extend(_.clone(query), {ssoUsername: sso});
        var taskId = (params && params.taskId) || 'list';
        var newParams = _.extend(_.clone(params), {taskId: taskId});
        navigateTo("tasks", newParams, newQuery);
    }
});

function navigateTo(route, params, query) {
    require('../../react_components/router.jsx').transitionTo(route, params, query)
}

module.exports = NavigationActions;