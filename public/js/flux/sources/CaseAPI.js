var Marty                   = require('marty');
var _                       = require('lodash');
var Q                       = require('q');
Q.longStackSupport 			= true
var CaseSourceActions       = require('../actions/CaseSourceActions');
var AppConstants    		= require('../constants/AppConstants');

var API = Marty.createStateSource({
    type: 'http',
    getCase: function (caseNumber) {
        return Q($.ajax({url: `${AppConstants.getUrlPrefix()}/case/${caseNumber}`}).then((c) => {
            return CaseSourceActions.receiveCase(c)
        }));
    }
});

module.exports = API;